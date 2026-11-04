// Ported from Vitrin for Mac (apps/VitrinMac/VitrinMac/Core/ProjectSession.swift).
import Foundation
import Observation

/// Everything the phone knows about one open project: the overview, the running job, the log lines and Claude's runs,
/// kept current from the Studio's events. The Studio itself runs on the Mac, started by the hub. Owned by `VitrinStore`.
@MainActor @Observable final class ProjectSession {
    let project: VitrinProject
    let client: StudioClient
    private let store: VitrinStore
    private(set) var isReady = false
    private(set) var overview: Overview?
    private(set) var loadError: String?
    private(set) var job: JobSummary?
    private(set) var finishedJob: JobSummary?
    private(set) var jobs: [JobSummary] = []
    private(set) var logs: [LogLine] = []
    private(set) var claudeRuns: [ClaudeRun] = []
    private(set) var claudeRunning = false
    private(set) var remotion: RemotionState?
    /// Bumps when files under metadata/ changed, so galleries reload.
    private(set) var changedTick = 0
    /// One-line messages for the toast area (newest last).
    private(set) var toasts: [Toast] = []
    /// The page on show, and the two sheets every page can raise.
    var page: ProjectPage = .flow
    var showClaude = false
    var showLog = false
    private var refreshTask: Task<Void, Never>?
    private var startTask: Task<Void, Never>?
    private var seq = 0

    struct Toast: Identifiable, Hashable {
        enum Tone { case ok, info, error }
        let id = UUID()
        var text: String
        var tone: Tone
    }

    init(project: VitrinProject, store: VitrinStore) {
        self.project = project
        self.store = store
        client = StudioClient(project: project.id, store: store)
    }

    var isBusy: Bool { job != nil || claudeRunning }

    // MARK: Lifecycle

    private struct Opened: Decodable { var hello: String? }

    /// Asks the Mac for the project's Studio. Safe to call again: after a reconnect, or when the hub stopped an idle
    /// Studio, this is how the events resume.
    func start() async {
        if let running = startTask { return await running.value }
        let task = Task { [self] in
            store.listen(to: project.id) { [weak self] name, data in
                self?.handle(StudioEvent(name: name, data: Data(data.utf8)))
            }
            do {
                let opened: Opened = try await store.json("POST", "/v1/projects/\(project.id)/open", body: "{}")
                if let hello = opened.hello { handle(StudioEvent(name: "hello", data: Data(hello.utf8))) }
                isReady = true
                await refresh()
            } catch {
                loadError = error.localizedDescription
            }
        }
        startTask = task
        await task.value
        startTask = nil
    }

    func retry() async {
        loadError = nil
        await start()
    }

    // MARK: Data

