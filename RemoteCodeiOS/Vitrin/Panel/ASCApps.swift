// Ported from Vitrin for Mac (apps/VitrinMac/VitrinMac/Core/ASCApps.swift).
import Foundation
import Observation

/// `vitrin asc apps --json`: the team's apps from App Store Connect, with the newest App Store version per platform.
/// Mirrors packages/cli/src/commands/asc.ts; states and platforms stay strings so a newer CLI never breaks decoding.

struct ASCAppVersion: Codable, Hashable, Identifiable, Sendable {
    var id: String
    /// IOS, MAC_OS, TV_OS, VISION_OS.
    var platform: String
    var version: String
    /// READY_FOR_SALE, PREPARE_FOR_SUBMISSION, IN_REVIEW …
    var state: String
}

struct ASCApp: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var bundleId: String
    var name: String
    var sku: String
    var primaryLocale: String
    var platforms: [String]
    var versions: [ASCAppVersion]

    /// The version the sidebar shows: iOS first, else the first platform ASC listed.
    var current: ASCAppVersion? { versions.first { $0.platform == "IOS" } ?? versions.first }
    var ascURL: URL { URL(string: "https://appstoreconnect.apple.com/apps/\(id)/distribution")! }

    /// The name, the bundle id or the SKU has `query` in it.
    func matches(_ query: String) -> Bool { [name, bundleId, sku].contains { $0.matches(search: query) } }
}

extension String {
    /// What a search field means: ignoring case and accents, so "ritim" finds "RİTİM", an empty search finds everything.
    func matches(search query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return q.isEmpty || localizedStandardContains(q)
    }
}

struct ASCAppsResult: Codable, Sendable {
    var generatedAt: String
    var apps: [ASCApp]
}

/// App Store Connect's names in words, and a tone per version state.
enum ASCWords {
    static func platform(_ p: String) -> String {
        switch p {
        case "IOS": return "iOS"
        case "MAC_OS": return "macOS"
        case "TV_OS": return "tvOS"
        case "VISION_OS": return "visionOS"
        default: return p
        }
    }

    /// The state in the user's language when the catalog knows it, else readable ("Pending Apple Release").
    @MainActor static func state(_ s: String) -> String { AscText.value(s) }

    static func tone(_ state: String) -> Tone {
        switch state {
        case "READY_FOR_SALE", "READY_FOR_DISTRIBUTION", "ACCEPTED", "VALID", "ACTIVE", "ENABLED", "APPROVED", "COMPLETE", "IN_BETA_TESTING", "BETA_APPROVED": return .ok
        case "WAITING_FOR_REVIEW", "IN_REVIEW", "PENDING_DEVELOPER_RELEASE", "PENDING_APPLE_RELEASE", "PROCESSING_FOR_DISTRIBUTION", "PROCESSING_FOR_APP_STORE", "WAITING_FOR_EXPORT_COMPLIANCE", "PROCESSING", "READY_FOR_REVIEW", "IN_PROGRESS": return .info
        case "REJECTED", "DEVELOPER_REJECTED", "METADATA_REJECTED", "INVALID_BINARY", "REMOVED_FROM_SALE", "DEVELOPER_REMOVED_FROM_SALE", "UNRESOLVED_ISSUES", "FAILED", "INVALID", "EXPIRED", "REMOVED": return .err
        case "PREPARE_FOR_SUBMISSION", "READY_TO_SUBMIT", "MISSING_METADATA", "WAITING_FOR_UPLOAD", "DEVELOPER_ACTION_NEEDED", "ACTION_REQUIRED": return .warn
        default: return .neutral
        }
    }
}

/// The team's app list, read through the CLI with the account key: at launch, after the key changes, and on demand.
@MainActor @Observable final class ASCAppList {
    private(set) var apps: [ASCApp] = []
    private(set) var loading = false
    private(set) var error: String?
    private(set) var loadedAt: Date?
    private var task: Task<Void, Never>?

    func app(_ id: String?) -> ASCApp? { id.flatMap { id in apps.first { $0.id == id } } }

