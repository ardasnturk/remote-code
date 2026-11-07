import Foundation
import RemoteCodeKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A native Mac app with a local hub (D-119): `control.json` in its support folder holds
/// `{version, port, token, pid}` while the app or its `hub --attached` tool runs. If neither
/// runs, this plugin starts the tool from the app's bundle. The app asks that tool to end when
/// it opens, so requests look at the control file each time.
///
/// `GET /host/status` is answered here, because it must work with no app on the Mac.
public actor LocalHubPlugin: HostPlugin {
    public struct Configuration: Sendable {
        public var id: String
        public var name: String
        /// Bundle name, e.g. `MRRadar.app`.
        public var bundle: String
        /// The tool in `Contents/MacOS`.
        public var tool: String
        /// Folder in Application Support.
        public var support: String

        public init(id: String, name: String, bundle: String, tool: String, support: String) {
            self.id = id
            self.name = name
            self.bundle = bundle
            self.tool = tool
            self.support = support
        }
    }

    struct Control: Decodable {
        var version: Int
        var port: Int
        var token: String
        var pid: Int32
    }

    public nonisolated let configuration: Configuration
    private let home: URL
    private let session: URLSession
    private let streaming: URLSession
    private var hub: Process?
    private var starting: Task<Control, Error>?

    public init(_ configuration: Configuration, home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.configuration = configuration
        self.home = home
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 120
        config.connectionProxyDictionary = [:]
        session = URLSession(configuration: config)
        let long = URLSessionConfiguration.ephemeral
        long.timeoutIntervalForRequest = 3600
        long.timeoutIntervalForResource = 7 * 24 * 3600
        long.connectionProxyDictionary = [:]
        streaming = URLSession(configuration: long)
    }

    private func unavailable(_ message: String) -> ErrorPayload {
        ErrorPayload(code: .pluginUnavailable, message: message)
    }

    private var controlURL: URL {
        home.appendingPathComponent("Library/Application Support/\(configuration.support)/control.json")
    }

    /// `<bundle>/Contents/MacOS/<tool>` in the folders apps install to.
    func installedTool() -> String? {
        ["/Applications", home.appendingPathComponent("Applications").path]
            .map { "\($0)/\(configuration.bundle)/Contents/MacOS/\(configuration.tool)" }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func liveControl() -> Control? {
        guard let data = try? Data(contentsOf: controlURL), let control = try? JSONDecoder().decode(Control.self, from: data),
              kill(control.pid, 0) == 0 else { return nil }
        return control
    }

    /// True while the app itself runs the hub. It then shows Mac notifications of its own.
    public func isRunByApp() -> Bool {
        guard let control = liveControl() else { return false }
        return control.pid != hub?.processIdentifier
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
        guard let tool = installedTool() else { throw unavailable("\(configuration.name) is not installed on this Mac.") }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = ["hub", "--attached"]
        process.environment = await LoginShellEnvironment.capture()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw unavailable("\(configuration.name) could not start: \(error.localizedDescription)")
        }
        hub = process
        for _ in 0..<100 {
            try? await Task.sleep(for: .milliseconds(100))
            if let control = liveControl() { return control }
            if !process.isRunning { break }
        }
        process.terminate()
        throw unavailable("\(configuration.name) could not start its service.")
    }

    public func send(_ request: PluginRequest) async throws -> PluginResponse {
        if request.path == "/host/status" { return try status() }
        guard request.path.hasPrefix("/v1/"), !request.path.contains("..") else {
            throw ErrorPayload(code: .invalidRequest, message: "Invalid \(configuration.name) path.")
        }
        do {
            return try await forward(request)
        } catch let error as ErrorPayload {
            throw error
        } catch {
            // The hub may just have handed over to the app.
            try? await Task.sleep(for: .seconds(1))
            do {
                return try await forward(request)
            } catch {
                throw unavailable("\(configuration.name) did not answer: \(error.localizedDescription)")
            }
        }
    }

    private func forward(_ request: PluginRequest) async throws -> PluginResponse {
        let control = try await control()
        guard let url = URL(string: "http://127.0.0.1:\(control.port)\(request.path)") else {
            throw ErrorPayload(code: .invalidRequest, message: "Invalid \(configuration.name) path.")
        }
        var http = URLRequest(url: url)
        http.httpMethod = ["POST", "PUT", "DELETE"].contains(request.method) ? request.method : "GET"
        http.setValue("Bearer \(control.token)", forHTTPHeaderField: "Authorization")
        if let timeout = request.timeout { http.timeoutInterval = TimeInterval(timeout) }
        if let body = request.body {
            http.httpBody = Data(body.utf8)
            http.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: http)
        let reply = response as? HTTPURLResponse
        return PluginResponse(status: reply?.statusCode ?? 0, contentType: reply?.value(forHTTPHeaderField: "Content-Type"), body: data)
    }

    private struct Status: Encodable {
        var installed: Bool
    }

    private func status() throws -> PluginResponse {
        let body = try JSONEncoder().encode(Status(installed: installedTool() != nil || liveControl() != nil))
        return PluginResponse(status: 200, contentType: "application/json", body: body)
    }

    /// The hub's server-sent events; reconnects, across handovers too, until cancelled.
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
        guard installedTool() != nil || liveControl() != nil, let control = try? await control(),
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
                    yield(PluginEvent(plugin: configuration.id, event: event, data: line.dropFirst(5).trimmingCharacters(in: .whitespaces)))
                    event = "message"
                }
            }
        } catch {}
        #endif
    }
}
