// Ported from Vitrin Studio (packages/studio/src/pages/Setup.tsx), one column for a phone.
import SwiftUI

/// What this run produces and how it reaches the store, in the order the run needs it. Edits collect in a draft; a bar
/// at the bottom saves them with `vitrin select` (or discards them) and appears only when something changed.
struct SetupView: View {
    @Environment(VitrinPanelModel.self) private var model
    var session: ProjectSession
    var overview: Overview
    @State private var draft: Draft?
    @State private var newLocale = ""
    @State private var doctor: Job?

    struct Draft: Hashable {
        var platforms: [String]
        var assets: [String]
        var targets: [String]
        var locales: [String]
        var primaryLocale: String
        var language: String
        var capture: String
    }

    private static let platformKeys: Set<String> = ["ios", "macos", "watchos", "tvos", "visionos"]
    private static let assetKeys: Set<String> = ["metadata", "screenshots", "previews", "creatives", "events"]
    private static let kindKeys: Set<String> = ["screenshot", "preview", "creative", "event"]
    private static let captureModes: [(mode: String, label: String, hint: String)] = [
        ("html", "setup.captureHtml", "setup.captureHtmlHint"),
        ("launch-args", "setup.captureLaunch", "setup.captureLaunchHint"),
        ("manual", "setup.captureManual", "setup.captureManualHint"),
    ]
    /// Example lines for .env: names only, never values.
    private static let envLines = ["ASC_KEY_PATH": "ASC_KEY_PATH=./secrets/AuthKey_XXXXXXXXXX.p8"]
    private static let ascKeyNames: Set<String> = ["ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_PATH", "ASC_KEY_CONTENT_BASE64"]

    private var report: PlatformsReport? { overview.platforms }

    private var saved: Draft? {
        guard let cfg = overview.config else { return nil }
        return Draft(
            platforms: report?.platforms.filter(\.selected).map(\.platform) ?? [],
            assets: report?.assets.filter(\.selected).map(\.asset) ?? [],
            targets: report?.formats.filter { $0.selected == true }.map(\.target) ?? [],
            locales: cfg.locales,
            primaryLocale: cfg.primaryLocale,
            language: cfg.language ?? "en",
            capture: cfg.capture
        )
    }

    private func same(_ a: [String], _ b: [String]) -> Bool { a.count == b.count && a.allSatisfy(b.contains) }
    private func list(_ values: [String]) -> VitrinJSON { .array(values.map { .string($0) }) }

    /// The `vitrin select` arguments: what differs from the saved config, and nothing else.
    private func args(_ d: Draft, _ s: Draft) -> [String: VitrinJSON] {
        var a: [String: VitrinJSON] = [:]
        if report != nil, !same(d.platforms, s.platforms) { a["platforms"] = list(d.platforms) }
        if report != nil, !same(d.assets, s.assets) { a["assets"] = list(d.assets) }
        if report != nil, !same(d.targets, s.targets) { a["targets"] = list(d.targets) }
        if !same(d.locales, s.locales) { a["locales"] = list(d.locales) }
        if d.primaryLocale != s.primaryLocale { a["primaryLocale"] = .string(d.primaryLocale) }
        if d.language != s.language { a["language"] = .string(d.language == "en" ? "default" : d.language) }
        if d.capture != s.capture { a["capture"] = .string(d.capture) }
        return a
    }

    var body: some View {
        Group {
            if let saved, let draft {
                form(draft, saved)
            } else if overview.config == nil {
                EmptyHint(text: overview.configError ?? L.t("studio.noConfig"), symbol: "exclamationmark.triangle")
            } else {
                ProgressView()
            }
        }
        .task(id: saved) { draft = saved }
        .onChange(of: session.job?.id) { Task { await trackDoctor() } }
        .onChange(of: session.finishedJob?.id) { Task { await trackDoctor() } }
        .task { await trackDoctor() }
    }

