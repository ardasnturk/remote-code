// Ported from Vitrin for Mac (apps/VitrinMac/VitrinMac/Views/FlowView.swift) and reshaped for a phone.
import SwiftUI

/// The run at a glance: the next step first, the stages in three groups with the status the server computed, and
/// everything that waits for the user (Claude's questions, blockers, the approve and upload clicks).
struct FlowView: View {
    var session: ProjectSession
    var overview: Overview
    struct Brief: Identifiable { var name: String; var text: String; var id: String { name } }
    @State private var brief: Brief?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let error = overview.configError { Text(verbatim: error).font(.callout).foregroundStyle(.red) }
                NextStepCard(session: session, overview: overview, showBrief: openBrief)
                stageList
                decisions
                summary
            }
            .padding(14)
        }
        .refreshable { await session.refresh() }
        .sheet(item: $brief) { b in
            BriefSheet(name: b.name, text: b.text, session: session)
        }
    }

    private var stageList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Pipeline.groups, id: \.key) { group in
                Text(L.t("flow.\(group.key)")).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase).padding(.top, 8)
                ForEach(group.stages, id: \.self) { id in
                    if let view = overview.stage(id), let n = overview.flow.firstIndex(where: { $0.id == id }) {
                        StageRow(session: session, overview: overview, view: view, n: n + 1, showBrief: openBrief)
                    }
                }
            }
        }
    }

    private var decisions: some View {
        Card(L.t("flow.pending")) {
            let list = overview.pendingDecisions.filter { d in
                switch d {
                case .blocker(let b): return b.code != overview.next?.blocker
                case .question(let q): return q.id != overview.next?.question
                case .stage: return true
                }
            }
            if list.isEmpty {
                Text(L.t("flow.noDecisions")).foregroundStyle(.secondary)
            } else {
                ForEach(list) { d in DecisionView(decision: d, session: session, overview: overview) }
            }
        }
    }

    private var summary: some View {
        Card(L.t("flow.summary")) {
            if let cfg = overview.config {
                KeyValueRow(key: L.t("summary.locales"), value: cfg.locales.joined(separator: ", "))
                KeyValueRow(key: L.t("summary.primary"), value: cfg.primaryLocale)
                if !cfg.locales.contains(cfg.primaryLocale) {
                    Text(verbatim: L.t("flow.primaryLocaleIs").replacingOccurrences(of: "{locale}", with: cfg.primaryLocale)).font(.caption).foregroundStyle(.red)
                }
                perLocale(L.t("flow.storeText"), cfg) { l in
                    let has = overview.listing.contains(l)
                    return ("\(l) \(has ? "✓" : "✗ \(L.t("common.missing"))")", has)
                }
                let extra = overview.listing.filter { !cfg.locales.contains($0) }.count
                if extra > 0 { Text(verbatim: L.t("flow.notSelectedExtra").replacingOccurrences(of: "{n}", with: "\(extra)")).font(.caption).foregroundStyle(.secondary) }
                KeyValueRow(key: L.t("summary.uploader"), value: cfg.uploader ?? L.t("summary.notChosen"))
                KeyValueRow(key: L.t("summary.capture"), value: cfg.capture)
                KeyValueRow(key: L.t("summary.language"), value: cfg.language ?? "en")
                if overview.stage("design")?.stageStatus != .skipped {
                    perLocale(L.t("summary.screenshots"), cfg) { l in ("\(l): \(overview.screenshots[l]?.count ?? 0)", overview.screenshots[l]?.isEmpty == false) }
                }
                if overview.stage("video")?.stageStatus != .skipped {
                    perLocale(L.t("summary.previews"), cfg) { l in ("\(l): \(overview.previews[l]?.count ?? 0)", overview.previews[l]?.isEmpty == false) }
                }
                validationRow
                approvalRow
                uploadRow
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(L.t("summary.tools")).foregroundStyle(.secondary).font(.caption)
                FlowLayout(spacing: 6) {
                    ToolPill("asc", overview.tools.asc)
                    ToolPill("ffmpeg", overview.tools.ffmpeg)
                    ToolPill("claude", overview.tools.claude)
                }
            }
            Text(verbatim: "Vitrin \(overview.version) · \(overview.root)").font(.caption2.monospaced()).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
        }
    }

    /// One line per store language, what is missing in red.
    private func perLocale(_ key: String, _ cfg: ProjectConfig, _ line: @escaping (String) -> (text: String, ok: Bool)) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: key).font(.caption).foregroundStyle(.secondary)
            FlowLayout(spacing: 8) {
                ForEach(cfg.locales, id: \.self) { l in
                    let entry = line(l)
                    Text(verbatim: entry.text).font(.callout).foregroundStyle(entry.ok ? Color.primary : Color.red)
                }
            }
        }
    }

    private var validationRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L.t("summary.validation")).font(.caption).foregroundStyle(.secondary)
            if let v = overview.validation {
                HStack(spacing: 6) {
                    Pill(v.ok ? L.t("review.validationOk") : L.t("review.validationErrors", v.counts.error), v.ok ? .ok : .err)
                    if v.counts.warning > 0 { Text(verbatim: L.t("flow.warnings").replacingOccurrences(of: "{n}", with: "\(v.counts.warning)")).font(.caption).foregroundStyle(.secondary) }
                }
            } else {
                Text(verbatim: "—").font(.callout)
            }
        }
    }

    private var approvalRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L.t("flow.approval")).font(.caption).foregroundStyle(.secondary)
            if let a = overview.approval, a.valid {
                Pill(L.date(a.approvedAt), .ok)
            } else if let a = overview.approval, a.status == "approved" {
                Text(verbatim: L.t("review.approvalInvalid").replacingOccurrences(of: "{reason}", with: L.reason(StageView(id: "review", status: "blocked", reason: a.problem), overview)))
                    .font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            } else {
                Pill(L.t("review.notApproved"))
            }
        }
    }

    private var uploadRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L.t("stage.upload")).font(.caption).foregroundStyle(.secondary)
            if let up = overview.approval?.upload, up.overallHash == overview.approval?.overallHash {
                Pill(L.date(up.uploadedAt), up.readBack == "ok" ? .ok : .err)
            } else {
                Text(L.t("upload.notUploaded")).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func openBrief(_ name: String) {
        Task {
            do {
                let f = try await session.readFile("metadata/briefs/\(name).md")
                brief = Brief(name: name, text: f.text)
            } catch {
                session.report(error)
            }
        }
    }
}