    /// Reads the team's apps through `asc` with whichever credential asc resolves (Vitrin's key, else asc's own
    /// login); a refresh while one runs joins it. Not connected: the list empties without an error.
    func refresh(connection: AscConnection, force: Bool = false) async {
        if let running = task { return await running.value }
        let t = Task { [self] in
            loading = true
            defer { loading = false }
            guard connection.isConnected else {
                apps = []
                error = connection.state == .missingCLI ? L.t("asc.missing") : nil
                loadedAt = nil
                return
            }
            do {
                try await AscCLI.read(Self.listArgs, force: force) { entry in
                    apps = Self.apps(from: entry.doc)
                    error = nil
                    loadedAt = entry.fetchedAt
                }
            } catch {
                self.error = (error as? AscCLI.Failure)?.message ?? error.localizedDescription
            }
        }
        task = t
        await t.value
        task = nil
    }

    /// One paginated `GET /v1/apps` with the App Store versions included; `fields[apps]` must name the relationship
    /// or the sparse fieldset drops it, and `createdAt` is not a field ASC accepts for appStoreVersions.
    static let listArgs = ["api", "GET", "/v1/apps",
        "--query", "include=appStoreVersions",
        "--query", "fields[apps]=name,bundleId,sku,primaryLocale,appStoreVersions",
        "--query", "fields[appStoreVersions]=platform,versionString,appVersionState,appStoreState",
        "--query", "limit=200", "--query", "limit[appStoreVersions]=50", "--paginate"]

    /// The JSON:API document as the sidebar's apps: the newest version (highest number) per platform, iOS first.
    nonisolated static func apps(from doc: VitrinJSON) -> [ASCApp] {
        let o = doc.objectValue ?? [:]
        var versions: [String: [String: VitrinJSON]] = [:]
        for inc in o["included"]?.arrayValue ?? [] {
            guard let i = inc.objectValue, i["type"]?.stringValue == "appStoreVersions", let id = i["id"]?.stringValue else { continue }
            versions[id] = i["attributes"]?.objectValue ?? [:]
        }
        let order = ["IOS", "MAC_OS", "TV_OS", "VISION_OS"]
        func rank(_ p: String) -> Int { order.firstIndex(of: p) ?? order.count }
        return (o["data"]?.arrayValue ?? []).compactMap { item -> ASCApp? in
            guard let a = item.objectValue, let id = a["id"]?.stringValue else { return nil }
            let attr = a["attributes"]?.objectValue ?? [:]
            let rel = a["relationships"]?.objectValue?["appStoreVersions"]?.objectValue?["data"]?.arrayValue ?? []
            var best: [String: ASCAppVersion] = [:]
            for r in rel {
                guard let vid = r.objectValue?["id"]?.stringValue, let v = versions[vid], let platform = v["platform"]?.stringValue else { continue }
                let candidate = ASCAppVersion(id: vid, platform: platform, version: v["versionString"]?.stringValue ?? "", state: v["appVersionState"]?.stringValue ?? v["appStoreState"]?.stringValue ?? "")
                if let cur = best[platform], compareVersions(candidate.version, cur.version) <= 0 { continue }
                best[platform] = candidate
            }
            let vs = best.values.sorted { rank($0.platform) != rank($1.platform) ? rank($0.platform) < rank($1.platform) : $0.platform < $1.platform }
            return ASCApp(id: id, bundleId: attr["bundleId"]?.stringValue ?? "", name: attr["name"]?.stringValue ?? "", sku: attr["sku"]?.stringValue ?? "",
                          primaryLocale: attr["primaryLocale"]?.stringValue ?? "", platforms: vs.map(\.platform), versions: vs)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// `1.10` > `1.9`, `2.0` > `1.99.1`, `1.0` = `1.0.0`.
    nonisolated static func compareVersions(_ a: String, _ b: String) -> Int {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }, pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let d = (i < pa.count ? pa[i] : 0) - (i < pb.count ? pb[i] : 0)
            if d != 0 { return d < 0 ? -1 : 1 }
        }
        return 0
    }

    func clear() {
        AscCache.shared.removeAll()
        task?.cancel()
        task = nil
        apps = []
        error = nil
        loadedAt = nil
    }

    private static func firstLine(of text: String) -> String? {
        let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        // The CLI prefixes errors with ✗ and warnings with ⚠; the words are what matter.
        guard let line = lines.first(where: { $0.hasPrefix("✗") }) ?? lines.first else { return nil }
        // "ASC API 401 /v1/apps?include=…: detail" → "ASC API 401: detail"; the path is noise in a sidebar line.
        return String(line.drop { $0 == "✗" || $0 == "⚠" || $0 == " " }).replacingOccurrences(of: #"^(ASC API \d+) /\S*:"#, with: "$1:", options: .regularExpression)
    }
}