    private func form(_ d: Draft, _ s: Draft) -> some View {
        let changes = args(d, s)
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(L.t("setup.intro")).font(.callout).foregroundStyle(.secondary)
                languages(d)
                platforms(d)
                assets(d)
                capture(d)
                uploader
                tools(d)
                keys
                seeds
            }
            .padding(14)
        }
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await session.refresh() }
        .safeAreaInset(edge: .bottom) {
            if !changes.isEmpty {
                HStack {
                    Text(verbatim: L.t("setup.unsaved").replacingOccurrences(of: "{n}", with: "\(changes.count)")).font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button(L.t("setup.discard")) { draft = saved }.buttonStyle(.bordered).accessibilityIdentifier("setup.discard")
                    Button(L.t("common.save")) { Task { await session.run("select", args: changes) } }
                        .buttonStyle(.borderedProminent).disabled(session.isBusy).accessibilityIdentifier("setup.save")
                }
                .padding(10).background(.bar)
            }
        }
    }

    private func toggle(_ key: WritableKeyPath<Draft, [String]>, _ id: String, _ on: Bool) {
        guard var d = draft else { return }
        if on { if !d[keyPath: key].contains(id) { d[keyPath: key].append(id) } }
        else { d[keyPath: key].removeAll { $0 == id } }
        draft = d
    }

    // MARK: Languages

    private func localeName(_ tag: String) -> String {
        L.locale.localizedString(forIdentifier: tag) ?? tag
    }

    private func languages(_ d: Draft) -> some View {
        let all = unique(d.locales + (report?.locales.map(\.locale) ?? []) + overview.listing)
        let blockers = overview.blockers.filter { $0.code == "stray-locales" || $0.code == "primary-locale" }
        let primary = d.locales + (d.locales.contains(d.primaryLocale) ? [] : [d.primaryLocale])
        let notSelected = L.t("setup.notSelected")
        return SetupSection(n: 1, title: L.t("setup.languages")) {
            ForEach(blockers) { BlockerCard(blocker: $0, session: session, overview: overview, primary: true) }
            StudioField(label: L.t("summary.locales"), hint: L.t("setup.localesHint")) {
                ForEach(all, id: \.self) { l in
                    StudioCheckRow(on: d.locales.contains(l), action: { toggle(\.locales, l, $0) }) {
                        FlowLayout(spacing: 6) {
                            Text(verbatim: localeName(l)).font(.callout)
                            Text(verbatim: l).font(.caption.monospaced()).foregroundStyle(.secondary)
                            if overview.listing.contains(l) { Pill(L.t("setup.hasText"), .ok) }
                        }
                    }
                }
                HStack {
                    TextField(L.t("setup.addLocale"), text: $newLocale)
                        .textFieldStyle(.roundedBorder).font(.callout.monospaced())
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .submitLabel(.done).onSubmit(addLocale)
                        .accessibilityIdentifier("setup.addLocale")
                    Button { addLocale() } label: { Image(systemName: "plus") }
                        .buttonStyle(.bordered).disabled(newLocale.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityLabel(L.t("setup.addLocale"))
                }
            }
            StudioPicker(
                L.t("setup.primaryLocale"), value: d.primaryLocale,
                labeled: primary.map { l in .init(value: l, label: "\(localeName(l)) (\(l))\(d.locales.contains(l) ? "" : " · \(notSelected)")") },
                hint: L.t("setup.primaryLocaleHint")
            ) { v in draft?.primaryLocale = v }
            StudioPicker(
                L.t("setup.uiLanguage"), value: d.language,
                labeled: [.init(value: "en", label: "English"), .init(value: "tr", label: "Türkçe")]
            ) { v in draft?.language = v }
        }
    }

    private func unique(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.filter { seen.insert($0).inserted }
    }

    private func addLocale() {
        let l = newLocale.trimmingCharacters(in: .whitespaces)
        guard !l.isEmpty else { return }
        toggle(\.locales, l, true)
        newLocale = ""
    }

    // MARK: Platforms, content, capture

    private func platformLabel(_ id: String, fallback: String? = nil) -> String {
        Self.platformKeys.contains(id) ? L.t("setup.platform.\(id)") : (fallback ?? id)
    }

    private func platforms(_ d: Draft) -> some View {
        SetupSection(n: 2, title: L.t("setup.platforms")) {
            if let report {
                ForEach(report.platforms) { x in
                    StudioCheckRow(on: d.platforms.contains(x.platform), action: { toggle(\.platforms, x.platform, $0) }) {
                        FlowLayout(spacing: 6) {
                            Text(verbatim: platformLabel(x.platform, fallback: x.label)).font(.callout)
                            if x.detected == true { Pill(L.t("setup.detected"), .ok) }
                        }
                    }
                }
                ForEach(unique(report.formats.map(\.platform)), id: \.self) { p in
                    let formats = report.formats.filter { $0.platform == p }
                    StudioField(label: "\(L.t("setup.formats")) · \(platformLabel(p))") {
                        ForEach(unique(formats.map { $0.kind ?? "" }), id: \.self) { kind in
                            Text(verbatim: Self.kindKeys.contains(kind) ? L.t("setup.kind.\(kind)") : kind)
                                .font(.caption).foregroundStyle(.secondary).padding(.top, 4)
                            ForEach(formats.filter { ($0.kind ?? "") == kind }) { f in
                                StudioCheckRow(on: d.targets.contains(f.target), action: { toggle(\.targets, f.target, $0) }) {
                                    FlowLayout(spacing: 6) {
                                        Text(verbatim: f.label ?? f.target).font(.callout)
                                        if let size = f.size { Text(verbatim: size).font(.caption.monospaced()).foregroundStyle(.secondary) }
                                        if f.required == true { Pill(L.t("setup.required"), .info) }
                                    }
                                }
                            }
                        }
                    }
                }
            } else {
                Text(L.t("setup.needsAnalyze")).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func assets(_ d: Draft) -> some View {
        SetupSection(n: 3, title: L.t("setup.content")) {
            if let report {
                ForEach(report.assets) { x in
                    StudioCheckRow(on: d.assets.contains(x.asset), action: { toggle(\.assets, x.asset, $0) }) {
                        Text(verbatim: Self.assetKeys.contains(x.asset) ? L.t("setup.asset.\(x.asset)") : (x.label ?? x.asset)).font(.callout).fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                Text(L.t("setup.needsAnalyze")).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func capture(_ d: Draft) -> some View {
        SetupSection(n: 4, title: L.t("setup.captureMode")) {
            ForEach(Self.captureModes, id: \.mode) { c in
                StudioRadioRow(title: L.t(c.label), hint: L.t(c.hint), on: d.capture == c.mode) { draft?.capture = c.mode }
                    .accessibilityIdentifier("setup.capture.\(c.mode)")
            }
            if !Self.captureModes.contains(where: { $0.mode == d.capture }) {
                StudioRadioRow(title: d.capture, hint: nil, on: true) {}
            }
        }
    }

    // MARK: Uploader and tools

    private var uploader: some View {
        SetupSection(n: 5, title: L.t("setup.uploader")) {
            HStack(spacing: 8) {
                Text(verbatim: "asc CLI").font(.callout.weight(.medium))
                if let asc = overview.tools.asc { Pill("\(L.t("common.installed")) \(asc)", .ok) } else { Pill(L.t("common.missing"), .warn) }
            }
            Text(L.t("setup.uploaderHint")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if overview.tools.asc == nil {
                ToolInstallButton(tool: "asc", title: L.t("tools.install").replacingOccurrences(of: "{tool}", with: "asc")) { Task { await session.refresh() } }
            }
        }
    }

    private struct ToolRow: Identifiable {
        var id: String
        var value: String?
        var needed: Bool
        var install: String
    }

    private func toolRows(_ d: Draft) -> [ToolRow] {
        let t = overview.tools
        let video = overview.stage("video")?.status != "skipped"
        return [
            ToolRow(id: "claude", value: t.claude, needed: true, install: "npm install -g @anthropic-ai/claude-code"),
            ToolRow(id: "ffmpeg", value: t.ffmpeg, needed: video, install: "brew install ffmpeg"),
            ToolRow(id: "asc", value: t.asc, needed: true, install: "brew install asc"),
            ToolRow(id: "brew", value: t.brew, needed: (video && t.ffmpeg == nil) || t.asc == nil, install: "https://brew.sh"),
        ]
    }

    private func tools(_ d: Draft) -> some View {
        SetupSection(n: 6, title: L.t("summary.tools")) {
            Text(L.t("setup.toolsHint")).font(.caption).foregroundStyle(.secondary)
            ForEach(toolRows(d)) { r in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(verbatim: r.id).font(.callout.monospaced())
                        Spacer()
                        if let value = r.value {
                            Pill(value.contains("/") || value.count > 24 ? L.t("common.installed") : value, .ok)
                        } else {
                            Pill(L.t("common.missing"), r.needed ? .err : .neutral)
                        }
                    }
                    Text(verbatim: L.t("setup.toolWhy.\(r.id)") + (r.needed ? "" : " · \(L.t("setup.notNeeded"))")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if r.value == nil, r.needed {
                        if ["claude", "ffmpeg", "asc"].contains(r.id) {
                            ToolInstallButton(tool: r.id, title: L.t("tools.install").replacingOccurrences(of: "{tool}", with: r.id)) { Task { await session.refresh() } }
                        } else {
                            CopyCode(text: r.install)
                        }
                    }
                }
                .padding(.vertical, 3)
                if r.id != "brew" { Divider() }
            }
        }
    }

    // MARK: Keys and seeds

    /// The App Store keys count as present when the app is connected (Vitrin's key or asc's own login), as on the upload page.
    private var missingKeys: [String] {
        overview.missingKeys.filter { !(model.connection.isConnected && Self.ascKeyNames.contains($0)) }
    }

    private var keys: some View {
        SetupSection(n: 7, title: L.t("setup.keys")) {
            FlowLayout(spacing: 8) {
                Button(L.t("setup.doctor")) { Task { await session.run("doctor") } }
                    .buttonStyle(.bordered).controlSize(.small).disabled(session.isBusy).accessibilityIdentifier("setup.doctor")
                Button(L.t("setup.doctorTools")) { Task { await session.run("doctor", args: ["tools": true]) } }
                    .buttonStyle(.bordered).controlSize(.small).disabled(session.isBusy).accessibilityIdentifier("setup.doctorTools")
            }
            if missingKeys.isEmpty {
                Pill(L.t("setup.keysOk"), .ok)
            } else {
                missingKeysGuide
            }
            if let checks = doctor?.result?.objectValue?["checks"]?.arrayValue { DoctorChecks(checks: checks) }
        }
    }

    @ViewBuilder private var missingKeysGuide: some View {
        let apple = missingKeys.contains { $0.hasPrefix("ASC_") }
        Text(L.t("setup.keysMissing")).font(.callout)
        FlowLayout(spacing: 6) {
            ForEach(missingKeys, id: \.self) { Pill($0, .err) }
        }
        if apple {
            Text(L.t("flow.accountOnHome")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text(L.t("setup.keysStepsTitle")).font(.callout.weight(.semibold))
            ForEach(1...3, id: \.self) { n in
                Text(verbatim: "\(n). \(L.t("setup.keysStep\(n)"))").font(.callout).fixedSize(horizontal: false, vertical: true)
            }
        }
        Text(L.t("setup.keysEnvSnippet")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        CopyCode(text: missingKeys.map { Self.envLines[$0] ?? "\($0)=" }.joined(separator: "\n"))
        Text(L.t("setup.keysHint")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    private var seeds: some View {
        SetupSection(n: 8, title: L.t("setup.seeds")) {
            Text(L.t("setup.seedsHint")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            switch overview.config?.seeds {
            case .perLocale(let byLocale):
                ForEach(byLocale.keys.sorted(), id: \.self) { l in
                    KeyValueRow(key: l, value: byLocale[l]?.joined(separator: ", ") ?? "")
                }
            case .list(let list):
                Text(verbatim: list.isEmpty ? "—" : list.joined(separator: ", ")).font(.callout).textSelection(.enabled)
            case nil:
                Text(verbatim: "—").font(.callout)
            }
        }
    }

    private func trackDoctor() async {
        if let j = session.jobs.last(where: { $0.command == "doctor" }), let full = try? await session.client.job(j.id) { doctor = full }
    }
}

/// A numbered card of the setup page.
private struct SetupSection<Content: View>: View {
    var n: Int
    var title: String
    @ViewBuilder var content: Content
    var body: some View {
        Card {
            HStack(spacing: 8) {
                StepNumber(n: n, done: false)
                Text(verbatim: title).font(.headline)
            }
            content
        }
    }
}
