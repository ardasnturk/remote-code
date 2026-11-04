// Ported from Vitrin for Mac (apps/VitrinMac/VitrinMac/Views/UploadView.swift) and reshaped for a phone.
import SwiftUI

/// The upload as a checklist: uploader → keys (names only) → approved content → dry-run plan → the upload after the
/// user's explicit confirmation; read-back, finalize and submit follow.
struct UploadView: View {
    @Environment(VitrinPanelModel.self) private var model
    var session: ProjectSession
    var overview: Overview
    @State private var flags = Flags()
    @State private var planJob: Job?
    @State private var confirmUpload = false
    @State private var typed = ""
    @State private var deleteResearch: Bool?
    @State private var submitBundle = ""
    @State private var doctor: Job?

    struct Flags {
        var creatives = false, cpp = false, events = false, experiment = false, skipScreenshots = false
        var args: [String: VitrinJSON] {
            var a: [String: VitrinJSON] = ["creatives": .bool(creatives), "cpp": .bool(cpp), "events": .bool(events), "skipScreenshots": .bool(skipScreenshots)]
            if experiment { a["experiment"] = .bool(true) }
            return a
        }
    }

    /// asc is the one uploader; it only has to be installed.
    private var toolVersion: String? { overview.tools.asc }
    private var uploaderOk: Bool { toolVersion != nil }
    /// The App Store keys count as present when the app is connected (Vitrin's key or asc's own login).
    private var ascKeyNames: Set<String> { ["ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_PATH", "ASC_KEY_CONTENT_BASE64"] }
    private var missingKeys: [String] { overview.missingKeys.filter { !(model.connection.isConnected && ascKeyNames.contains($0)) } }
    private var keysOk: Bool { missingKeys.isEmpty }
    private var approved: Bool { overview.approval?.valid ?? false }
    private var planOk: Bool { planJob?.status == "ok" }
    private var uploaded: ApprovalSummary.Upload? { overview.approval?.upload }
    private var waiting: [String] { [uploaderOk ? nil : L.t("upload.stepUploader"), keysOk ? nil : L.t("upload.stepKeys"), approved ? nil : L.t("upload.stepApproval")].compactMap { $0 } }
    private var appName: String { overview.app?.name ?? "" }
    /// The key names the upload needs: present ones from the env key list, missing ones from the overview.
    private var keyNames: [(name: String, present: Bool)] {
        var names = ["ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_PATH"]
        for m in missingKeys where !names.contains(m) { names.append(m) }
        return names.map { ($0, !missingKeys.contains($0)) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(L.t("upload.intro")).font(.callout).foregroundStyle(.secondary)
                Step(n: 1, ok: uploaderOk, title: L.t("upload.stepUploader")) {
                    HStack(spacing: 8) {
                        VitrinBadge(symbol: "terminal.fill", colors: BadgeColors.deep, size: 22)
                        Text(verbatim: "asc CLI").font(.callout.weight(.medium))
                        Pill(toolVersion ?? L.t("common.missing"), toolVersion == nil ? .err : .ok)
                    }
                    Text(L.t("upload.ascHint")).font(.caption).foregroundStyle(.secondary)
                    if toolVersion == nil { ToolInstallButton(tool: "asc", title: L.t("asc.install")) { Task { await session.refresh() } } }
                }
                Step(n: 2, ok: keysOk, title: L.t("upload.stepKeys"), actions: AnyView(Button(L.t("job.doctor")) { Task { await session.run("doctor") } }.controlSize(.small).disabled(session.isBusy))) {
                    Text(L.t("upload.keysIntro")).font(.callout).foregroundStyle(.secondary)
                    FlowLayout(spacing: 6) {
                        ForEach(keyNames, id: \.name) { k in Pill(k.name + (k.present ? " ✓" : ""), k.present ? .ok : .err) }
                    }
                    if !keysOk {
                        Text(L.t("upload.keysWhere")).font(.caption).foregroundStyle(.secondary)
                        Button(L.t("upload.howToKeys")) { session.page = .setup }.controlSize(.small).accessibilityIdentifier("upload.howToKeys")
                    }
                    if let d = doctor, let checks = d.result?.objectValue?["checks"]?.arrayValue { DoctorChecks(checks: checks) }
                }
                Step(n: 3, ok: approved, title: L.t("upload.stepApproval")) {
                    if approved, let a = overview.approval { Text(verbatim: "\(L.t("review.approved")) · \(L.date(a.approvedAt))").font(.callout) }
                    else {
                        if let a = overview.approval, a.status == "approved" { Text(L.t("review.approvalInvalid").replacingOccurrences(of: "{reason}", with: L.reason(StageView(id: "review", status: "blocked", reason: a.problem), overview))).font(.callout).foregroundStyle(.red) }
                        else { Text(L.t("flow.decisionApprove")).font(.callout) }
                        Button(L.t("flow.openReview")) { session.page = .review }.controlSize(.small)
                    }
                }
                Step(n: 4, ok: planOk, title: L.t("upload.stepPlan")) {
                    Text(L.t("upload.dryRunHint")).font(.callout).foregroundStyle(.secondary)
                    VStack(spacing: 6) {
                        Toggle(L.t("upload.creatives"), isOn: $flags.creatives)
                        Toggle(L.t("upload.cpp"), isOn: $flags.cpp).disabled(overview.files["cpp"] != true)
                        Toggle(L.t("upload.events"), isOn: $flags.events)
                        Toggle(L.t("upload.experiment"), isOn: $flags.experiment).disabled(overview.files["experiments"] != true)
                        Toggle(L.t("upload.skipScreenshots"), isOn: $flags.skipScreenshots)
                    }.font(.callout)
                    Button(L.t("upload.dryRun")) { Task { await session.run("upload", args: flags.args.merging(["dryRun": true]) { $1 }) } }.buttonStyle(.borderedProminent).disabled(session.isBusy).accessibilityIdentifier("upload.dryRun")
                    if let p = planJob, !p.summary.isRunning {
                        Pill("\(L.t("upload.lastPlan")) · \(L.date(p.endedAt))", Tone.ofJob(p.status))
                        if let m = p.message { Text(verbatim: m).font(.callout) }
                        PlanTable(session: session, tick: session.changedTick)
                        DisclosureGroup(L.t("upload.planLog")) {
                            ScrollView { Text(planLog(p)).font(.caption.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                                .frame(maxHeight: 260).padding(8).background(RoundedRectangle(cornerRadius: 6).fill(Color(.tertiarySystemFill)))
                        }.font(.callout)
                    }
                }
                Step(n: 5, ok: uploaded != nil && uploaded?.overallHash == overview.approval?.overallHash, title: L.t("upload.stepUpload")) {
                    Button(L.t("upload.now")) { typed = ""; confirmUpload = true }.buttonStyle(.borderedProminent).tint(.red).disabled(!waiting.isEmpty || session.isBusy).accessibilityIdentifier("upload.now")
                    if !waiting.isEmpty { Text(L.t("upload.waitsFor").replacingOccurrences(of: "{steps}", with: waiting.joined(separator: ", "))).font(.callout).foregroundStyle(.red) }
                }
                Text(L.t("upload.after")).font(.title3.bold()).padding(.top, 8)
                readBackCard
                finalizeCard
                submitCard
            }
            .padding(14)
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: session.job?.id) { Task { await trackJobs() } }
        .onChange(of: session.finishedJob?.id) { Task { await trackJobs() } }
        .task { await trackJobs() }
        .sheet(isPresented: $confirmUpload) { uploadConfirmation }
    }

    private var readBackCard: some View {
        Card(L.t("upload.readBack")) {
            if let u = uploaded {
                KeyValueRow(key: L.t("upload.uploaded"), value: L.date(u.uploadedAt))
                HStack { Text(L.t("upload.readBack")).foregroundStyle(.secondary).font(.callout); Spacer(); Pill(u.readBack == "ok" ? L.t("upload.readBackOk") : L.t("upload.differences", u.differences.count), u.readBack == "ok" ? .ok : .err) }
                ForEach(u.differences, id: \.self) { Text($0).font(.caption) }
            } else { Text(L.t("upload.notUploaded")).foregroundStyle(.secondary).font(.callout) }
        }
    }

    private var finalizeCard: some View {
        Card(L.t("upload.finalize")) {
            Text(L.t("upload.finalizeIntro")).font(.callout).foregroundStyle(.secondary)
            if let f = overview.approval?.finalized {
                Pill("\(f.mode) · \(L.date(f.at))", .ok)
            } else {
                Picker("", selection: Binding(get: { deleteResearch.map { $0 ? "delete" : "keep" } ?? "" }, set: { deleteResearch = $0 == "delete" ? true : $0 == "keep" ? false : nil })) {
                    Text(L.t("upload.deleteResearch")).tag("delete")
                    Text(L.t("upload.keepResearch")).tag("keep")
                }.pickerStyle(.inline).labelsHidden().font(.callout)
                Button(L.t("upload.finalize")) { Task { await session.run("finalize", args: ["checked": true, "deleteResearch": .bool(deleteResearch ?? false)]) } }
                    .disabled(session.isBusy || uploaded == nil || deleteResearch == nil)
                if uploaded == nil { Text(L.t("upload.finalizeAfter")).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }

    private var submitCard: some View {
        Card(L.t("upload.submit")) {
            Text(L.t("upload.submitHint")).font(.callout).foregroundStyle(.secondary)
            TextField(overview.app?.bundleId ?? "bundle id", text: $submitBundle).textFieldStyle(.roundedBorder).font(.body.monospaced()).textInputAutocapitalization(.never).autocorrectionDisabled()
            Button(L.t("upload.submit")) { Task { await session.run("submit", args: ["confirm": .string(submitBundle)]) } }.tint(.red)
                .disabled(session.isBusy || submitBundle.isEmpty || submitBundle != overview.app?.bundleId)
        }
    }

    private var uploadConfirmation: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Label(L.t("upload.now"), systemImage: "exclamationmark.triangle.fill").font(.headline).foregroundStyle(.red)
                Text(L.t("upload.confirmText"))
                Text(verbatim: appName).font(.title3.bold())
                TextField(L.t("upload.typeName"), text: $typed).textFieldStyle(.roundedBorder).accessibilityIdentifier("upload.typeName")
                Text(L.t("upload.confirmHint")).font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(16)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.t("common.cancel")) { confirmUpload = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.t("upload.now")) {
                        confirmUpload = false
                        Task { await session.run("upload", args: flags.args.merging(["yes": true]) { $1 }) }
                    }
                    .tint(.red)
                    .disabled(typed.trimmingCharacters(in: .whitespaces) != appName.trimmingCharacters(in: .whitespaces))
                    .accessibilityIdentifier("upload.confirm")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func planLog(_ job: Job) -> String {
        let lines = job.lines.filter { $0.level != "raw" || !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }.map(\.text).joined(separator: "\n")
        return lines.isEmpty ? (job.details ?? []).joined(separator: "\n") : lines
    }

    /// Keeps the last dry run and doctor jobs this page cares about.
    private func trackJobs() async {
        let c = session.client
        if let j = session.jobs.last(where: { $0.command == "upload" && $0.isDryRun }), let full = try? await c.job(j.id) { planJob = full }
        if let j = session.jobs.last(where: { $0.command == "doctor" }), let full = try? await c.job(j.id) { doctor = full }
    }
}

struct Step<Content: View>: View {
    var n: Int
    var ok: Bool
    var title: String
    var actions: AnyView? = nil
    @ViewBuilder var content: Content
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            StepNumber(n: n, done: ok, tone: ok ? .ok : .neutral)
            VStack(alignment: .leading, spacing: 8) {
                HStack { Text(title).font(.headline); Spacer(); actions }
                content
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground).opacity(0.7)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ok ? Color.green.opacity(0.4) : Color(.separator)))
    }
}