    func refresh() async {
        do {
            let o = try await client.overview()
            overview = o
            job = o.job
            claudeRunning = o.claude.running
            remotion = o.remotion
            loadError = nil
        } catch {
            if Self.isCancellation(error) { return }
            loadError = error.localizedDescription
        }
        if let list = try? await client.jobs() { jobs = list }
        if let c = try? await client.claude() {
            claudeRuns = c.runs
            claudeRunning = c.running != nil
        }
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    /// Jobs that write to App Store Connect: what the app has read from it is old once they end.
    private static let changesAppStoreConnect: Set<String> = ["upload", "finalize", "submit", "doctor"]

    private func handle(_ e: StudioEvent) {
        switch e.name {
        case "hello":
            struct Hello: Decodable { var job: JobSummary?; var claude: ClaudeID?; var remotion: RemotionState? }
            struct ClaudeID: Decodable { var id: String }
            if let h = e.decode(Hello.self) {
                job = h.job
                claudeRunning = h.claude != nil
                remotion = h.remotion
            }
        case "log":
            if var line = e.decode(LogLine.self) {
                seq += 1
                line.seq = seq
                logs.append(line)
                if logs.count > 5000 { logs.removeFirst(logs.count - 5000) }
            }
        case "job":
            if let j = e.decode(JobSummary.self) {
                if j.isRunning {
                    job = j
                } else {
                    if job?.id == j.id || job == nil { job = nil }
                    finishedJob = j
                    if Self.changesAppStoreConnect.contains(j.command) { AscCache.shared.markStale() }
                    announce(j)
                    scheduleRefresh()
                }
                if let i = jobs.firstIndex(where: { $0.id == j.id }) { jobs[i] = j } else { jobs.append(j) }
            }
        case "claude":
            if let ev = e.decode(ClaudeEvent.self) {
                switch ev.type {
                case "init": claudeRunning = true
                case "exit":
                    claudeRunning = false
                    scheduleRefresh()
                default: break
                }
                if let runId = ev.runId {
                    if let i = claudeRuns.firstIndex(where: { $0.id == runId }) {
                        claudeRuns[i].events.append(ev)
                        if ev.type == "exit" {
                            claudeRuns[i].status = (ev.code ?? 1) == 0 ? "done" : "failed"
                            claudeRuns[i].endedAt = ISO8601DateFormatter().string(from: .now)
                        }
                    } else {
                        Task { [weak self] in
                            guard let self, let c = try? await self.client.claude() else { return }
                            self.claudeRuns = c.runs
                        }
                    }
                }
            }
        case "changed":
            changedTick += 1
            scheduleRefresh()
        case "remotion":
            if let r = e.decode(RemotionState.self) { remotion = r }
        default: break
        }
    }

    private func announce(_ j: JobSummary) {
        let name = L.job(j)
        switch j.status {
        case "ok": toast(L.t("toast.jobDone").replacingOccurrences(of: "{name}", with: name), .ok)
        case "needs-input": toast(L.t("toast.jobNeedsInput").replacingOccurrences(of: "{name}", with: name), .info)
        default: toast(L.t("toast.jobFailed").replacingOccurrences(of: "{name}", with: name) + (j.message.map { " — \($0)" } ?? ""), .error)
        }
    }

    func toast(_ text: String, _ tone: Toast.Tone = .info) {
        let t = Toast(text: text, tone: tone)
        toasts.append(t)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(tone == .error ? 8 : 4))
            self?.toasts.removeAll { $0.id == t.id }
        }
    }

    func dismiss(_ toast: Toast) { toasts.removeAll { $0.id == toast.id } }

    /// A request cancelled by a newer one (a view that went away) is not an error worth a toast.
    static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    func report(_ error: Error) {
        if Self.isCancellation(error) { return }
        toast(error.localizedDescription, .error)
    }

    func clearLogs() { logs.removeAll() }

    // MARK: Actions

    /// Starts a stage (one at a time; the server refuses while Claude works).
    func run(_ command: String, args: [String: VitrinJSON] = [:], force: Bool = false) async {
        do {
            job = try await client.run(command, args: args, force: force)
        } catch {
            report(error)
        }
    }

    func askClaude(stage: String? = nil, prompt: String? = nil, extra: String? = nil, fresh: Bool? = nil) async {
        do {
            try await client.askClaude(prompt: prompt, stage: stage, extra: extra, fresh: fresh, model: ClaudeModel.chosen)
            claudeRunning = true
            if let c = try? await client.claude() { claudeRuns = c.runs }
        } catch {
            report(error)
        }
    }

    func cancelClaude() async {
        try? await client.cancelClaude()
    }

    func resetClaude() async {
        do {
            try await client.resetClaude()
            toast(L.t("claude.newConversation"), .ok)
        } catch {
            report(error)
        }
    }

    func answer(_ q: StudioQuestion, _ answer: String) async {
        do {
            try await client.answer(question: q.id, answer: answer, model: ClaudeModel.chosen)
            toast(L.t("toast.answerSent"), .ok)
            claudeRunning = true
            scheduleRefresh()
        } catch {
            report(error)
        }
    }

    func chooseDesign(_ option: DesignSamples.Option) async {
        await askClaude(stage: "design", extra: "The user looked at the design samples in the Vitrin app and chose \(option.letter): “\(option.name)” (\(option.style)). That answers Step 2 of the brief: write art-direction.json with this choice (selectionReason: “The user chose \(option.letter).”) and continue with Step 3.")
        toast(L.t("toast.designChoiceSent").replacingOccurrences(of: "{name}", with: "\(option.letter) · \(option.name)"), .ok)
    }

    /// Remotion Studio runs on the Mac, on its 127.0.0.1: the phone starts and stops it, and can't open it.
    func startRemotion(locale: String?) async {
        do { try await client.startRemotion(locale: locale) } catch { report(error) }
    }

    func stopRemotion() async {
        do { try await client.stopRemotion() } catch { report(error) }
    }

    func readFile(_ path: String) async throws -> EditableFile {
        try await client.file(path)
    }

    func saveFile(_ path: String, text: String) async -> Bool {
        do {
            try await client.save(path, text: text)
            toast(L.t("toast.saved"), .ok)
            return true
        } catch {
            report(error)
            return false
        }
    }

    /// Shows a file in Finder, on the Mac.
    func openInFinder(_ path: String) async {
        try? await client.open(path, reveal: true)
    }
}
