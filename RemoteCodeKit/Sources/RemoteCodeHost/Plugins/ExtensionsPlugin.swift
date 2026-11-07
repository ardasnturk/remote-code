import Foundation
import RemoteCodeKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Settings → Extensions (D-120): which tools the Mac has, whether their tab shows, and installing
/// them. It's a plugin itself, so the Mac's Settings and the phone read the same answers.
///
/// `GET /v1/list`, `POST /v1/enabled {id, enabled}`, `POST /v1/install {id}`.
public actor ExtensionsPlugin: HostPlugin {
    struct Entry: Sendable {
        var id: String
        var name: String
        var bundle: String
        var repository: String
        /// Start of the DMG's name on GitHub, e.g. `PromoStudio` in `PromoStudio-1.6.3.dmg`.
        var asset: String
        var website: String
    }

    static let catalog = [
        Entry(id: PluginID.mrradar, name: "MRRadar", bundle: "MRRadar.app", repository: "ardasnturk/mrradar", asset: "MRRadar", website: "https://mrradar.ardasnturk.com"),
        Entry(id: PluginID.funnelradar, name: "FunnelRadar", bundle: "FunnelRadar.app", repository: "ardasnturk/funnelradar", asset: "FunnelRadar", website: "https://funnelradar.ardasnturk.com"),
        Entry(id: PluginID.vitrin, name: "Vitrin", bundle: "Vitrin.app", repository: "ardasnturk/vitrin", asset: "Vitrin", website: "https://vitrin.ardasnturk.com"),
        Entry(id: PluginID.promoStudio, name: "Promo Studio", bundle: "Promo Studio.app", repository: "ardasnturk/promo-studio", asset: "PromoStudio", website: "https://promo.ardasnturk.com"),
    ]

    /// Every release must be signed by this team; the installer refuses anything else.
    static let team = "5JMD3VSD7N"

    private let home: URL
    private let stateFile: URL
    private var disabled: Set<String>
    private var latest: [String: String] = [:]
    private var checkedAt: Date?
    private var installing: Set<String> = []
    private var listeners: [UUID: AsyncStream<PluginEvent>.Continuation] = [:]

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
        stateFile = home.appendingPathComponent("Library/Application Support/Pilothouse/extensions.json")
        disabled = (try? Data(contentsOf: stateFile)).flatMap { try? JSONDecoder().decode(Set<String>.self, from: $0) } ?? []
    }

    public func isEnabled(_ id: String) -> Bool { !disabled.contains(id) }

    func installedBundle(_ entry: Entry) -> URL? {
        [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")]
            .map { $0.appendingPathComponent(entry.bundle) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func version(of bundle: URL) -> String? {
        guard let data = try? Data(contentsOf: bundle.appendingPathComponent("Contents/Info.plist")),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        return plist["CFBundleShortVersionString"] as? String
    }

    public func list() async -> [ExtensionInfo] {
        await refreshLatest()
        return Self.catalog.map { entry in
            let bundle = installedBundle(entry)
            return ExtensionInfo(
                id: entry.id, name: entry.name, website: entry.website, installed: bundle != nil,
                version: bundle.flatMap(version), latestVersion: latest[entry.id],
                enabled: !disabled.contains(entry.id), installing: installing.contains(entry.id)
            )
        }
    }

    /// Looks on GitHub at most once an hour; the API allows few unsigned requests.
    private func refreshLatest() async {
        if let checkedAt, Date().timeIntervalSince(checkedAt) < 3600 { return }
        checkedAt = Date()
        for entry in Self.catalog {
            if let release = try? await release(of: entry) {
                latest[entry.id] = release.version
            }
        }
    }

    struct Release: Sendable {
        var version: String
        var dmg: URL
        var checksum: URL
    }

    private func release(of entry: Entry) async throws -> Release {
        struct Payload: Decodable {
            struct Asset: Decodable {
                var name: String
                var browser_download_url: URL
            }
            var tag_name: String
            var assets: [Asset]
        }
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(entry.repository)/releases/latest")!)
        request.setValue("RemoteCode", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        let version = payload.tag_name.hasPrefix("v") ? String(payload.tag_name.dropFirst()) : payload.tag_name
        let name = "\(entry.asset)-\(version).dmg"
        guard let dmg = payload.assets.first(where: { $0.name == name }),
              let checksum = payload.assets.first(where: { $0.name == name + ".sha256" }) else {
            throw ErrorPayload(code: .pluginUnavailable, message: "The latest \(entry.name) release has no Mac download.")
        }
        return Release(version: version, dmg: dmg.browser_download_url, checksum: checksum.browser_download_url)
    }

    public func setEnabled(_ id: String, _ enabled: Bool) {
        if enabled { disabled.remove(id) } else { disabled.insert(id) }
        try? FileManager.default.createDirectory(at: stateFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(disabled).write(to: stateFile, options: .atomic)
        post()
    }

    private func post() {
        for listener in listeners.values {
            listener.yield(PluginEvent(plugin: PluginID.extensions, event: "changed", data: "{}"))
        }
    }

    public func install(_ id: String) async throws {
        guard let entry = Self.catalog.first(where: { $0.id == id }) else {
            throw ErrorPayload(code: .invalidRequest, message: "Unknown extension.")
        }
        guard !installing.contains(id) else { return }
        installing.insert(id)
        post()
        defer {
            installing.remove(id)
            checkedAt = nil
            post()
        }
        #if canImport(Darwin)
        let release = try await release(of: entry)
        let folder = installedBundle(entry)?.deletingLastPathComponent() ?? URL(fileURLWithPath: "/Applications")
        try await ExtensionInstaller.install(release: release, bundle: entry.bundle, into: folder, team: Self.team)
        #else
        throw ErrorPayload(code: .pluginUnavailable, message: "Extensions install on a Mac.")
        #endif
    }

    // MARK: HostPlugin

    public func send(_ request: PluginRequest) async throws -> PluginResponse {
        struct Change: Decodable {
            var id: String
            var enabled: Bool?
        }
        switch (request.method, request.path) {
        case ("GET", "/v1/list"):
            return PluginResponse(status: 200, contentType: "application/json", body: try JSONEncoder().encode(await list()))
        case ("POST", "/v1/enabled"), ("POST", "/v1/install"):
            guard let change = request.body.flatMap({ try? JSONDecoder().decode(Change.self, from: Data($0.utf8)) }) else {
                throw ErrorPayload(code: .invalidRequest, message: "Invalid request.")
            }
            if request.path.hasSuffix("install") {
                try await install(change.id)
            } else {
                setEnabled(change.id, change.enabled ?? true)
            }
            return PluginResponse(status: 200, contentType: "application/json", body: try JSONEncoder().encode(await list()))
        default:
            throw ErrorPayload(code: .invalidRequest, message: "Invalid path.")
        }
    }

    public nonisolated func events() -> AsyncStream<PluginEvent> {
        AsyncStream { continuation in
            let id = UUID()
            Task { await self.add(id, continuation) }
            continuation.onTermination = { _ in Task { await self.remove(id) } }
        }
    }

    private func add(_ id: UUID, _ continuation: AsyncStream<PluginEvent>.Continuation) { listeners[id] = continuation }
    private func remove(_ id: UUID) { listeners[id] = nil }
}

#if canImport(Darwin)
/// Installs a release: the checksum, the signature, the team and Gatekeeper must all pass
/// before anything reaches the Applications folder.
enum ExtensionInstaller {
    static func install(release: ExtensionsPlugin.Release, bundle: String, into folder: URL, team: String) async throws {
        let fail: (String) -> ErrorPayload = { ErrorPayload(code: .pluginUnavailable, message: $0) }
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("extension-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }

        let (download, _) = try await URLSession.shared.download(from: release.dmg)
        let dmg = staging.appendingPathComponent("image.dmg")
        try FileManager.default.moveItem(at: download, to: dmg)
        let (sums, _) = try await URLSession.shared.data(from: release.checksum)
        let expected = String(decoding: sums, as: UTF8.self).split(whereSeparator: \.isWhitespace).first.map { $0.lowercased() }
        let sum = try await run("/usr/bin/shasum", ["-a", "256", dmg.path])
        guard expected != nil, sum.output.hasPrefix(expected!) else { throw fail("The download doesn't match its checksum, so nothing was installed.") }

        let mount = staging.appendingPathComponent("mount")
        let attach = try await run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path, dmg.path])
        guard attach.status == 0 else { throw fail("The disk image couldn't be opened.") }
        let staged = staging.appendingPathComponent(bundle)
        let copy = try await run("/usr/bin/ditto", [mount.appendingPathComponent(bundle).path, staged.path])
        _ = try await run("/usr/bin/hdiutil", ["detach", mount.path, "-force", "-quiet"])
        guard copy.status == 0 else { throw fail("The app couldn't be copied from the disk image.") }
        _ = try await run("/usr/bin/xattr", ["-d", "com.apple.FinderInfo", staged.path])

        let verify = try await run("/usr/bin/codesign", ["--verify", "--deep", "--strict", staged.path])
        guard verify.status == 0 else { throw fail("The app's signature is invalid, so nothing was installed.") }
        let details = try await run("/usr/bin/codesign", ["-dv", staged.path])
        guard details.output.contains("TeamIdentifier=\(team)") else { throw fail("The app isn't signed by the expected developer, so nothing was installed.") }
        let assess = try await run("/usr/sbin/spctl", ["--assess", "--type", "execute", staged.path])
        guard assess.status == 0 else { throw fail("macOS Gatekeeper rejected the app, so nothing was installed.") }

        let target = folder.appendingPathComponent(bundle)
        let previous = staging.appendingPathComponent("previous.app")
        let hadOld = FileManager.default.fileExists(atPath: target.path)
        if hadOld { try FileManager.default.moveItem(at: target, to: previous) }
        let place = try await run("/usr/bin/ditto", [staged.path, target.path])
        if place.status != 0 {
            try? FileManager.default.removeItem(at: target)
            if hadOld { try? FileManager.default.moveItem(at: previous, to: target) }
            throw fail("The app couldn't be copied to \(folder.path).")
        }
    }

    private static func run(_ tool: String, _ arguments: [String]) async throws -> (status: Int32, output: String) {
        try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = arguments
            process.standardInput = FileHandle.nullDevice
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            FileManager.default.createFile(atPath: file.path, contents: nil)
            defer { try? FileManager.default.removeItem(at: file) }
            let handle = try FileHandle(forWritingTo: file)
            process.standardOutput = handle
            process.standardError = handle
            try process.run()
            process.waitUntilExit()
            try? handle.close()
            return (process.terminationStatus, (try? String(contentsOf: file, encoding: .utf8)) ?? "")
        }.value
    }
}
#endif
