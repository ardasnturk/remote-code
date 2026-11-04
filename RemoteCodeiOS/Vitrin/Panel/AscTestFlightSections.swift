// Ported from Vitrin for Mac (apps/VitrinMac/VitrinMac/Views/AscTestFlightSections.swift).
import SwiftUI

/// Beta groups; a group opens to its testers and builds.
struct BetaGroupList: View {
    var doc: VitrinJSON
    @State private var open: String?
    var body: some View {
        let groups = JSONAPI.items(doc)
        if groups.isEmpty {
            AscDataView(doc: .array([]))
        } else {
            VStack(spacing: 0) {
                ForEach(Array(groups.enumerated()), id: \.offset) { i, g in
                    let id = g["id"]?.stringValue ?? ""
                    let isInternal = JSONAPI.attr(g, "isInternalGroup")?.boolValue == true
                    VStack(alignment: .leading, spacing: 0) {
                        Button { withAnimation(.easeOut(duration: 0.15)) { open = open == id ? nil : id } } label: {
                            HStack(spacing: 10) {
                                VitrinBadge(symbol: isInternal ? "person.2.fill" : "globe", colors: isInternal ? BadgeColors.deep : BadgeColors.cool, size: 26)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(JSONAPI.text(g, "name")).font(.callout.weight(.medium))
                                    Text(L.t(isInternal ? "asc.tf.internal" : "asc.tf.external")).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary).rotationEffect(.degrees(open == id ? 90 : 0))
                            }
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if open == id {
                            VStack(alignment: .leading, spacing: 10) {
                                if let link = JSONAPI.attr(g, "publicLink")?.stringValue, let u = URL(string: link), JSONAPI.attr(g, "publicLinkEnabled")?.boolValue == true {
                                    Link(L.t("asc.tf.publicLink"), destination: u).font(.caption)
                                }
                                AscSection(title: L.t("asc.tf.testers"), args: ["testflight", "groups", "testers", "list", "--group-id", id], empty: L.t("asc.tf.noTesters"))
                                AscSection(title: L.t("asc.tf.builds"), args: ["testflight", "groups", "builds", "list", "--group-id", id], empty: L.t("asc.tf.noBuilds"))
                            }
                            .padding(.horizontal, 10).padding(.bottom, 10)
                        }
                    }
                    if i < groups.count - 1 { Divider().opacity(0.4) }
                }
            }
            .vitrinCard(padding: 4)
        }
    }
}
