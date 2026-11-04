import Foundation
import Observation
import RemoteCodeKit

struct VitrinProject: Decodable, Identifiable, Hashable, Sendable {
    var id: String
    var path: String
    var name: String
    var exists: Bool
    var initialized: Bool
    var bundleId: String?
    var running: Bool
}

struct VitrinHubStatus: Decodable, Sendable {
    struct Connection: Decodable, Sendable {
        var state: String
        var keyId: String?
        var name: String?
        var asc: Bool?
    }
    var api: Int
    var version: String
    var tools: [String: Bool]
    var connection: Connection
}

enum VitrinError: LocalizedError {
    case notConnected
    case message(String)

    var errorDescription: String? {
        switch self {
        case .notConnected: L.t("vitrin.notConnected")
        case .message(let text): text
        }
    }
}

/// The Vitrin tab's live state (the plugin `vitrin`, D-117): forwards requests through the Mac to Vitrin's hub and
/// follows its events. Owned by `MacConnection`.
@MainActor
@Observable
final class VitrinStore {
    private struct HostStatus: Decodable {
        var installed: Bool
        var version: String?
    }

    /// The Mac has the plugin. It can be offered, whether or not Vitrin is there yet.
    private(set) var isOffered = false
    /// Vitrin is on the Mac; the tab shows only then.
    private(set) var isAvailable = false
    private(set) var installedVersion: String?
    private(set) var hub: VitrinHubStatus?
    private(set) var projects: [VitrinProject] = []
    private(set) var isInstalling = false
    private(set) var loadError: String?
    /// The screens of the App Store Connect panel read from here.
    let panel = VitrinPanelModel()
    /// The projects opened so far, which keep their log and Claude's runs while the user looks elsewhere.
    @ObservationIgnored private var sessions: [String: ProjectSession] = [:]

    @ObservationIgnored private weak var connection: MacConnection?
    @ObservationIgnored private var subscribed = false
    /// The open Studio of each project hears its own events.
    @ObservationIgnored private var studioListeners: [String: @MainActor (String, String) -> Void] = [:]

    init() {
        panel.attach(self)
    }

    func attach(_ connection: MacConnection) {
        self.connection = connection
    }

    // MARK: Lifecycle (called by MacConnection)

    func connected(capabilities: Set<String>) async {
        subscribed = false
        isOffered = capabilities.contains(HostCapability.vitrin)
        guard isOffered else {
            isAvailable = false
            return
        }
        await refreshHost()
        if isAvailable { await start() }
    }

    func disconnected() {
        subscribed = false
    }

    private func refreshHost() async {
        guard let status: HostStatus = try? await json("GET", "/host/status") else { return }
        isAvailable = status.installed
        installedVersion = status.version
    }

    private func start() async {
        await refresh()
        guard !subscribed, let client = connection?.client else { return }
        if (try? await client.request(.pluginSubscribe(PluginRef(plugin: PluginID.vitrin)))) != nil { subscribed = true }
        await panel.refresh()
        for session in sessions.values { await session.start() }
    }

    func session(for project: VitrinProject) -> ProjectSession {
        if let open = sessions[project.id] { return open }
        let session = ProjectSession(project: project, store: self)
        sessions[project.id] = session
        return session
    }

