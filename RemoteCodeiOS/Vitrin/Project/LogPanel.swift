// Ported from Vitrin for Mac (apps/VitrinMac/VitrinMac/Views/LogPanel.swift).
import SwiftUI

/// The live log: every line the running stage prints, masked by the CLI, with the job's state on top.
struct LogPanel: View {
    var session: ProjectSession
    @Environment(\.dismiss) private var dismiss
    @State private var filter = ""
    @State private var autoScroll = true
    @State private var errorsOnly = false

    private var lines: [LogLine] {
        session.logs.filter { l in
            (!errorsOnly || l.level == "error" || l.level == "warn") && (filter.isEmpty || l.text.localizedCaseInsensitiveContains(filter))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            status.padding(.horizontal, 12).padding(.vertical, 8)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(lines) { l in
                            Text(verbatim: l.text.isEmpty ? " " : l.text)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(color(l.level))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .id(l.id)
                        }
                    }
                    .padding(8)
                }
                .onChange(of: session.logs.count) {
                    if autoScroll, let last = lines.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
        .searchable(text: $filter, placement: .navigationBarDrawer(displayMode: .automatic), prompt: Text(L.t("log.filter")))
        .navigationTitle(L.t("log.toggle"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L.t("common.close")) { dismiss() }.accessibilityIdentifier("log.close")
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Toggle(L.t("log.errorsOnly"), isOn: $errorsOnly)
                    Toggle(L.t("log.autoScroll"), isOn: $autoScroll)
                    Button(L.t("log.copy"), systemImage: "doc.on.doc") { UIPasteboard.general.string = lines.map(\.text).joined(separator: "\n") }
                    Button(L.t("log.clear"), systemImage: "trash", role: .destructive) { session.clearLogs() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("log.panel")
    }

    @ViewBuilder private var status: some View {
        HStack(spacing: 8) {
            if let j = session.job {
                ProgressView().controlSize(.small)
                Text(verbatim: L.job(j)).font(.callout.weight(.medium))
                Spacer()
                Text(verbatim: L.date(j.startedAt)).font(.caption).foregroundStyle(.secondary)
            } else if let f = session.finishedJob {
                Pill(L.t("job.\(f.status)"), Tone.ofJob(f.status))
                Text(verbatim: L.job(f)).font(.callout)
                Spacer()
            } else {
                Text(L.t("log.idle")).font(.callout).foregroundStyle(.secondary)
                Spacer()
            }
        }
        .lineLimit(1)
    }

    private func color(_ level: String) -> Color {
        switch level {
        case "error": return .red
        case "warn": return .orange
        case "ok": return .green
        case "step": return .accentColor
        case "dim": return .secondary
        case "result": return .purple
        default: return .primary
        }
    }
}