/// metadata/upload-plan.json as a table.
struct PlanTable: View {
    var session: ProjectSession
    var tick: Int
    @State private var items: [PlanItem] = []
    @State private var meta = ""

    struct PlanItem: Decodable, Identifiable {
        var area: String
        var locale: String?
        var field: String?
        var target: String?
        var change: String
        var local: String?
        var remote: String?
        var via: String?
        var file: String?
        var id: String { [area, locale, field, target, file, local].compactMap { $0 }.joined(separator: "|") }
    }
    struct Plan: Decodable {
        var generatedAt: String?
        var bundleId: String?
        var uploader: String?
        var remoteKnown: Bool?
        var items: [PlanItem]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !items.isEmpty {
                Text(verbatim: meta).font(.caption).foregroundStyle(.secondary)
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(verbatim: [item.area, item.locale].compactMap { $0 }.joined(separator: " · ")).font(.caption.weight(.medium))
                            Spacer()
                            Pill(item.change, item.change == "unchanged" ? .neutral : item.change == "unknown" ? .info : .warn)
                        }
                        Text(verbatim: item.field ?? item.target ?? item.file ?? "").font(.caption).lineLimit(1)
                        if let local = item.local, !local.isEmpty { Text(verbatim: local).font(.caption2).foregroundStyle(.secondary).lineLimit(2) }
                        if let via = item.via { Text(verbatim: via).font(.caption2).foregroundStyle(.tertiary) }
                    }
                    .padding(.vertical, 3)
                    Divider()
                }
            }
        }
        .task(id: tick) {
            guard let f = try? await session.readFile("metadata/upload-plan.json"), f.exists, let p = try? JSONDecoder().decode(Plan.self, from: Data(f.text.utf8)) else { items = []; return }
            items = p.items
            meta = [p.bundleId, p.uploader, L.date(p.generatedAt), p.remoteKnown == true ? nil : L.t("plan.remoteUnknown")].compactMap { $0 }.joined(separator: " · ")
        }
    }
}

struct DoctorChecks: View {
    var checks: [VitrinJSON]
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(checks.enumerated()), id: \.offset) { _, c in
                if let o = c.objectValue {
                    HStack(alignment: .top, spacing: 6) {
                        let status = o["status"]?.stringValue ?? ""
                        Image(systemName: status == "ok" ? "checkmark.circle.fill" : status == "warn" ? "exclamationmark.triangle.fill" : status == "skip" ? "minus.circle" : "xmark.circle.fill")
                            .foregroundStyle(status == "ok" ? .green : status == "warn" ? .orange : status == "skip" ? .secondary : .red).font(.caption)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(o["title"]?.stringValue ?? "").font(.caption.weight(.medium))
                            if let d = o["detail"]?.stringValue { Text(d).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                            if let f = o["fix"]?.stringValue { Text(verbatim: "→ \(f)").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
        }
    }
}
