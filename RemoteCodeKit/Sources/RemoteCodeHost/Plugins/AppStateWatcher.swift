import Foundation
import RemoteCodeKit

/// What a change of an App Store version means to the person who submitted it.
public enum AppReviewStage: String, Sendable, Hashable, CaseIterable {
    case waitingForReview, inReview, approved, live, rejected

    /// App Store Connect's states, by stage; the ones between them say nothing worth a notification.
    public init?(state: String) {
        switch state {
        case "WAITING_FOR_REVIEW": self = .waitingForReview
        case "IN_REVIEW": self = .inReview
        case "ACCEPTED", "PENDING_DEVELOPER_RELEASE", "PENDING_APPLE_RELEASE": self = .approved
        case "READY_FOR_SALE", "READY_FOR_DISTRIBUTION": self = .live
        case "REJECTED", "METADATA_REJECTED", "INVALID_BINARY", "UNRESOLVED_ISSUES": self = .rejected
        default: return nil
        }
    }
}

/// The newest App Store version of one app on one platform.
struct WatchedVersion: Codable, Hashable, Sendable {
    var appId: String
    var name: String
    var platform: String
    var version: String
    var state: String
}

/// `asc-watch.json` in Vitrin's folder, shared with Vitrin for Mac, which keeps the
/// same file while Remote Code isn't watching. So a change is told once, whoever sees it.
struct AppWatchFile: Codable, Sendable {
    var owner: String
    /// Seconds since 1970.
    var checkedAt: Double
    var states: [String: WatchedVersion]
}

enum AppStates {
    /// The same read as Vitrin's app list: one paginated request covers every app of the team.
    static let arguments = ["api", "GET", "/v1/apps",
        "--query", "include=appStoreVersions",
        "--query", "fields[apps]=name,bundleId,sku,primaryLocale,appStoreVersions",
        "--query", "fields[appStoreVersions]=platform,versionString,appVersionState,appStoreState",
        "--query", "limit=200", "--query", "limit[appStoreVersions]=50", "--paginate", "--output", "json"]

    private struct Document: Decodable {
        struct Reference: Decodable { var id: String }
        struct Relationship: Decodable { var data: [Reference]? }
        struct Relationships: Decodable { var appStoreVersions: Relationship? }
        struct AppAttributes: Decodable { var name: String? }
        struct App: Decodable {
            var id: String
            var attributes: AppAttributes?
            var relationships: Relationships?
        }
        struct VersionAttributes: Decodable {
            var platform: String?
            var versionString: String?
            var appVersionState: String?
            var appStoreState: String?
        }
        struct Included: Decodable {
            var id: String
            var type: String
            var attributes: VersionAttributes?
        }
        var data: [App]
        var included: [Included]?
    }

    /// The JSON:API document as `<app id>/<platform>` → newest version; `nil` if it isn't one.
    static func snapshot(from output: String) -> [String: WatchedVersion]? {
        guard let start = output.firstIndex(where: { $0 == "{" }),
              let document = try? JSONDecoder().decode(Document.self, from: Data(output[start...].utf8)) else { return nil }
        var versions: [String: Document.VersionAttributes] = [:]
        for item in document.included ?? [] where item.type == "appStoreVersions" {
            versions[item.id] = item.attributes
        }
        var snapshot: [String: WatchedVersion] = [:]
        for app in document.data {
            for reference in app.relationships?.appStoreVersions?.data ?? [] {
                guard let attributes = versions[reference.id], let platform = attributes.platform else { continue }
                let version = attributes.versionString ?? ""
                let key = "\(app.id)/\(platform)"
                if let current = snapshot[key], version.compare(current.version, options: .numeric) != .orderedDescending { continue }
                snapshot[key] = WatchedVersion(
                    appId: app.id, name: app.attributes?.name ?? "", platform: platform, version: version,
                    state: attributes.appVersionState ?? attributes.appStoreState ?? "")
            }
        }
        return snapshot
    }

    /// What reached a new review stage. An app or platform seen for the first time isn't news, and a move
    /// inside one stage (accepted, then pending release) is told once.
    static func changes(from old: [String: WatchedVersion], to new: [String: WatchedVersion]) -> [(WatchedVersion, AppReviewStage)] {
        new.keys.sorted().compactMap { key in
            guard let before = old[key], let after = new[key], before.state != after.state,
                  let stage = AppReviewStage(state: after.state) else { return nil }
            let sameRelease = before.version == after.version
            return sameRelease && AppReviewStage(state: before.state) == stage ? nil : (after, stage)
        }
    }
}

/// Tells the user when an app of theirs moves through App Review (D-118). Reads the team's apps through
/// Vitrin every few minutes, only while the notification is on, and compares them with the last look.
actor AppStateWatcher {
    private let plugin: any HostPlugin
    private let notifications: NotificationService
    private let file: URL
    private let interval: Duration
    private var task: Task<Void, Never>?

    init(plugin: any HostPlugin, notifications: NotificationService, file: URL, interval: Duration = .seconds(300)) {
        self.plugin = plugin
        self.notifications = notifications
        self.file = file
        self.interval = interval
    }

    /// `asc-watch.json` in the folder `vitrin hub` uses.
    static func defaultFile(home: URL) -> URL {
        let support = ProcessInfo.processInfo.environment["VITRIN_APP_SUPPORT"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent("Library/Application Support/Vitrin")
        return support.appendingPathComponent("asc-watch.json")
    }

    func start() {
        guard task == nil else { return }
        // The first check waits a minute, so the app has configured the notifications by then.
        task = Task { [weak self, interval] in
            try? await Task.sleep(for: .seconds(60))
            while !Task.isCancelled {
                await self?.check()
                try? await Task.sleep(for: interval)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private struct Reply: Decodable {
        var code: Int
        var stdout: String
    }

    func check() async {
        guard await notifications.wants(.appStateChanged), let snapshot = await read() else { return }
        let previous = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(AppWatchFile.self, from: $0) }
        save(snapshot)
        // The first look only records where everything stands.
        guard let previous else { return }
        for (version, stage) in AppStates.changes(from: previous.states, to: snapshot) {
            await notifications.post(HostAlert(kind: .appStateChanged, sessionId: version.appId, folderName: version.name, detail: stage.rawValue))
        }
    }

    /// Nil while there is nothing to compare: no Vitrin, no key, no network, or a result too large for one reply.
    private func read() async -> [String: WatchedVersion]? {
        guard let body = try? JSONSerialization.data(withJSONObject: ["args": AppStates.arguments, "timeout": 120] as [String: Any]) else { return nil }
        let request = PluginRequest(plugin: PluginID.vitrin, method: "POST", path: "/v1/asc", body: String(decoding: body, as: UTF8.self), timeout: 130)
        guard let response = try? await plugin.send(request), (200..<300).contains(response.status),
              let reply = try? JSONDecoder().decode(Reply.self, from: response.body), reply.code == 0 else { return nil }
        return AppStates.snapshot(from: reply.stdout)
    }

    private func save(_ states: [String: WatchedVersion]) {
        let record = AppWatchFile(owner: "remote-code", checkedAt: Date().timeIntervalSince1970, states: states)
        guard let data = try? JSONEncoder().encode(record) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? data.write(to: file, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}