struct ToolPill: View {
    var name: String
    var version: String?
    init(_ name: String, _ version: String?) {
        self.name = name
        self.version = version
    }
    var body: some View { Pill(version.map { "\(name) \($0)" } ?? name, version == nil ? .neutral : .ok) }
}

/// One stage: its number (or check), title, hint, status and the single action it offers; the rest behind “…”.
struct StageRow: View {
    var session: ProjectSession
    var overview: Overview
    var view: StageView
    var n: Int
    var showBrief: (String) -> Void

    private var running: Bool { session.job?.command == Pipeline.command(for: view.id)?.command && view.id != "upload" }
    private var missingTool: Blocker? { overview.blockers.first { $0.stage == view.id && $0.severity == "error" && $0.params["install"] != nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                StepNumber(n: n, done: view.stageStatus == .done && !running, tone: Tone.of(view.stageStatus), running: running)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Button(L.stage(view.id)) { session.page = Pipeline.page(for: view.id) }
                            .buttonStyle(.plain).font(.body.weight(.medium))
                        if view.isOptional { Text(verbatim: "· \(L.t("flow.optional"))").font(.caption).foregroundStyle(.secondary) }
                    }
                    Text(L.hint(view.id)).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if let c = Pipeline.command(for: view.id) {
                    Menu {
                        if let b = view.brief { Button(L.t("flow.brief")) { showBrief(b) } }
                        if view.brief != nil || view.stageStatus == .needsUser {
                            Button(L.t("common.run")) { Task { await session.run(c.command, args: c.args) } }
                                .disabled(session.isBusy || missingTool != nil)
                        }
                        Button(L.t("flow.rerun")) { Task { await session.run(c.command, args: c.args, force: true) } }
                            .disabled(session.isBusy || missingTool != nil)
                    } label: {
                        Image(systemName: "ellipsis").frame(width: 28, height: 28).contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("flow.more.\(view.id)")
                }
            }
            FlowLayout(spacing: 6) {
                if running { Pill(L.t("common.running"), .accent) } else { Pill(L.status(view.stageStatus), Tone.of(view.stageStatus)) }
                if let at = view.completedAt, view.stageStatus != .notRun { Text(verbatim: L.date(at)).font(.caption).foregroundStyle(.secondary) }
            }
            let reason = L.reason(view, overview)
            if !reason.isEmpty { Text(verbatim: reason).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            if let note = view.note { Text(verbatim: note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            primaryAction
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(running ? Color.accentColor.opacity(0.08) : Color(.secondarySystemBackground).opacity(0.7)))
        .opacity(view.stageStatus == .skipped ? 0.6 : 1)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("flow.stage.\(view.id)")
    }

    @ViewBuilder private var primaryAction: some View {
        if view.stageStatus == .skipped {
            EmptyView()
        } else if view.stageStatus == .needsUser || view.id == "upload" {
            Button(L.t("flow.goToPage")) { session.page = Pipeline.page(for: view.id) }
                .buttonStyle(view.stageStatus == .needsUser ? AnyButtonStyle(.borderedProminent) : AnyButtonStyle(.bordered)).controlSize(.small)
        } else if let b = view.brief {
            ClaudeButton(session: session, overview: overview, stage: b, small: true)
        } else if let c = Pipeline.command(for: view.id) {
            Button(L.t("common.run")) { Task { await session.run(c.command, args: c.args) } }
                .buttonStyle(view.stageStatus != .done && !view.isOptional ? AnyButtonStyle(.borderedProminent) : AnyButtonStyle(.bordered))
                .controlSize(.small)
                .disabled(session.isBusy || missingTool != nil)
                .accessibilityIdentifier("flow.run.\(view.id)")
            if let missingTool { Text(verbatim: L.blocker(missingTool)).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

/// “Let Claude do it”: runs the user's Claude Code on a stage's brief, on the Mac.
struct ClaudeButton: View {
    var session: ProjectSession
    var overview: Overview
    var stage: String
    var small = false
    var body: some View {
        Button { Task { await session.askClaude(stage: stage); session.showClaude = true } } label: { Label(L.t("claude.doIt"), systemImage: "sparkles") }
            .buttonStyle(.borderedProminent)
            .controlSize(small ? .small : .regular)
            .disabled(session.isBusy || !overview.claude.available)
    }
}

/// One sentence and one button: what to do now.
struct NextStepCard: View {
    var session: ProjectSession
    var overview: Overview
    var showBrief: (String) -> Void

    var body: some View {
        Card(L.t("flow.nextStep"), accent: true) {
            if let next = overview.next {
                Text(L.stage(next.stage)).font(.title3.weight(.semibold))
                content(for: next)
            } else {
                Text(L.t("flow.allDone"))
            }
        }
    }

    @ViewBuilder private func content(for next: NextStep) -> some View {
        let view = overview.stage(next.stage)
        let reason = view.map { L.reason($0, overview) } ?? ""
        switch next.action {
        case "answer":
            if let q = overview.questions.first(where: { $0.id == next.question }) { QuestionCard(question: q, session: session, overview: overview) }
        case "fix", "decide":
            if let b = overview.blocker(next.blocker ?? "") {
                if next.action == "fix" { Text(L.t("flow.fixFirst")).foregroundStyle(.secondary) }
                BlockerCard(blocker: b, session: session, overview: overview, primary: true)
            }
        case "claude":
            if let b = view?.brief {
                Text(verbatim: L.t("flow.nextClaude").replacingOccurrences(of: "{stage}", with: L.stage(next.stage)))
                FlowLayout(spacing: 8) {
                    ClaudeButton(session: session, overview: overview, stage: b)
                    Button(L.t("flow.brief")) { showBrief(b) }.buttonStyle(.bordered)
                }
            }
        case "approve", "upload", "finalize":
            Text(verbatim: next.action == "finalize" ? L.t("flow.nextFinalize") : (reason.isEmpty ? L.t(next.action == "upload" ? "flow.decisionUpload" : "flow.nextApprove") : reason))
            Button(L.t(next.action == "approve" ? "flow.openReview" : "flow.openUpload")) { session.page = Pipeline.page(for: next.stage) }.buttonStyle(.borderedProminent)
        default:
            Text(verbatim: reason.isEmpty ? L.t("flow.nextRun").replacingOccurrences(of: "{stage}", with: L.stage(next.stage)) : reason)
            if let c = Pipeline.command(for: next.stage) {
                // A missing tool (ffmpeg) makes the run fail for sure; it unlocks by itself once the tool is installed.
                let missingTool = overview.blockers.first { $0.stage == next.stage && $0.severity == "error" && $0.params["install"] != nil }
                Button(L.t("common.run")) { Task { await session.run(c.command, args: c.args) } }
                    .buttonStyle(.borderedProminent).disabled(session.isBusy || missingTool != nil).accessibilityIdentifier("flow.next")
                if let missingTool { Text(verbatim: L.blocker(missingTool)).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}

/// A pending decision: Claude's question, a blocker with its fixes, or a stage waiting for the user's tap.
struct DecisionView: View {
    var decision: PendingDecision
    var session: ProjectSession
    var overview: Overview
    var body: some View {
        switch decision {
        case .question(let q): QuestionCard(question: q, session: session, overview: overview)
        case .blocker(let b): BlockerCard(blocker: b, session: session, overview: overview)
        case .stage(let s):
            VStack(alignment: .leading, spacing: 8) {
                let r = L.reason(s, overview)
                Text(verbatim: r.isEmpty ? L.t(s.id == "upload" ? "flow.decisionUpload" : "flow.decisionApprove") : r)
                Button(L.t(s.id == "upload" ? "flow.openUpload" : "flow.openReview")) { session.page = Pipeline.page(for: s.id) }.buttonStyle(.borderedProminent).controlSize(.small)
            }
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.08)))
        }
    }
}

/// One blocker: what is wrong, and its one-tap fixes or the install command to copy.
struct BlockerCard: View {
    var blocker: Blocker
    var session: ProjectSession
    var overview: Overview
    var primary = false
    /// What “compare in store preview” does on a page that shows the samples itself.
    var openPreview: (() -> Void)? = nil

    /// The tools the Mac's hub can install; the command names them.
    private func tool(in install: String) -> String? {
        ["ffmpeg", "asc", "claude"].first { install.contains($0) }
    }

    private var tint: Color { blocker.severity == "error" ? .red : blocker.severity == "decision" ? .accentColor : .orange }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: blocker.severity == "error" ? "exclamationmark.octagon.fill" : blocker.severity == "decision" ? "questionmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(tint)
                Text(verbatim: L.blocker(blocker)).textSelection(.enabled)
            }
            if blocker.code == "design-choice" {
                DesignOptions(session: session, overview: overview, openPreview: openPreview)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(Array(blocker.fixes.enumerated()), id: \.element.id) { i, fix in
                        Button(L.fix(fix, blocker)) { Task { await session.run(fix.command, args: fix.args) } }
                            .buttonStyle(primary && i == 0 ? AnyButtonStyle(.borderedProminent) : AnyButtonStyle(.bordered)).controlSize(.small).disabled(session.isBusy)
                    }
                    if let install = blocker.params["install"]?.stringValue {
                        if let tool = tool(in: install) {
                            ToolInstallButton(tool: tool, title: L.t("tools.install").replacingOccurrences(of: "{tool}", with: tool)) { Task { await session.refresh() } }
                        } else {
                            CopyCode(text: install)
                        }
                    }
                    if blocker.code == "keys-missing" {
                        Text(L.t("flow.accountOnHome")).font(.caption).foregroundStyle(.secondary)
                    } else if blocker.fixes.isEmpty, blocker.params["install"] == nil, blocker.stage != "upload" {
                        Button(L.t("flow.goToPage")) { session.page = Pipeline.page(for: blocker.stage) }.controlSize(.small).buttonStyle(.bordered)
                    }
                }
            }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(tint.opacity(0.08)))
    }
}

/// One button per design sample (and the store preview to compare them): a tap hands the choice to Claude.
struct DesignOptions: View {
    var session: ProjectSession
    var overview: Overview
    var openPreview: (() -> Void)? = nil
    var body: some View {
        FlowLayout(spacing: 6) {
            if overview.samples?.storePreview != nil {
                Button(L.t("visuals.openSamples")) { if let openPreview { openPreview() } else { session.page = .design } }.controlSize(.small).buttonStyle(.bordered)
            }
            ForEach(overview.samples?.options ?? []) { o in
                Button(String("\(o.letter) · \(o.name)")) { Task { await session.chooseDesign(o); session.showClaude = true } }
                    .buttonStyle(.borderedProminent).controlSize(.small).disabled(session.isBusy || !overview.claude.available)
            }
        }
    }
}

/// A question Claude left: its options as buttons, or an answer in the user's own words.
struct QuestionCard: View {
    var question: StudioQuestion
    var session: ProjectSession
    var overview: Overview
    @State private var text = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L.t("claude.asks"), systemImage: "sparkles").font(.caption).foregroundStyle(.secondary)
            Text(verbatim: question.question).font(.body.weight(.medium)).textSelection(.enabled)
            if !question.options.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(question.options, id: \.value) { o in
                        Button(o.label) { Task { await session.answer(question, o.value); session.showClaude = true } }
                            .buttonStyle(.borderedProminent).controlSize(.small).disabled(disabled)
                    }
                }
            }
            HStack {
                TextField(question.options.isEmpty ? L.t("claude.answer") : L.t("claude.answerOwnWords"), text: $text, axis: .vertical)
                    .lineLimit(1...4).textFieldStyle(.roundedBorder).disabled(disabled)
                Button(L.t("claude.answer")) { send() }.controlSize(.small).buttonStyle(.bordered).disabled(disabled || text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.08)))
    }
    private var disabled: Bool { session.isBusy || !overview.claude.available }
    private func send() {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        Task { await session.answer(question, t); text = ""; session.showClaude = true }
    }
}

struct BriefSheet: View {
    var name: String
    var text: String
    var session: ProjectSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L.t("flow.briefIntro")).font(.callout).foregroundStyle(.secondary)
                    if let o = session.overview {
                        // Claude's panel is a sheet of the project page: this one goes first, or it can't come up.
                        Button {
                            Task {
                                await session.askClaude(stage: name)
                                dismiss()
                                try? await Task.sleep(for: .milliseconds(450))
                                session.showClaude = true
                            }
                        } label: { Label(L.t("claude.doIt"), systemImage: "sparkles") }
                            .buttonStyle(.borderedProminent)
                            .disabled(session.isBusy || !o.claude.available)
                            .accessibilityIdentifier("brief.claude")
                    }
                    Text(verbatim: text).font(.callout.monospaced()).textSelection(.enabled)
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.tertiarySystemFill)))
                    Text(verbatim: "metadata/briefs/\(name).md").font(.caption.monospaced()).foregroundStyle(.tertiary)
                }
                .padding(14)
            }
            .navigationTitle(Text(verbatim: L.t("flow.briefTitle").replacingOccurrences(of: "{stage}", with: L.stage(name))))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.t("common.close")) { dismiss() }.accessibilityIdentifier("brief.close")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("brief.sheet")
    }
}
