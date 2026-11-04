// Ported from Vitrin for Mac (apps/VitrinMac/VitrinMac/Core/AscText.swift).
import SwiftUI

/// App Store Connect's values in words: language and country names, `HEALTH_AND_FITNESS`, field names, dates, sizes.
/// The app never shows an API code when it can show what the code means.
@MainActor enum AscText {
    /// The language the app is showing, for Foundation's names (the system language can differ).
    static var locale: Locale { L.locale }

    /// `de-DE`, `de_DE` → Almanca (Almanya).
    static func language(_ code: String) -> String {
        guard !code.isEmpty else { return "" }
        return locale.localizedString(forIdentifier: code.replacingOccurrences(of: "_", with: "-")) ?? code
    }

    /// `TUR`, `tr` → Türkiye.
    static func territory(_ code: String) -> String {
        guard !code.isEmpty else { return "" }
        return locale.localizedString(forRegionCode: code.uppercased()) ?? code
    }

    /// A value of one of the API's enums: its translation, else its words ("Pending Apple Release").
    static func value(_ s: String) -> String {
        if let m = s.wholeMatch(of: /PT(\d+)H/), let hours = Int(m.1) {
            return (hours % 24 == 0 ? L.t("asc.duration.days").replacingOccurrences(of: "{n}", with: "\(hours / 24)") : L.t("asc.duration.hours").replacingOccurrences(of: "{n}", with: "\(hours)"))
        }
        for prefix in ["enum.", "ascState."] {
            let key = prefix + s
            let t = L.t(key)
            if t != key { return t }
        }
        if let p = platforms[s] { return p }
        if let d = device(s) { return d }
        return s.lowercased().split(separator: "_").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    /// Screenshot and preview display types: `APP_IPHONE_55`, `IPAD_PRO_129` → iPhone 5.5", iPad Pro 12.9".
    /// Device names read the same in every language, and new sizes need no entry.
    static func device(_ s: String) -> String? {
        var t = s
        for prefix in ["IMESSAGE_APP_", "APP_"] where t.hasPrefix(prefix) { t = String(t.dropFirst(prefix.count)) }
        if let m = t.wholeMatch(of: /IPHONE_(\d)(\d)/) { return "iPhone \(m.1).\(m.2)\"" }
        if let m = t.wholeMatch(of: /IPAD_(\d)(\d)/) { return "iPad \(m.1).\(m.2)\"" }
        if let m = t.wholeMatch(of: /IPAD_(\d{2})(\d)/) { return "iPad \(m.1).\(m.2)\"" }
        if let m = t.wholeMatch(of: /IPAD_PRO(?:_\dGEN)?_(\d{2})(\d)/) { return "iPad Pro \(m.1).\(m.2)\"" }
        return nil
    }

    private static let platforms = ["IOS": "iOS", "MAC_OS": "macOS", "TV_OS": "tvOS", "VISION_OS": "visionOS", "WATCH_OS": "watchOS", "UNIVERSAL": "Universal"]

    /// A field name: its translation, else its words (`earliestReleaseDate` → Earliest release date).
    static func field(_ key: String) -> String {
        let k = "asc.field.\(key)"
        let t = L.t(k)
        if t != k { return t }
        var out = ""
        for c in key {
            if c.isUppercase { out += " " + c.lowercased() } else if c == "-" || c == "_" { out += " " } else { out.append(c) }
        }
        out = out.trimmingCharacters(in: .whitespaces)
        return out.prefix(1).uppercased() + out.dropFirst()
    }

    /// A form field for a command's flag: its translation, else its words without the `-id`.
    static func flag(_ name: String) -> String {
        let k = "asc.flag.\(name)"
        let t = L.t(k)
        if t != k { return t }
        var n = name
        if n.hasSuffix("-id") { n = String(n.dropLast(3)) }
        return field(n)
    }

    static func isID(_ flag: String) -> Bool { flag == "id" || flag.hasSuffix("-id") }

    static func date(_ s: String) -> String {
        guard let d = parseDate(s) else { return s }
        let dateOnly = !s.contains("T")
        return d.formatted(Date.FormatStyle(date: .abbreviated, time: dateOnly ? .omitted : .shortened, locale: locale))
    }

    static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        for options: ISO8601DateFormatter.Options in [[.withInternetDateTime, .withFractionalSeconds], [.withInternetDateTime], [.withFullDate]] {
            f.formatOptions = options
            if let d = f.date(from: s) { return d }
        }
        return nil
    }

