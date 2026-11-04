// Ported from Vitrin for Mac (apps/VitrinMac/VitrinMac/Views/AscBuildSections.swift).
import SwiftUI

/// Builds with their app version, newest first; a row opens to its groups and What to Test notes.
struct BuildList: View {
    var appID: String
    var reload: () -> Void = {}
    @State private var open: String?
    @State private var query = ""

    var body: some View {
        AscLoad(args: ["builds", "list", "--app", appID, "--limit", "50", "--sort", "-uploadedDate", "--include", "preReleaseVersion"]) { doc, _ in
            let all = JSONAPI.items(doc)
            let versions = Self.versions(doc)
            let version = { (b: [String: VitrinJSON]) in b["relationships"]?.objectValue?["preReleaseVersion"]?.objectValue?["data"]?.objectValue?["id"]?.stringValue.flatMap { versions[$0] } }
            let builds = all.filter { b in [version(b) ?? "", JSONAPI.text(b, "version"), ASCWords.state(JSONAPI.text(b, "processingState"))].contains { $0.matches(search: query) } }
            if all.isEmpty {
                AscDataView(doc: .array([]))
            } else {
                VStack(spacing: 0) {
                    if all.count > AscListSearch.threshold { AscListSearch(text: $query).padding(6) }
                    if builds.isEmpty { Text(L.t("search.noResults")).font(.callout).foregroundStyle(.secondary).padding(10) }
                    ForEach(Array(builds.enumerated()), id: \.offset) { i, b in
                        row(b, version: version(b))
                        if i < builds.count - 1 { Divider().opacity(0.4) }
                    }
                }
                .vitrinCard(padding: 4)
            }
        }
    }

    @ViewBuilder private func row(_ b: [String: VitrinJSON], version: String?) -> some View {
        let id = b["id"]?.stringValue ?? ""
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(.easeOut(duration: 0.15)) { open = open == id ? nil : id } } label: {
                HStack(spacing: 10) {
                    if case .image(let u)? = JSONAPI.attr(b, "iconAssetToken").map({ AscText.shown("iconAssetToken", $0) }) { RemoteThumb(url: u, size: 30) }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(version.map { "\($0) (\(JSONAPI.text(b, "version")))" } ?? JSONAPI.text(b, "version")).font(.callout.weight(.medium))
                        Text(AscText.date(JSONAPI.text(b, "uploadedDate"))).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        if JSONAPI.attr(b, "expired")?.boolValue == true { Pill(L.t("asc.builds.expired"), .neutral).lineLimit(1) }
                        Pill(ASCWords.state(JSONAPI.text(b, "processingState")), ASCWords.tone(JSONAPI.text(b, "processingState"))).lineLimit(1)
                    }
                    Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary).rotationEffect(.degrees(open == id ? 90 : 0))
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open == id {
                VStack(alignment: .leading, spacing: 10) {
                    AscFields(fields: (b["attributes"]?.objectValue ?? [:]).filter { ["minOsVersion", "buildAudienceType", "expirationDate", "usesNonExemptEncryption"].contains($0.key) && !AscDataView.isBlank($0.value) }.sorted { $0.key < $1.key }.map { (key: $0.key, value: $0.value) })
                    AscSection(title: L.t("asc.builds.groups"), args: ["testflight", "groups", "list", "--build-id", id, "--app", appID], empty: L.t("asc.builds.noGroups"))
                    AscSection(title: L.t("asc.builds.notes"), args: ["builds", "test-notes", "list", "--build-id", id], empty: L.t("asc.builds.noNotes"))
                }
                .padding(.horizontal, 10).padding(.bottom, 10)
            }
        }
    }

    /// `included` preReleaseVersions: id → version string.
    nonisolated static func versions(_ doc: VitrinJSON) -> [String: String] {
        var out: [String: String] = [:]
        for i in doc.objectValue?["included"]?.arrayValue ?? [] {
            guard let o = i.objectValue, o["type"]?.stringValue == "preReleaseVersions", let id = o["id"]?.stringValue,
                  let v = o["attributes"]?.objectValue?["version"]?.stringValue else { continue }
            out[id] = v
        }
        return out
    }
}

/// The next build number and the total.
struct BuildCounters: View {
    var appID: String
    var version: String?
    var platform: String?
    var body: some View {
        HStack(spacing: 12) {
            AscLoad(args: ["builds", "count", "--app", appID]) { doc, _ in
                Counter(symbol: "shippingbox.fill", title: L.t("asc.builds.total"), value: doc.objectValue?["total"]?.display ?? "—")
            }
            if let version, let platform {
                AscLoad(args: ["builds", "next-build-number", "--app", appID, "--version", version, "--platform", platform]) { doc, _ in
                    Counter(symbol: "plus.forwardslash.minus", title: L.t("asc.builds.next"), value: doc.objectValue?["nextBuildNumber"]?.display ?? "—")
                }
            }
        }
    }
}

struct Counter: View {
    var symbol: String
    var title: String
    var value: String
    var body: some View {
        HStack(spacing: 10) {
            VitrinBadge(symbol: symbol, colors: BadgeColors.deep, size: 30)
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.title3.bold().monospacedDigit())
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .vitrinCard(padding: 12)
    }
}
