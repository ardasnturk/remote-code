// Ported from Vitrin for Mac (apps/VitrinMac/VitrinMac/Core/AppIcons.swift).
import Foundation
import Observation

/// App icons. The API has no icon on the app record, but every processed build carries one (`iconAssetToken`), so the
/// newest build of each app gives its icon. One request covers the newest 200 builds across the team, one per app
/// fills in the rest; the templates are kept on disk, so the sidebar has its icons from the first frame next time.
@MainActor @Observable final class AppIconStore {
    private(set) var templates: [String: String] = [:]
    private var loadedFor: Set<String> = []
    private static let cacheURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Vitrin/app-icons.json")

    init() {
        if let data = try? Data(contentsOf: Self.cacheURL), let t = try? JSONDecoder().decode([String: String].self, from: data) { templates = t }
    }

    /// The icon at `size` points (retina), or nil when the app has no processed build yet.
    func url(for appID: String, size: CGFloat) -> URL? { templates[appID].flatMap { Self.url(template: $0, size: size) } }

    /// mzstatic's template: `…/{w}x{h}bb.{f}`.
    nonisolated static func url(template: String, size: CGFloat) -> URL? {
        let px = String(Int(size * 2))
        return URL(string: template.replacingOccurrences(of: "{w}", with: px).replacingOccurrences(of: "{h}", with: px).replacingOccurrences(of: "{f}", with: "png"))
    }

    /// Once per set of apps; a failure leaves the placeholders.
    func load(apps: [ASCApp]) async {
        let ids = Set(apps.map(\.id))
        guard !ids.isEmpty, ids != loadedFor else { return }
        loadedFor = ids
        if let doc = try? await AscCLI.json(Self.recentBuildsArgs) { merge(Self.icons(from: doc)) }
        for app in apps where templates[app.id] == nil {
            if let doc = try? await AscCLI.json(["builds", "list", "--app", app.id, "--limit", "1", "--sort", "-uploadedDate"]) { merge(Self.icons(from: doc, app: app.id)) }
        }
        save()
    }

    private func merge(_ found: [String: String]) { templates.merge(found) { _, new in new } }

    private func save() {
        guard let data = try? JSONEncoder().encode(templates) else { return }
        try? FileManager.default.createDirectory(at: Self.cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: Self.cacheURL)
    }

    static let recentBuildsArgs = ["api", "GET", "/v1/builds", "--query", "include=app", "--query", "fields[builds]=iconAssetToken,uploadedDate,app",
                                   "--query", "fields[apps]=bundleId", "--query", "sort=-uploadedDate", "--query", "limit=200"]

    /// The first (newest) build with an icon per app. `app` is the app of a list that has no relationship data.
    nonisolated static func icons(from doc: VitrinJSON, app: String? = nil) -> [String: String] {
        var out: [String: String] = [:]
        for b in doc.objectValue?["data"]?.arrayValue ?? [] {
            guard let o = b.objectValue,
                  let template = o["attributes"]?.objectValue?["iconAssetToken"]?.objectValue?["templateUrl"]?.stringValue,
                  let id = app ?? o["relationships"]?.objectValue?["app"]?.objectValue?["data"]?.objectValue?["id"]?.stringValue,
                  out[id] == nil else { continue }
            out[id] = template
        }
        return out
    }
}
