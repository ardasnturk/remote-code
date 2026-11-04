// Ported from Vitrin for Mac (apps/VitrinMac/VitrinMac/Core/AscCatalog.swift).
import Foundation

/// Every asc command the app offers, from `asc-commands.json` (written by `scripts/asc-catalog.py`): what it
/// does in each language, whether it only reads, and what a read needs before it can run. The panels are built from
/// this, so a page opens at once and needs no `asc --help`.
struct AscCommand: Decodable, Hashable, Identifiable, Sendable {
    /// `testflight groups list`
    var path: String
    /// The title per language.
    var titles: [String: String]
    /// A read (shown and run in place), not a change.
    var read: Bool
    /// A group of commands, not a command.
    var group: Bool
    /// Context flags it takes when the page knows them: `["app", "paginate"]` is filtered down to what a page fills.
    var takes: [String]
    /// What a read needs that only a choice can give: `["group-id"]`.
    var needs: [String]
    var id: String { path }
    var words: [String] { path.split(separator: " ").map(String.init) }
    var parent: String { words.dropLast().joined(separator: " ") }

    var title: String { titles[L.language] ?? titles["en"] ?? path }
}

@MainActor enum AscCatalog {
    private static let all: [String: AscCommand] = {
        guard let url = Bundle.main.url(forResource: "asc-commands", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([AscCommand].self, from: data) else { return [:] }
        return Dictionary(list.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
    }()
    private static let byParent: [String: [AscCommand]] = Dictionary(grouping: all.values, by: \.parent)

    static func command(_ path: String) -> AscCommand? { all[path] }

    /// "12 views · 7 actions" for an area, counting everything under it.
    static func counts(_ path: String) -> String {
        let under = all.values.filter { !$0.group && ($0.path == path || $0.path.hasPrefix(path + " ")) }
        let reads = under.filter(\.read).count
        return [reads > 0 ? L.t("asc.count.views").replacingOccurrences(of: "{n}", with: "\(reads)") : nil,
                under.count > reads ? L.t("asc.count.actions").replacingOccurrences(of: "{n}", with: "\(under.count - reads)") : nil]
            .compactMap { $0 }.joined(separator: " · ")
    }

    /// The children of a group, reads first, in the catalog's words.
    static func children(_ path: String) -> [AscCommand] {
        (byParent[path] ?? []).sorted { a, b in
            if a.group != b.group { return !a.group }
            if a.read != b.read { return a.read }
            return order(a) != order(b) ? order(a) < order(b) : a.path < b.path
        }
    }

    /// The list a flag's value comes from: `--build-id` from the app's builds, `--id` from the sibling `list`.
    static func source(flag: String, path: String) -> AscCommand? {
        let words = path.split(separator: " ").map(String.init)
        let top = words.first ?? ""
        if flag == "id" {
            var w = Array(words.dropLast())
            while !w.isEmpty {
                if let c = all[(w + ["list"]).joined(separator: " ")], c.needs.isEmpty { return c }
                w.removeLast()
            }
            return nil
        }
        let noun = flag.hasSuffix("-id") ? String(flag.dropLast(3)) : flag
        if let p = known["\(top):\(noun)"] ?? known[noun], let c = all[p] { return c }
        for candidate in ["\(top) \(noun)s list", "\(top) \(noun) list", "\(noun)s list"] {
            if let c = all[candidate] { return c }
        }
        return nil
    }

    private static let known = [
        "version": "versions list", "build": "builds list", "group": "testflight groups list", "tester": "testflight testers list",
        "localization": "localizations list", "version-localization": "localizations list", "subscription": "subscriptions list",
        "iap": "iap list", "custom-page": "product-pages custom-pages list", "submission": "review submissions-list",
        "subscriptions:group": "subscriptions groups list", "event": "app-events list", "user": "users list", "device": "devices list",
        "certificate": "certificates list", "profile": "profiles list", "bundle": "bundle-ids list",
    ]

    /// `--platform  Platform: IOS, MAC_OS, TV_OS`: the values a flag's help lists.
    static func choices(_ summary: String) -> [String]? {
        guard let m = summary.firstMatch(of: /[:(]\s*([A-Z][A-Z0-9_]+(?:(?:,| \|)\s*[A-Z][A-Z0-9_]+)+)/) else { return nil }
        return m.1.split(whereSeparator: { ", |".contains($0) }).map(String.init)
    }

    static func takesPath(_ flag: String) -> Bool {
        ["file", "path", "ipa", "pkg", "dir", "image", "video", "csv", "p8"].contains { flag.contains($0) }
    }

    private static let destructiveVerbs = ["delete", "remove", "revoke", "expire", "cancel", "release", "submit", "reject", "disable", "purge", "stop", "publish"]
    static func isDestructive(_ c: AscCommand) -> Bool {
        guard let verb = c.words.last else { return false }
        return destructiveVerbs.contains { verb.contains($0) }
    }

    static func symbol(_ c: AscCommand) -> String {
        let verb = c.words.last ?? ""
        if verb.contains("delete") || verb.contains("remove") || verb.contains("revoke") { return "trash" }
        if verb.contains("create") || verb.contains("add") || verb.contains("invite") || verb.contains("register") { return "plus" }
        if verb.contains("update") || verb.contains("edit") || verb.contains("set") || verb.contains("rename") { return "pencil" }
        if verb.contains("upload") || verb.contains("push") || verb.contains("import") { return "arrow.up.circle" }
        if verb.contains("download") || verb.contains("pull") || verb.contains("export") { return "arrow.down.circle" }
        if verb.contains("submit") || verb.contains("publish") || verb.contains("release") { return "paperplane" }
        return "bolt"
    }

    private static func order(_ c: AscCommand) -> Int {
        switch c.words.last {
        case "list": return 0
        case "status", "view", "info", "current": return 1
        default: return 2
        }
    }
}
