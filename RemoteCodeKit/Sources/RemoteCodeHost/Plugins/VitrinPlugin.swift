import Foundation
import RemoteCodeKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Vitrin as a plugin (D-117): the phone's Vitrin tab, forwarded to `vitrin hub`.
///
/// The hub is Vitrin's local control API (Vitrin's docs/HUB_API.md). While it runs it
/// writes `~/Library/Application Support/Vitrin/control.json` (`{version, port, token,
/// pid}`, mode 0600). If nobody started one, this plugin does, from the Vitrin CLI
/// the Mac app, the Claude Code plugin or `/host/install` put on the Mac. The hub stops
/// with this process (`--attached`).
///
/// Two paths are answered here instead of by the hub, because they work without one:
/// `GET /host/status` and `POST /host/install`.
public actor VitrinPlugin: HostPlugin {
    struct Control: Decodable {
        var version: Int
        var port: Int
        var token: String
        var pid: Int32
    }

    private let home: URL
    private let session: URLSession
    private let streaming: URLSession
    private var hub: Process?
    private var starting: Task<Control, Error>?

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 900
        config.timeoutIntervalForResource = 900
        config.connectionProxyDictionary = [:]
        session = URLSession(configuration: config)
        let long = URLSessionConfiguration.ephemeral
        long.timeoutIntervalForRequest = 90
        long.timeoutIntervalForResource = 24 * 3600
        long.connectionProxyDictionary = [:]
        streaming = URLSession(configuration: long)
    }

    private static func unavailable(_ message: String) -> ErrorPayload {
        ErrorPayload(code: .pluginUnavailable, message: message)
    }

    // MARK: Finding the CLI

    private var installRoot: URL {
        let env = ProcessInfo.processInfo.environment
        if let root = env["VITRIN_HOME"], !root.isEmpty { return URL(fileURLWithPath: root) }
        if let data = env["XDG_DATA_HOME"], !data.isEmpty { return URL(fileURLWithPath: data).appendingPathComponent("vitrin") }
        return home.appendingPathComponent(".local/share/vitrin")
    }

    /// Newest finished install: `<root>/<version>/node_modules/@ardasnturk/vitrin/dist/bin.js`.
    func installedCLI() -> (entry: String, version: String)? {
        let fm = FileManager.default
        guard let versions = try? fm.contentsOfDirectory(atPath: installRoot.path) else { return nil }
        let sorted = versions.filter { $0.first?.isNumber == true }
            .sorted { $0.compare($1, options: .numeric) == .orderedDescending }
        for version in sorted {
            let folder = installRoot.appendingPathComponent(version)
            let entry = folder.appendingPathComponent("node_modules/@ardasnturk/vitrin/dist/bin.js").path
            if fm.fileExists(atPath: entry), fm.fileExists(atPath: folder.appendingPathComponent(".vitrin-installed").path) {
                return (entry, version)
            }
        }
        return nil
    }

    private func shellEnvironment() async -> [String: String] {
        await LoginShellEnvironment.capture()
    }

    /// `name` on the login shell's PATH, then in the folders the Vitrin Mac app installs to.
    private func tool(_ name: String, in environment: [String: String]) -> String? {
        var folders = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        folders += ["/opt/homebrew/bin", "/usr/local/bin", installRoot.appendingPathComponent("node/bin").path, installRoot.appendingPathComponent("bin").path]
        return folders.map { "\($0)/\(name)" }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    // MARK: The hub

    private var controlURL: URL {
        home.appendingPathComponent("Library/Application Support/Vitrin/control.json")
    }

    /// The control file of a hub that is alive.
    private func liveControl() -> Control? {
        guard let data = try? Data(contentsOf: controlURL), let control = try? JSONDecoder().decode(Control.self, from: data),
              kill(control.pid, 0) == 0 else { return nil }
        return control
    }

    private func control() async throws -> Control {
        if let control = liveControl() { return control }
        if let starting { return try await starting.value }
        let task = Task { try await self.startHub() }
        starting = task
        defer { starting = nil }
        return try await task.value
    }

    private func startHub() async throws -> Control {
        guard let cli = installedCLI() else { throw Self.unavailable("Vitrin is not installed on this Mac.") }
        let environment = await shellEnvironment()
        guard let node = tool("node", in: environment) else { throw Self.unavailable("Vitrin needs Node.js 22 or newer on this Mac.") }
        try? FileManager.default.removeItem(at: controlURL)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: node)
        process.arguments = [cli.entry, "hub", "--attached"]
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw Self.unavailable("Vitrin could not start: \(error.localizedDescription)")
        }
        hub = process
        for _ in 0..<100 {
            try? await Task.sleep(for: .milliseconds(100))
            if let control = liveControl() { return control }
            if !process.isRunning { break }
        }
        process.terminate()
        throw Self.unavailable("Vitrin \(cli.version) could not start its service. It needs version 2.1 or newer.")
    }

    // MARK: Requests

    public func send(_ request: PluginRequest) async throws -> PluginResponse {
        switch request.path {
        case "/host/status": return try status()
        case "/host/install": return try await install()
        default: break
        }
        guard request.path.hasPrefix("/v1/"), !request.path.contains("..") else {
            throw ErrorPayload(code: .invalidRequest, message: "Invalid Vitrin path.")
        }
        let control = try await control()
        guard let url = URL(string: "http://127.0.0.1:\(control.port)\(request.path)") else {
            throw ErrorPayload(code: .invalidRequest, message: "Invalid Vitrin path.")
        }
        var http = URLRequest(url: url)
        http.httpMethod = ["POST", "PUT", "DELETE"].contains(request.method) ? request.method : "GET"
        http.setValue("Bearer \(control.token)", forHTTPHeaderField: "Authorization")
        if let timeout = request.timeout { http.timeoutInterval = TimeInterval(timeout) }
        if let body = request.body {
            http.httpBody = Data(body.utf8)
            http.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let range = request.range { http.setValue(range, forHTTPHeaderField: "Range") }
        do {
            let (data, response) = try await session.data(for: http)
            let reply = response as? HTTPURLResponse
            return PluginResponse(
                status: reply?.statusCode ?? 0,
                contentType: reply?.value(forHTTPHeaderField: "Content-Type"),
                contentRange: reply?.value(forHTTPHeaderField: "Content-Range"),
                body: data
            )
        } catch {
            throw Self.unavailable("Vitrin did not answer: \(error.localizedDescription)")
        }
    }

    private struct Status: Encodable {
        var installed: Bool
        var version: String?
    }

    private func status() throws -> PluginResponse {
        let cli = installedCLI()
        let body = try JSONEncoder().encode(Status(installed: cli != nil || liveControl() != nil, version: cli?.version))
        return PluginResponse(status: 200, contentType: "application/json", body: body)
    }

    // MARK: Installing

    private struct Release: Decodable {
        var tag_name: String
    }

    /// Installs the latest Vitrin CLI with Vitrin's own launcher, which checks the release against the
    /// checksums recorded in the repository. Node.js is the one thing it needs from the Mac.
    private func install() async throws -> PluginResponse {
        var environment = await shellEnvironment()
        guard let node = tool("node", in: environment), tool("npm", in: environment) != nil else {
            throw Self.unavailable("Vitrin needs Node.js 22 or newer on this Mac. Vitrin for Mac installs it for you.")
        }
        environment["PATH"] = "\((node as NSString).deletingLastPathComponent):\(environment["PATH"] ?? "")"
        var latest = URLRequest(url: URL(string: "https://api.github.com/repos/ardasnturk/vitrin/releases/latest")!)
        latest.setValue("RemoteCode", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: latest),
              let tag = (try? JSONDecoder().decode(Release.self, from: data))?.tag_name else {
            throw Self.unavailable("GitHub could not be reached.")
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("vitrin-install-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("bin"), withIntermediateDirectories: true)
        let raw = "https://raw.githubusercontent.com/ardasnturk/vitrin/\(tag)/plugins/vitrin"
        for file in ["bin/vitrin", "SHA256SUMS"] {
            guard let (data, response) = try? await URLSession.shared.data(from: URL(string: "\(raw)/\(file)")!),
                  (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw Self.unavailable("The Vitrin installer could not be downloaded.")
            }
            try data.write(to: folder.appendingPathComponent(file))
        }
        environment["VITRIN_VERSION"] = String(tag.drop { $0 == "v" })
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [folder.appendingPathComponent("bin/vitrin").path, "--version"]
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        let errors = folder.appendingPathComponent("errors.log")
        FileManager.default.createFile(atPath: errors.path, contents: nil)
        process.standardError = try FileHandle(forWritingTo: errors)
        let code: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: Self.unavailable("The Vitrin installer could not start."))
            }
        }
        guard code == 0 else {
            let tail = (try? String(contentsOf: errors, encoding: .utf8))?.suffix(300) ?? ""
            throw Self.unavailable(String(tail).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return try status()
    }

    // MARK: Events

    /// The hub's server-sent events; reconnects, across hub restarts too, until cancelled.
    public nonisolated func events() -> AsyncStream<PluginEvent> {
        AsyncStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    await self.readEvents { continuation.yield($0) }
                    try? await Task.sleep(for: .seconds(3))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func readEvents(_ yield: @Sendable (PluginEvent) -> Void) async {
        #if canImport(FoundationNetworking)
        return // URLSession.bytes is unavailable on Linux; the plugin only runs on macOS.
        #else
        guard installedCLI() != nil, let control = try? await control(),
              let url = URL(string: "http://127.0.0.1:\(control.port)/v1/events") else { return }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(control.token)", forHTTPHeaderField: "Authorization")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        guard let (bytes, response) = try? await streaming.bytes(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return }
        var event = "message"
        do {
            for try await line in bytes.lines {
                if line.hasPrefix("event:") {
                    event = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
                } else if line.hasPrefix("data:") {
                    yield(PluginEvent(plugin: PluginID.vitrin, event: event, data: line.dropFirst(5).trimmingCharacters(in: .whitespaces)))
                    event = "message"
                }
            }
        } catch {}
        #endif
    }
}
