// Ported from Vitrin for Mac (apps/VitrinMac/VitrinMac/Core/Localization.swift).
import Foundation

/// `L.t("key")`: the panel's words in the app's language (the table `Vitrin`, `Vitrin.xcstrings`). The phone has no
/// language setting of its own, so the system's choice from the app's languages stands.
enum L {
    static func t(_ key: String) -> String {
        NSLocalizedString(key, tableName: "Vitrin", comment: "")
    }

    static func t(_ key: String, _ args: any CVarArg...) -> String {
        String(format: t(key), locale: locale, arguments: args)
    }

    /// The language showing, as the catalogs name it.
    static var language: String { Bundle.main.preferredLocalizations.first ?? "en" }

    static var locale: Locale { Locale(identifier: language) }

    /// Stage and status names the Studio and the app share.
    static func stage(_ id: String) -> String { t("stage.\(id)") }
    static func hint(_ id: String) -> String { t("hint.\(id)") }
    static func status(_ s: StageStatus) -> String { t("status.\(s.rawValue)") }

    static func date(_ iso: String?) -> String {
        guard let d = Date.fromISO(iso) else { return "" }
        return d.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: locale))
    }

    /// A blocker in words, with its parameters filled in.
    static func blocker(_ b: Blocker) -> String {
        var s = t("blocker.\(b.code)")
        for (k, v) in b.params { s = s.replacingOccurrences(of: "{\(k)}", with: v.display) }
        return s
    }

    static func fix(_ fix: BlockerFix, _ b: Blocker) -> String {
        switch fix.id {
        case "add-locales": return t("fix.addLocales", (b.params["locales"]?.arrayValue?.count ?? 0))
        case "drop-locales": return t("fix.dropLocales")
        case "set-primary": return t("fix.setPrimary").replacingOccurrences(of: "{locale}", with: fix.args["primaryLocale"]?.display ?? "")
        case "add-primary": return t("fix.addPrimary").replacingOccurrences(of: "{locale}", with: b.param("primary"))
        default: return fix.id
        }
    }

    /// Why a stage has its status, in words; empty when the status says it all.
    static func reason(_ view: StageView, _ o: Overview) -> String {
        guard let r = view.reason else { return "" }
        if view.stageStatus == .outdated { return t("reason.outdatedBy").replacingOccurrences(of: "{stage}", with: stage(r)) }
        switch r {
        case "validation-errors": return t("reason.validationErrors", o.validation?.counts.error ?? 0)
        case "content-changed": return t("reason.contentChanged")
        case "rejected": return t("reason.rejected")
        case "readback-differences": return t("reason.readback")
        case "question": return t("reason.question")
        default: return o.blocker(r).map(blocker) ?? ""
        }
    }

    /// A job in the user's words.
    static func job(_ j: JobSummary) -> String {
        if j.command == "upload" { return t(j.isDryRun ? "upload.dryRun" : "stage.upload") }
        if j.command == "design", j.args["samples"]?.boolValue == true { return t("job.renderSamples") }
        switch j.command {
        case "select": return t("job.select")
        case "doctor": return t("job.doctor")
        case "finalize": return t("upload.finalize")
        case "submit": return t("upload.submit")
        case "init": return t("job.init")
        default: return Pipeline.order.contains(j.command) ? stage(j.command) : j.command
        }
    }
}