    static func bytes(_ n: Double) -> String { ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file) }

    /// `HEALTH_AND_FITNESS`-shaped: capitals, digits and underscores, at least two letters.
    static func isEnum(_ s: String) -> Bool {
        s.count >= 3 && s.count <= 64 && s.first?.isLetter == true && s.allSatisfy { $0.isUppercase || $0.isNumber || $0 == "_" }
    }

    static func isDate(_ s: String) -> Bool {
        s.count >= 10 && s.range(of: #"^\d{4}-\d{2}-\d{2}(T|$)"#, options: .regularExpression) != nil
    }

    /// One value, ready to show.
    enum Shown: Equatable {
        case none
        case text(String)
        case state(String, Tone)
        case flag(Bool)
        case image(URL)
        case link(URL, String)
    }

    /// Names and identifiers: shown as they are, whatever they look like.
    private static let verbatim: Set<String> = ["name", "title", "referenceName", "version", "versionString", "bundleId", "identifier", "sku", "udid", "productId",
                                                "vendorIdentifier", "currency", "reportCurrency", "regionCode", "teamId", "seedId", "keyId", "email", "username"]
    private static let languageKeys: Set<String> = ["locale", "primaryLocale", "language", "defaultLocale"]
    private static let countryKeys: Set<String> = ["territory", "country", "countryCode", "storefront", "baseTerritory", "territoryCode"]
    private static let sizeKeys: Set<String> = ["fileSize", "downloadBytes", "installBytes", "size", "sizeBytes", "bytes"]

    static func isStateKey(_ key: String) -> Bool {
        let k = key.lowercased()
        return k == "state" || k == "status" || k.hasSuffix("state") || k.hasSuffix("status")
    }

    /// What `key: value` means, by the key's name and the value's shape; works on any asc output.
    static func shown(_ key: String, _ value: VitrinJSON) -> Shown {
        switch value {
        case .null: return .none
        case .bool(let b): return .flag(b)
        case .number(let n):
            if sizeKeys.contains(key) { return .text(bytes(n)) }
            return .text(value.display)
        case .string(let s):
            if s.isEmpty { return .none }
            if verbatim.contains(key) { return .text(s) }
            if languageKeys.contains(key) { return .text(language(s)) }
            if countryKeys.contains(key) { return .text(territory(s)) }
            if isDate(s) { return .text(date(s)) }
            if isEnum(s) {
                if isStateKey(key) { return .state(Self.value(s), ASCWords.tone(s)) }
                return .text(Self.value(s))
            }
            if let u = URL(string: s), u.scheme == "https" || u.scheme == "http" {
                return .link(u, u.host() ?? s)
            }
            return .text(s)
        case .array(let a):
            let parts = a.compactMap { x -> String? in
                switch shown(key, x) {
                case .text(let t): return t
                case .state(let t, _): return t
                default: return nil
                }
            }
            return parts.isEmpty ? .none : .text(parts.joined(separator: ", "))
        case .object(let o):
            if let t = o["templateUrl"]?.stringValue, let u = AppIconStore.url(template: t, size: 160) { return .image(u) }
            return .none
        }
    }

    /// `shown` as plain text, for a row's subtitle or a picker.
    static func plain(_ key: String, _ value: VitrinJSON) -> String {
        switch shown(key, value) {
        case .text(let t): return t
        case .state(let t, _): return t
        case .link(_, let t): return t
        case .flag(let b): return L.t(b ? "common.yes" : "common.no")
        default: return ""
        }
    }
}
