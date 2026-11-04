// Ported from Vitrin for Mac (apps/VitrinMac/VitrinMac/Views/ClaudePanel.swift).
import SwiftUI

/// Claude: the user's Claude Code on the Mac, running the creative stages inside the project, and a prompt field.
struct ClaudePanel: View {
    var session: ProjectSession
    @Environment(\.dismiss) private var dismiss
    @AppStorage(ClaudeModel.settingKey) private var chosenModel = ""
    @State private var prompt = ""
    @State private var expanded: Set<String> = []

    private var available: Bool { session.overview?.claude.available ?? false }

    var body: some View {
        VStack(spacing: 0) {
            if !available {
                VStack(spacing: 8) {
                    Text(L.t("claude.missing")).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    ToolInstallButton(tool: "claude", title: L.t("tools.install").replacingOccurrences(of: "{tool}", with: "Claude Code")) { Task { await session.refresh() } }
                }
                .padding(16)
                Spacer()
            } else if session.claudeRuns.isEmpty {
                Spacer()
                EmptyHint(text: L.t("claude.idle"), symbol: "sparkles")
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(session.claudeRuns) { run in
                                RunView(run: run, expanded: expanded.contains(run.id) || run.id == session.claudeRuns.last?.id) { toggle(run.id) }
                            }
                        }
                        .padding(10)
                    }
                    .onChange(of: session.claudeRuns.last?.events.count) {
                        if let last = session.claudeRuns.last { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            Divider()
            HStack(alignment: .bottom) {
                TextField(L.t("claude.placeholder"), text: $prompt, axis: .vertical).lineLimit(1...5).textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("claude.prompt")
                Button { send() } label: { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                    .buttonStyle(.borderless)
                    .disabled(!available || session.isBusy || prompt.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("claude.send")
            }
            .padding(10)
        }
        .navigationTitle(Text(verbatim: "Claude"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L.t("common.close")) { dismiss() }.accessibilityIdentifier("claude.close")
            }
            ToolbarItem(placement: .principal) { modelMenu }
            ToolbarItem(placement: .primaryAction) {
                if session.claudeRunning {
                    Button(L.t("common.stop")) { Task { await session.cancelClaude() } }
                } else {
                    Button(L.t("claude.newConversation")) { Task { await session.resetClaude() } }.disabled(session.claudeRuns.isEmpty)
                }
            }
        }
    }

    private var modelMenu: some View {
        Menu {
            Picker(L.t("claude.model"), selection: $chosenModel) {
                Text(L.t("settings.claudeModelDefault")).tag("")
                ForEach(ClaudeModel.aliases, id: \.alias) { Text(verbatim: $0.label).tag($0.alias) }
            }
        } label: {
            Label(ClaudeModel.label(chosenModel), systemImage: "cpu").labelStyle(.titleAndIcon).font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("claude.model")
    }

    private func toggle(_ id: String) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }

    private func send() {
        let p = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty else { return }
        prompt = ""
        Task { await session.askClaude(prompt: p) }
    }
}

struct RunView: View {
    var run: ClaudeRun
    var expanded: Bool
    var toggle: () -> Void

    /// The model Claude Code reported in its init line (the alias resolved to a full name).
    private var model: String? { run.events.first(where: { $0.type == "init" })?.model }

    private var title: String {
        guard let l = run.label else { return run.prompt }
        switch l.kind {
        case "brief": return L.t("claude.runBrief").replacingOccurrences(of: "{stage}", with: L.stage(l.stage ?? ""))
        case "answer": return L.t("claude.runAnswer").replacingOccurrences(of: "{answer}", with: l.answer ?? "")
        default: return l.text ?? run.prompt
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: toggle) {
                HStack(spacing: 6) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.caption).foregroundStyle(.secondary)
                    Text(verbatim: title).font(.callout.weight(.medium)).lineLimit(2)
                    Spacer()
                    Pill(L.t("claude.\(run.status)"), run.status == "running" ? .accent : run.status == "done" ? .ok : run.status == "cancelled" ? .neutral : .err)
                }
            }
            .buttonStyle(.plain)
            if let model { Text(verbatim: ClaudeModel.shortName(model)).font(.caption2.monospaced()).foregroundStyle(.tertiary) }
            if expanded {
                ForEach(Array(run.events.enumerated()), id: \.offset) { _, e in EventView(event: e) }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.secondarySystemBackground)))
        .id(run.id)
    }
}

struct EventView: View {
    var event: ClaudeEvent
    var body: some View {
        switch event.type {
        case "text":
            Text(verbatim: event.text ?? "").font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        case "tool":
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "wrench").font(.caption).foregroundStyle(.secondary)
                Text(verbatim: event.name ?? "").font(.caption.weight(.medium))
                Text(verbatim: event.summary ?? "").font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
            }
        case "result":
            HStack(spacing: 6) {
                Image(systemName: event.ok == true ? "checkmark.circle" : "xmark.circle").foregroundStyle(event.ok == true ? .green : .red).font(.caption)
                Text(verbatim: [event.turns.map { "\($0) turns" }, event.costUsd.map { String(format: "$%.2f", $0) }, event.durationMs.map { String(format: "%.0fs", $0 / 1000) }].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
            }
        case "error":
            Text(verbatim: event.text ?? "").font(.caption).foregroundStyle(.red).textSelection(.enabled)
        case "init":
            Text(verbatim: [event.model, event.sessionId.map { String($0.prefix(8)) }].compactMap { $0 }.joined(separator: " · ")).font(.caption2).foregroundStyle(.tertiary)
        default:
            EmptyView()
        }
    }
}

/// The Claude Code models the app offers by alias. Empty means Claude Code's default (the Studio then falls back to
/// ui.claudeModel in the config).
enum ClaudeModel {
    static let settingKey = "vitrin.claudeModel"
    static let aliases: [(alias: String, label: String)] = [("fable", "Fable"), ("opus", "Opus"), ("sonnet", "Sonnet"), ("haiku", "Haiku")]

    static var chosen: String? {
        let m = (UserDefaults.standard.string(forKey: settingKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return m.isEmpty ? nil : m
    }

    /// "claude-opus-5-5" → "opus 5.5"; an alias or an unknown name stays as it is.
    static func shortName(_ model: String) -> String {
        let parts = model.split(separator: "-").map(String.init)
        guard parts.count >= 3, parts[0] == "claude" else { return model }
        let version = parts.dropFirst(2).filter { Int($0) != nil }.joined(separator: ".")
        return version.isEmpty ? parts[1] : "\(parts[1]) \(version)"
    }

    static func label(_ setting: String) -> String {
        if setting.isEmpty { return L.t("settings.claudeModelDefault") }
        return aliases.first(where: { $0.alias == setting })?.label ?? setting
    }
}
