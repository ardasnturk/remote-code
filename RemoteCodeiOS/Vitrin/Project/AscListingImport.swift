// Ported from Vitrin for Mac (apps/VitrinMac/VitrinMac/Core/AscListingImport.swift).
import Foundation

/// The store text that is live (or being prepared) in App Store Connect, as Vitrin's `metadata/listing/<locale>.json`
/// files: the version's localizations (description, keywords, promotional text, What's New, URLs) merged with the
/// app info localizations (name, subtitle, privacy URL), read through asc. The version is the one being edited
/// (PREPARE_FOR_SUBMISSION or a rejected one) when there is one, else the newest.
@MainActor enum AscListingImport {
    struct Result {
        var versionString: String
        /// locale → the listing file's JSON object.
        var listings: [String: [String: VitrinJSON]]
    }

    static func fetch(appID: String) async throws -> Result {
        let versions = JSONAPI.items(try await AscCLI.json(["versions", "list", "--app", appID, "--limit", "20"]))
        let editable: Set<String> = ["PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY"]
        guard let version = versions.first(where: { editable.contains(JSONAPI.text($0, "appVersionState")) }) ?? versions.first,
              let versionID = version["id"]?.stringValue else {
            throw AscCLI.Failure(message: L.t("apps.noVersions"))
        }
        let versionLocs = JSONAPI.items(try await AscCLI.json(["localizations", "list", "--version", versionID, "--paginate"]))
        let infoLocs = JSONAPI.items(try await AscCLI.json(["localizations", "list", "--app", appID, "--type", "app-info", "--paginate"]))
        var out: [String: [String: VitrinJSON]] = [:]
        func text(_ item: [String: VitrinJSON]?, _ key: String) -> String { item.map { JSONAPI.text($0, key) } ?? "" }
        let locales = Set(versionLocs.map { JSONAPI.text($0, "locale") } + infoLocs.map { JSONAPI.text($0, "locale") }).filter { !$0.isEmpty }
        for locale in locales {
            let v = versionLocs.first { JSONAPI.text($0, "locale") == locale }
            let i = infoLocs.first { JSONAPI.text($0, "locale") == locale }
            var o: [String: VitrinJSON] = [
                "locale": .string(locale),
                "name": .string(text(i, "name")),
                "subtitle": .string(text(i, "subtitle")),
                "promotionalText": .string(text(v, "promotionalText")),
                "description": .string(text(v, "description")),
                "keywords": .string(text(v, "keywords")),
                "whatsNew": .string(text(v, "whatsNew")),
                "claims": .array([]),
                "notes": .string("Imported from App Store Connect (version \(JSONAPI.text(version, "versionString"))).")
            ]
            for (key, src, item) in [("supportUrl", "supportUrl", v), ("marketingUrl", "marketingUrl", v), ("privacyUrl", "privacyPolicyUrl", i)] {
                let t = text(item, src)
                if !t.isEmpty { o[key] = .string(t) }
            }
            out[locale] = o
        }
        return Result(versionString: JSONAPI.text(version, "versionString"), listings: out)
    }

    /// Pretty JSON for a listing file, keys in a stable order.
    static func fileText(_ o: [String: VitrinJSON]) -> String {
        guard let d = try? JSONEncoder.pretty.encode(VitrinJSON.object(o)), let s = String(data: d, encoding: .utf8) else { return "{}" }
        return s + "\n"
    }
}

extension JSONEncoder {
    static let pretty: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return e
    }()
}