    func refresh() async {
        do {
            hub = try await json("GET", "/v1/status", timeout: 40)
            projects = try await json("GET", "/v1/projects")
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    func handle(_ event: PluginEvent) {
        guard event.plugin == PluginID.vitrin else { return }
        switch event.event {
        case "studio":
            guard let object = (try? JSONSerialization.jsonObject(with: Data(event.data.utf8))) as? [String: Any],
                  let project = object["project"] as? String, let name = object["event"] as? String,
                  let data = object["data"] as? String else { return }
            studioListeners[project]?(name, data)
        case "projects":
            Task { self.projects = (try? await self.json("GET", "/v1/projects")) ?? self.projects }
        case "connection":
            Task {
                await self.refresh()
                await self.panel.refresh()
            }
        default:
            break
        }
    }

    func listen(to project: String, _ listener: (@MainActor (String, String) -> Void)?) {
        studioListeners[project] = listener
    }

    /// Installs the latest Vitrin on the Mac. It takes minutes: the Mac downloads about 450 MB.
    func install() async throws {
        isInstalling = true
        defer { isInstalling = false }
        _ = try await call("POST", "/host/install", timeout: 1500)
        await refreshHost()
        if isAvailable { await start() }
    }

    // MARK: Projects

    func addProject(path: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["path": path])
        let _: VitrinProject = try await json("POST", "/v1/projects", body: String(decoding: body, as: UTF8.self))
        projects = try await json("GET", "/v1/projects")
    }

    func removeProject(_ project: VitrinProject) async throws {
        try await call("DELETE", "/v1/projects/\(project.id)")
        projects.removeAll { $0.id == project.id }
        sessions[project.id] = nil
        listen(to: project.id, nil)
    }

    // MARK: Calls

    /// One request to the plugin. An answer other than 2xx, when `checked`, throws the hub's message.
    @discardableResult
    func call(_ method: String, _ path: String, body: String? = nil, range: String? = nil, timeout: TimeInterval = 60, checked: Bool = true) async throws -> PluginResponse {
        guard let client = connection?.client else { throw VitrinError.notConnected }
        let request = PluginRequest(plugin: PluginID.vitrin, method: method, path: path, body: body, range: range, timeout: Int(timeout))
        let response: ServerMessage
        do {
            response = try await client.request(.plugin(request), timeout: timeout + 10)
        } catch let error as ErrorPayload {
            throw VitrinError.message(error.message)
        }
        guard case .pluginResponse(let result) = response else {
            throw MacClientError.unexpectedResponse(response.typeName)
        }
        guard !checked || (200..<300).contains(result.status) else {
            let object = (try? JSONSerialization.jsonObject(with: result.body)) as? [String: Any]
            throw VitrinError.message(object?["error"] as? String ?? "HTTP \(result.status)")
        }
        return result
    }

    func json<T: Decodable>(_ method: String, _ path: String, body: String? = nil, timeout: TimeInterval = 60) async throws -> T {
        try JSONDecoder().decode(T.self, from: try await call(method, path, body: body, timeout: timeout).body)
    }

    struct AdsKeyPair: Decodable, Sendable {
        var publicKey: String
        var privateKey: String
    }

    /// The Apple Ads key pair, which stays on the Mac.
    func adsKeyPair() async throws -> AdsKeyPair {
        try await json("POST", "/v1/ads/keypair", body: "{}")
    }

    /// Stores a key `asc` wrote to a file on the Mac.
    func adoptKey(id: String, issuer: String, path: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["keyId": id, "issuerId": issuer, "p8Path": path])
        try await call("POST", "/v1/asc/key", body: String(decoding: body, as: UTF8.self))
    }

    private struct AscReply: Decodable {
        struct Part: Decodable {
            var id: String
            var length: Int
        }
        var code: Int
        var stdout: String
        var stderr: String
        var part: Part?
    }

    private struct AscPart: Decodable {
        var text: String
    }

    /// Runs `asc` on the Mac; large output arrives in parts.
    func asc(_ args: [String], write: Bool, timeout: TimeInterval) async throws -> (code: Int, stdout: String, stderr: String) {
        let body = try JSONSerialization.data(withJSONObject: ["args": args, "write": write, "timeout": Int(timeout)] as [String: Any])
        let reply: AscReply = try await json("POST", "/v1/asc", body: String(decoding: body, as: UTF8.self), timeout: timeout + 5)
        guard let part = reply.part else { return (reply.code, reply.stdout, reply.stderr) }
        var text = ""
        // The hub counts UTF-16 units, as JavaScript does.
        while text.utf16.count < part.length {
            let piece: AscPart = try await json("GET", "/v1/asc/part/\(part.id)?offset=\(text.utf16.count)")
            if piece.text.isEmpty { break }
            text += piece.text
        }
        return (reply.code, text, reply.stderr)
    }
}
