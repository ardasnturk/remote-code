// Ported from Vitrin for Mac (apps/VitrinMac/VitrinMac/Views/AscStatusSections.swift).
import SwiftUI

/// A titled section that loads by itself and shows whatever comes back in words.
struct AscSection: View {
    var title: String
    var args: [String]
    var empty: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(title, info: "info." + args.prefix(2).joined(separator: "."))
            AscLoad(args: args) { doc, _ in AscDataView(doc: doc, empty: empty) }
        }
    }
}

/// `asc review doctor`: what stands between the version and App Review, without opening anything.
struct ReviewReadiness: View {
    var appID: String
    var body: some View {
        AscLoad(args: ["review", "doctor", "--app", appID]) { doc, _ in
            let o = doc.objectValue ?? [:]
            let summary = o["summary"]?.objectValue ?? [:]
            let blocking = (o["blockingChecks"]?.arrayValue ?? []).compactMap(\.objectValue)
            let warnings = (o["warningChecks"]?.arrayValue ?? []).compactMap(\.objectValue)
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(L.t("asc.ready.title"), info: "info.asc.ready.title")
                FlowLayout(spacing: 6) {
                    if let n = summary["errors"]?.numberValue, n > 0 { Pill(L.t("asc.ready.errors").replacingOccurrences(of: "{n}", with: "\(Int(n))"), .err) }
                    if let n = summary["warnings"]?.numberValue, n > 0 { Pill(L.t("asc.ready.warnings").replacingOccurrences(of: "{n}", with: "\(Int(n))"), .warn) }
                    if blocking.isEmpty && warnings.isEmpty { Pill(L.t("asc.ready.ok"), .ok) }
                }
                ForEach(Array(blocking.enumerated()), id: \.offset) { _, c in CheckRow(check: c, symbol: "xmark.octagon.fill", color: .red) }
                if !warnings.isEmpty {
                    DisclosureGroup(L.t("asc.ready.showWarnings").replacingOccurrences(of: "{n}", with: "\(warnings.count)")) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(warnings.enumerated()), id: \.offset) { _, c in CheckRow(check: c, symbol: "exclamationmark.triangle.fill", color: .orange) }
                        }
                        .padding(.top, 6)
                    }
                    .font(.callout)
                }
            }
            .vitrinCard(padding: 14)
        }
    }

    private struct CheckRow: View {
        var check: [String: VitrinJSON]
        var symbol: String
        var color: Color
        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: symbol).foregroundStyle(color).font(.caption)
                VStack(alignment: .leading, spacing: 1) {
                    Text(check["message"]?.stringValue ?? "").font(.callout).fixedSize(horizontal: false, vertical: true)
                    if let r = check["remediation"]?.stringValue { Text(r).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                }
            }
        }
    }
}

/// What App Review sees: the contact, the demo account and the notes, with a button to change them.
struct ReviewContactCard: View {
    var versionID: String
    var body: some View {
        AscLoad(args: ["review", "details-for-version", "--version-id", versionID], errorText: L.t("asc.reviewInfo.none")) { doc, reload in
            let item = JSONAPI.items(doc).first ?? [:]
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SectionTitle(L.t("asc.reviewInfo.title"), info: "info.asc.reviewInfo.title")
                    Spacer()
                    if let id = item["id"]?.stringValue { AscActionButton(action: AscActions.reviewDetails(id: id, item: item), done: reload).controlSize(.small).labelStyle(.iconOnly) }
                }
                let name = "\(JSONAPI.text(item, "contactFirstName")) \(JSONAPI.text(item, "contactLastName"))".trimmingCharacters(in: .whitespaces)
                AscFields(fields: ([("reviewContact", VitrinJSON.string(name)), ("contactEmail", JSONAPI.attr(item, "contactEmail") ?? .null), ("contactPhone", JSONAPI.attr(item, "contactPhone") ?? .null),
                                    ("demoAccountRequired", JSONAPI.attr(item, "demoAccountRequired") ?? .null), ("notes", JSONAPI.attr(item, "notes") ?? .null)] as [(String, VitrinJSON)])
                    .filter { !AscDataView.isBlank($0.1) }.map { (key: $0.0, value: $0.1) })
            }
            .vitrinCard(padding: 14)
        }
    }
}

/// `asc review history`: every submission of the app, newest first, with what became of it.
struct SubmissionHistory: View {
    var appID: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(L.t("asc.history.submissions"), info: "info.asc.history.submissions")
            AscLoad(args: ["review", "history", "--app", appID]) { doc, _ in
                let items = (doc.arrayValue ?? []).compactMap(\.objectValue)
                if items.isEmpty {
                    AscDataView(doc: .array([]))
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(items.prefix(12).enumerated()), id: \.offset) { i, s in
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(verbatim: "\(ASCWords.platform(s["platform"]?.stringValue ?? "")) \(s["versionString"]?.stringValue ?? "")").font(.callout.weight(.medium))
                                    Text(AscText.date(s["submittedDate"]?.stringValue ?? "")).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                let outcome = (s["outcome"]?.stringValue ?? "").uppercased()
                                Pill(AscText.value(outcome.isEmpty ? (s["state"]?.stringValue ?? "") : outcome), outcome == "REJECTED" ? .err : outcome == "APPROVED" ? .ok : ASCWords.tone(s["state"]?.stringValue ?? ""))
                            }
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            if i < min(items.count, 12) - 1 { Divider().opacity(0.4) }
                        }
                    }
                    .vitrinCard(padding: 4)
                }
            }
        }
    }
}

/// All versions, newest first.
struct VersionHistory: View {
    var appID: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(L.t("asc.history.versions"), info: "info.asc.history.versions")
            AscLoad(args: ["versions", "list", "--app", appID, "--limit", "20"]) { doc, _ in
                ResourceTable(items: JSONAPI.items(doc), columns: [
                    (L.t("asc.field.version"), "versionString", .text), (L.t("asc.field.platform"), "platform", .mono),
                    (L.t("asc.field.state"), "appVersionState", .state), (L.t("asc.field.releaseType"), "releaseType", .text), (L.t("asc.field.createdDate"), "createdDate", .date),
                ], empty: L.t("asc.empty"))
            }
        }
    }
}
