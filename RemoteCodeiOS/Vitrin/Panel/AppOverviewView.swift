// Ported from Vitrin for Mac (apps/VitrinMac/VitrinMac/Views/AppOverviewView.swift).
import SwiftUI

/// An App Store Connect app, managed through the asc CLI: a gradient hero, then tabs for the release status, the
/// store text per language, builds, TestFlight, customer reviews, in-app purchases and subscriptions, and every other
/// asc command. Reads run with `--read-only`; every change is confirmed first and shows the command it runs.
struct AppOverviewView: View {
    @Environment(VitrinPanelModel.self) private var model
    @Environment(AppModel.self) private var remote
    var app: ASCApp
    @State private var tab: Tab = .status
    /// The version being prepared (else the newest), filled into the forms that take `--version-id`.
    @State private var versionID: String?
    /// Counts pull-to-refreshes; the page reads everything again.
    @State private var linking = false
    @State private var linkError: String?

    enum Tab: String, CaseIterable, Identifiable {
        case status, metadata, visuals, builds, testflight, reviews, money, analytics, more
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .status: return "gauge.with.dots.needle.67percent"
            case .metadata: return "text.alignleft"
            case .builds: return "shippingbox.fill"
            case .testflight: return "airplane"
            case .reviews: return "star.bubble.fill"
            case .money: return "creditcard.fill"
            case .visuals: return "photo.fill.on.rectangle.fill"
            case .analytics: return "chart.xyaxis.line"
            case .more: return "square.grid.2x2.fill"
            }
        }
        /// The asc command groups shown at the bottom of this tab.
        var groups: [String] {
            switch self {
            case .status: return AscAreas.release
            case .metadata: return AscAreas.listing
            case .visuals: return AscAreas.visuals
            case .builds: return AscAreas.builds
            case .testflight: return AscAreas.testflight
            case .reviews: return AscAreas.reviews
            case .money: return AscAreas.money
            case .analytics: return AscAreas.analytics
            case .more: return AscAreas.more
            }
        }
        var colors: [Color] {
            switch self {
            case .status: return BadgeColors.brand
            case .metadata: return BadgeColors.magic
            case .builds: return BadgeColors.deep
            case .testflight: return BadgeColors.cool
            case .reviews: return BadgeColors.warm
            case .money: return BadgeColors.fresh
            case .visuals: return BadgeColors.warm
            case .analytics: return BadgeColors.deep
            case .more: return BadgeColors.gray
            }
        }
    }

    var body: some View {
        // On a phone the hero scrolls away and the tabs stay.
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                hero.padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)
                Section {
                    Group {
                        if !model.connection.isConnected {
                            ConnectHint().padding(16)
                        } else {
                            switch tab {
                            case .status: AscStatusTab(app: app)
                            case .metadata: AscMetadataTab(app: app)
                            case .builds: AscBuildsTab(app: app)
                            case .testflight: AscTestFlightTab(app: app)
                            case .reviews: AscReviewsTab(app: app)
                            case .money: AscMoneyTab(app: app)
                            case .visuals: AscVisualsTab(app: app)
                            case .analytics: AscAnalyticsTab(app: app)
                            case .more: AscMoreTab(app: app)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .environment(\.ascShelf, AscShelfContext(title: L.t("asc.shelf.title"), intro: L.t("asc.tab.\(tab.rawValue).intro"), groups: tab.groups, prefill: ["app": app.id, "version-id": versionID ?? "", "app-id": app.id]))
                    .id("\(app.id)-\(tab.rawValue)")
                } header: {
                    TabStrip(selection: $tab).padding(.horizontal, 16).padding(.vertical, 8).background(.bar)
                }
            }
        }
        .refreshable { AscCache.shared.reloadVisible() }
        .brandWindowBackground()
        .navigationTitle(app.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: app.id) {
            let editable: Set<String> = ["PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY"]
            if let doc = try? await AscCLI.cached(["versions", "list", "--app", app.id, "--limit", "10"]) {
                let vs = JSONAPI.items(doc)
                versionID = (vs.first { editable.contains(JSONAPI.text($0, "appVersionState")) } ?? vs.first)?["id"]?.stringValue
            }
        }
        .sheet(isPresented: $linking) {
            if let mac = remote.connection {
                VitrinFolderPicker(connection: mac) { path in
                    Task {
                        do {
                            linkError = nil
                            try await model.store?.addProject(path: path)
                        } catch {
                            linkError = error.localizedDescription
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("app.overview")
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                AppIcon(app: app, size: 64).shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                VStack(alignment: .leading, spacing: 4) {
                    Text(app.name).font(.title2.bold()).lineLimit(2).minimumScaleFactor(0.7)
                    Text(app.bundleId).font(.callout.monospaced()).opacity(0.85).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                }
            }
            FlowLayout(spacing: 6) {
                ForEach(app.versions) { v in StatusPill(text: Text(verbatim: "\(ASCWords.platform(v.platform)) \(v.version) · \(ASCWords.state(v.state))"), color: ASCWords.tone(v.state).color, onGradient: true) }
                if let p = model.linkedProject(for: app) { StatusPill(text: Text(L.t("apps.linked").replacingOccurrences(of: "{project}", with: p.name)), color: .white, onGradient: true) }
            }
            FlowLayout(spacing: 8) {
                Link(destination: app.ascURL) { Label(L.t("apps.openASC"), systemImage: "arrow.up.right.square") }
                if let p = model.linkedProject(for: app) {
                    Button { model.open(p) } label: { Label(L.t("apps.openProject"), systemImage: "folder") }
                } else {
                    Button { linking = true } label: { Label(L.t("apps.linkProject"), systemImage: "link.badge.plus") }
                        .accessibilityIdentifier("app.linkProject")
                }
            }
            .buttonStyle(.bordered).tint(.white).controlSize(.small)
            if let linkError { Label(linkError, systemImage: "exclamationmark.triangle.fill").font(.caption).fixedSize(horizontal: false, vertical: true) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.white)
        .padding(16)
        .background(VitrinBrand.gradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// Capsule tabs that scroll sideways when the window is narrow, instead of a segmented control that overflows.
private struct TabStrip: View {
    @Binding var selection: AppOverviewView.Tab
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(AppOverviewView.Tab.allCases) { t in
                    Button { selection = t } label: {
                        HStack(spacing: 6) {
                            VitrinBadge(symbol: t.symbol, colors: t.colors, size: 18)
                            Text(L.t("asc.tab.\(t.rawValue)")).font(.callout.weight(selection == t ? .semibold : .regular)).lineLimit(1)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(selection == t ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(.clear), in: Capsule())
                        .overlay { if selection == t { Capsule().strokeBorder(.white.opacity(0.15), lineWidth: 0.5) } }
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("app.tab.\(t.rawValue)")
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Not connected: how to connect (Vitrin's key or asc's own login), without forcing either.
struct ConnectHint: View {
    @Environment(VitrinPanelModel.self) private var model
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VitrinBadge(symbol: "key.horizontal.fill", colors: BadgeColors.cool, size: 32)
            VStack(alignment: .leading, spacing: 6) {
                Text(model.connection.state == .missingCLI ? L.t("asc.missing") : L.t("asc.connect.title")).font(.headline)
                Text(L.t("asc.connect.detail")).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if model.connection.state == .missingCLI { AscInstallButton() }
                HStack {
                    NavigationLink(value: VitrinRoute.account) { Text(L.t("account.add")) }.buttonStyle(VitrinGradientButtonStyle(fullWidth: false))
                    Button(L.t("onb.tools.again")) { Task { await model.refreshApps() } }.buttonStyle(.bordered)
                }
            }
        }
        .vitrinCard(padding: 16)
        .frame(maxWidth: 720, alignment: .leading)
    }
}

// MARK: shared loading

/// Loads one asc JSON result for a tab, cache first, and shows the content, or a spinner or the error while there is
/// nothing to show. Reloading (the content's `reload`, `refresh`, the page's refresh) always asks App Store Connect.
struct AscLoad<Content: View>: View {
    var args: [String]
    /// Bump to read again from outside (another list on the page changed).
    var refresh = 0
    /// Shown instead of asc's message when the read fails (a public lookup for an app not on the App Store yet).
    var errorText: String? = nil
    /// `asc web` reads go through Apple's web API with POST requests, which `--read-only` refuses.
    var readOnly = true
    @ViewBuilder var content: (VitrinJSON, @escaping () -> Void) -> Content
    @State private var value: VitrinJSON?
    @State private var error: String?
    @State private var updated: Date?
    @State private var seen: String?
    @State private var tick = 0

    var body: some View {
        Group {
            if let shown = value ?? AscCache.shared.peek(args)?.doc {
                content(shown) { tick += 1 }
            } else if let error {
                AscErrorCard(message: error, quiet: errorText) { self.error = nil; tick += 1 }
            } else {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text(L.t("asc.loading")).foregroundStyle(.secondary) }
                    .padding(.vertical, 20)
            }
        }
        .transformPreference(AscUpdatedKey.self) { oldest in
            if let updated { oldest = min(oldest ?? updated, updated) }
        }
        .task(id: "\(args.joined(separator: " "))#\(reloads)") {
            // Coming back to a page runs this again too; only a changed count asks for a new read.
            let force = seen != nil && seen != reloads
            seen = reloads
            do {
                try await AscCLI.read(args, readOnly: readOnly, force: force) { entry in
                    value = entry.doc
                    updated = entry.fetchedAt
                    error = nil
                }
            } catch {
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
    }

    private var reloads: String { "\(tick)#\(refresh)#\(AscCache.shared.revision)" }
}

/// The oldest result a page shows, for its "Updated …" line.
struct AscUpdatedKey: PreferenceKey {
    static let defaultValue: Date? = nil
    static func reduce(value: inout Date?, nextValue: () -> Date?) {
        if let next = nextValue() { value = min(value ?? next, next) }
    }
}

/// How old a page is, and the button that reads all of it again.
struct AscFreshness: View {
    var date: Date

    var body: some View {
        HStack(spacing: 6) {
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                Text(L.t("asc.updated").replacingOccurrences(of: "{time}", with: date.formatted(.relative(presentation: .named).locale(L.locale))))
            }
            if AscCache.shared.isFetching {
                ProgressView().controlSize(.mini)
            } else {
                Button { AscCache.shared.reloadVisible() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).accessibilityLabel(L.t("common.refresh")).accessibilityIdentifier("asc.reload")
            }
        }
        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
    }
}

/// JSON:API helpers: the `data` array, a resource's attributes, a value as text.
enum JSONAPI {
    static func items(_ doc: VitrinJSON) -> [[String: VitrinJSON]] {
        let d = doc.objectValue?["data"] ?? doc
        return (d.arrayValue ?? (d.objectValue.map { [VitrinJSON.object($0)] } ?? [])).compactMap(\.objectValue)
    }
    static func attr(_ item: [String: VitrinJSON], _ key: String) -> VitrinJSON? { item["attributes"]?.objectValue?[key] }
    static func text(_ item: [String: VitrinJSON], _ key: String) -> String {
        guard let v = attr(item, key) else { return "" }
        if case .null = v { return "" }
        return v.display
    }
    /// ISO dates as the user's short date and time.
    static func date(_ s: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let d = f.date(from: s) ?? { f.formatOptions = [.withInternetDateTime]; return f.date(from: s) }()
        return d.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? s
    }
}

/// A column table for a list of resources: each column a title and an attribute key.
struct ResourceTable: View {
    var items: [[String: VitrinJSON]]
    var columns: [(title: String, key: String, kind: Kind)]
    enum Kind { case text, mono, date, state, bool }
    var empty: String
    @State private var query = ""

    private var found: [[String: VitrinJSON]] {
        items.filter { item in
            columns.contains { c in (c.key == "id" ? item["id"] : JSONAPI.attr(item, c.key)).map { AscText.plain(c.key, $0).matches(search: query) } ?? query.isEmpty }
        }
    }

    var body: some View {
        if items.isEmpty {
            Text(empty).foregroundStyle(.secondary).font(.callout).vitrinCard(padding: 14)
        } else {
            let items = found
            // On a phone a row is a stack: a column per line, its title next to its value.
            LazyVStack(spacing: 0) {
                if self.items.count > AscListSearch.threshold { AscListSearch(text: $query).padding(8) }
                if items.isEmpty { Text(L.t("search.noResults")).font(.callout).foregroundStyle(.secondary).padding(12) }
                ForEach(items.indices, id: \.self) { r in
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(columns.indices, id: \.self) { i in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(columns[i].title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                Spacer(minLength: 8)
                                cell(items[r], columns[i]).multilineTextAlignment(.trailing)
                            }
                        }
                    }
                    .font(.callout)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    if r < items.count - 1 { Divider().opacity(0.5) }
                }
            }
            .vitrinCard(padding: 4)
        }
    }

    /// Every value in words (`AscText`): a `.mono` column stays monospaced only for codes that have no words.
    @ViewBuilder private func cell(_ item: [String: VitrinJSON], _ c: (title: String, key: String, kind: Kind)) -> some View {
        let raw = c.key == "id" ? item["id"] : JSONAPI.attr(item, c.key)
        let t = raw.map { AscText.plain(c.key, $0) } ?? ""
        switch c.kind {
        case .text: Text(t.isEmpty ? "—" : t).lineLimit(2).textSelection(.enabled)
        case .mono: Text(t.isEmpty ? "—" : t).font(t == raw?.stringValue ? .callout.monospaced() : .callout).lineLimit(1).textSelection(.enabled)
        case .date: Text(t.isEmpty ? "—" : t).lineLimit(1)
        case .state:
            if let s = raw?.stringValue, !s.isEmpty { Pill(ASCWords.state(s), ASCWords.tone(s)).lineLimit(1) } else { Text(verbatim: "—") }
        case .bool: Image(systemName: raw?.boolValue == true ? "checkmark.circle.fill" : "circle").foregroundStyle(raw?.boolValue == true ? .green : .secondary)
        }
    }
}

/// A tab body with the family padding; the page around it scrolls.
struct AscShelfContext {
    var title = ""
    /// One sentence on what this tab is for, above its content.
    var intro = ""
    var groups: [String] = []
    var prefill: [String: String] = [:]
}
extension EnvironmentValues {
    @Entry var ascShelf = AscShelfContext()
}

struct TabPage<Content: View>: View {
    @Environment(\.ascShelf) private var shelf
    @ViewBuilder var content: Content
    @State private var updated: Date?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
                if !shelf.intro.isEmpty { Text(shelf.intro).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                if let updated { AscFreshness(date: updated) }
                content
                // The rest of asc for this place: every command of the tab's groups, as forms.
                if !shelf.groups.isEmpty { AscCommandShelf(title: shelf.title, groups: shelf.groups, prefill: shelf.prefill).padding(.top, 8) }
            }
                .padding(16)
                .frame(maxWidth: 1000, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onPreferenceChange(AscUpdatedKey.self) { date in Task { @MainActor in updated = date } }
    }
}

// MARK: status

private struct AscStatusTab: View {
    var app: ASCApp
    var body: some View {
        TabPage {
            AscLoad(args: ["status", "--app", app.id]) { doc, reload in
                let o = doc.objectValue ?? [:]
                let summary = o["summary"]?.objectValue ?? [:]
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 12) {
                        let health = summary["health"]?.stringValue ?? ""
                        VitrinBadge(symbol: health == "green" ? "checkmark" : health == "red" ? "exclamationmark" : "hourglass", colors: health == "green" ? BadgeColors.fresh : health == "red" ? BadgeColors.alert : BadgeColors.warm, size: 36)
                        VStack(alignment: .leading, spacing: 4) {
                            SectionTitle(L.t("asc.status.next"), info: "info.asc.status.next")
                            Text(summary["nextAction"]?.stringValue ?? "—").font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                            ForEach(Array((summary["blockers"]?.arrayValue ?? []).enumerated()), id: \.offset) { _, b in
                                Label(b.objectValue?["message"]?.stringValue ?? b.display, systemImage: "exclamationmark.octagon.fill").foregroundStyle(.red).font(.callout)
                            }
                        }
                        Spacer()
                        Button { reload() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless).help(L.t("common.refresh"))
                    }
                    .vitrinCard(padding: 16)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
                        statusCard(L.t("asc.status.appstore"), "storefront.fill", BadgeColors.brand, o["appstore"], [("version", "version"), ("state", "state"), ("platform", "platform"), ("createdDate", "date")])
                        statusCard(L.t("asc.status.review"), "checkmark.seal.fill", BadgeColors.fresh, o["review"], [("state", "state"), ("submittedDate", "date"), ("platform", "platform")])
                        statusCard(L.t("asc.status.build"), "shippingbox.fill", BadgeColors.deep, o["builds"]?.objectValue?["latest"], [("version", "version"), ("buildNumber", "build"), ("processingState", "state"), ("uploadedDate", "date")])
                        statusCard("TestFlight", "airplane", BadgeColors.cool, o["testflight"], [("internalBuildState", "state"), ("externalBuildState", "state")])
                        statusCard(L.t("asc.status.phased"), "chart.bar.fill", BadgeColors.warm, o["phasedRelease"], [("configured", "bool"), ("state", "state")])
                    }
                    ReleaseActions(app: app, status: o, reload: reload)
                    ReviewReadiness(appID: app.id)
                    if let v = o["appstore"]?.objectValue?["versionId"]?.stringValue { ReviewContactCard(versionID: v) }
                    SubmissionHistory(appID: app.id)
                    VersionHistory(appID: app.id)
                }
            }
        }
    }

    @ViewBuilder private func statusCard(_ title: String, _ symbol: String, _ colors: [Color], _ value: VitrinJSON?, _ rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) { VitrinBadge(symbol: symbol, colors: colors, size: 24); Text(title).font(.headline) }
            if let o = value?.objectValue {
                ForEach(rows, id: \.0) { key, kind in
                    if let v = o[key], v != .null {
                        HStack {
                            Text(L.t("asc.field.\(key)")).foregroundStyle(.secondary)
                            Spacer()
                            switch kind {
                            case "state": Pill(ASCWords.state(v.display), ASCWords.tone(v.display))
                            case "date": Text(JSONAPI.date(v.display))
                            case "bool": Text(v.boolValue == true ? L.t("common.yes") : L.t("common.no"))
                            default: Text(v.display).monospacedDigit()
                            }
                        }
                        .font(.callout)
                    }
                }
            } else {
                Text(verbatim: "—").foregroundStyle(.secondary)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .vitrinCard(padding: 14)
    }
}

// MARK: metadata

private struct AscMetadataTab: View {
    var app: ASCApp
    @State private var versionID: String?

    var body: some View {
        TabPage {
            AscLoad(args: ["versions", "list", "--app", app.id, "--limit", "20"]) { doc, _ in
                let versions = JSONAPI.items(doc)
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        SectionTitle(L.t("asc.meta.version"), info: "info.asc.meta.version")
                        Picker("", selection: Binding(get: { versionID ?? versions.first?["id"]?.stringValue ?? "" }, set: { versionID = $0 })) {
                            ForEach(versions.indices, id: \.self) { i in
                                let v = versions[i]
                                Text(verbatim: "\(ASCWords.platform(JSONAPI.text(v, "platform"))) \(JSONAPI.text(v, "versionString")) · \(ASCWords.state(JSONAPI.text(v, "appVersionState")))").tag(v["id"]?.stringValue ?? "")
                            }
                        }
                        .labelsHidden().frame(maxWidth: 360)
                        Spacer()
                    }
                    if let id = versionID ?? versions.first?["id"]?.stringValue {
                        let state = JSONAPI.text(versions.first { $0["id"]?.stringValue == id } ?? [:], "appVersionState")
                        LocalizationEditor(versionID: id, editable: ["PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY"].contains(state), primaryLocale: app.primaryLocale)
                            .id(id)
                    } else {
                        Text(L.t("apps.noVersions")).foregroundStyle(.secondary)
                    }
                    SectionTitle(L.t("asc.meta.appInfo"), info: "info.asc.meta.appInfo")
                    AppInfoEditor(appID: app.id)
                    StoreSettings(appID: app.id)
                }
            }
        }
    }
}

/// The version's localizations: the locales on the left, the fields of the chosen one on the right, with the App
/// Store Connect limits; Save sends only the fields that changed (`asc localizations update --id … --confirm`).
private struct LocalizationEditor: View {
    var versionID: String
    var editable: Bool
    var primaryLocale = ""
    @State private var locale: String?
    @State private var drafts: [String: [String: String]] = [:]
    @State private var saving = false
    @State private var message: (String, Bool)?
    @State private var confirm = false

    static let fields: [(key: String, flag: String, limit: Int, multiline: Bool)] = [
        ("promotionalText", "promotional-text", 170, true), ("description", "description", 4000, true),
        ("keywords", "keywords", 100, false), ("whatsNew", "whats-new", 4000, true),
        ("supportUrl", "support-url", 0, false), ("marketingUrl", "marketing-url", 0, false),
    ]

    var body: some View {
        AscLoad(args: ["localizations", "list", "--version", versionID, "--paginate"]) { doc, reload in
            let items = JSONAPI.items(doc).sorted { JSONAPI.text($0, "locale") < JSONAPI.text($1, "locale") }
            let current = locale ?? items.first { JSONAPI.text($0, "locale") == primaryLocale }.map { JSONAPI.text($0, "locale") } ?? items.first.map { JSONAPI.text($0, "locale") }
            VStack(alignment: .leading, spacing: 12) {
                CapsuleTabs(items: items.map { JSONAPI.text($0, "locale") }, selection: Binding(get: { current ?? "" }, set: { locale = $0 }), title: { l in
                    let id = items.first { JSONAPI.text($0, "locale") == l }?["id"]?.stringValue ?? ""
                    return (drafts[id]?.isEmpty == false ? "• " : "") + AscText.language(l)
                })
                if let item = items.first(where: { JSONAPI.text($0, "locale") == current }), let id = item["id"]?.stringValue {
                    VStack(alignment: .leading, spacing: 12) {
                        if !editable { Label(L.t("asc.meta.locked"), systemImage: "lock.fill").font(.callout).foregroundStyle(.secondary) }
                        ForEach(Self.fields, id: \.key) { f in
                            field(id: id, item: item, f)
                        }
                        if let (m, ok) = message { Label(m, systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill").foregroundStyle(ok ? .green : .red).font(.callout) }
                        HStack {
                            Spacer()
                            if drafts[id]?.isEmpty == false { Button(L.t("common.cancel")) { drafts[id] = nil } }
                            Button { confirm = true } label: { Label(L.t("asc.meta.save"), systemImage: "arrow.up.circle") }
                                .buttonStyle(VitrinGradientButtonStyle(fullWidth: false))
                                .disabled(saving || drafts[id]?.isEmpty != false)
                        }
                        .confirmationDialog(L.t("asc.meta.saveConfirm"), isPresented: $confirm, titleVisibility: .visible) {
                            Button(L.t("asc.meta.save")) { Task { await save(id: id, reload: reload) } }
                            Button(L.t("common.cancel"), role: .cancel) {}
                        } message: {
                            Text((drafts[id] ?? [:]).keys.sorted().map { L.t("asc.field.\($0)") }.joined(separator: ", ") + " · \(AscText.language(current ?? ""))")
                        }
                    }
                    .vitrinCard(padding: 16)
                }
            }
        }
    }

    @ViewBuilder private func field(id: String, item: [String: VitrinJSON], _ f: (key: String, flag: String, limit: Int, multiline: Bool)) -> some View {
        let original = JSONAPI.text(item, f.key)
        let binding = Binding<String>(
            get: { drafts[id]?[f.key] ?? original },
            set: { v in
                var d = drafts[id] ?? [:]
                if v == original { d[f.key] = nil } else { d[f.key] = v }
                drafts[id] = d
            })
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(L.t("asc.field.\(f.key)")).font(.callout.weight(.medium))
                Spacer()
                if f.limit > 0 {
                    let n = binding.wrappedValue.count
                    Text(verbatim: "\(n)/\(f.limit)").font(.caption.monospacedDigit()).foregroundStyle(n > f.limit ? .red : .secondary)
                }
            }
            if f.multiline {
                TextEditor(text: binding).font(.callout).frame(minHeight: f.limit > 1000 ? 140 : 54).scrollContentBackground(.hidden)
                    .padding(6).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8)).disabled(!editable && f.key != "promotionalText")
            } else {
                TextField("", text: binding).textFieldStyle(.roundedBorder).textInputAutocapitalization(.never).autocorrectionDisabled().disabled(!editable)
            }
        }
    }

    private func save(id: String, reload: @escaping () -> Void) async {
        guard let d = drafts[id], !d.isEmpty else { return }
        saving = true
        defer { saving = false }
        var args = ["localizations", "update", "--id", id]
        for f in Self.fields { if let v = d[f.key] { args += ["--\(f.flag)", v] } }
        do {
            let r = try await AscCLI.run(args + ["--output", "json"], readOnly: false)
            if r.ok { drafts[id] = nil; message = (L.t("asc.saved"), true); reload() } else { message = (r.errorLine, false) }
        } catch { message = (error.localizedDescription, false) }
    }
}

/// Name, subtitle and privacy URLs per language (`--type app-info`).
private struct AppInfoEditor: View {
    var appID: String
    var body: some View {
        AscLoad(args: ["localizations", "list", "--app", appID, "--type", "app-info", "--paginate"]) { doc, reload in
            let items = JSONAPI.items(doc).sorted { JSONAPI.text($0, "locale") < JSONAPI.text($1, "locale") }
            VStack(spacing: 0) {
                ForEach(items.indices, id: \.self) { i in
                    let it = items[i]
                    let locale = JSONAPI.text(it, "locale")
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(AscText.language(locale)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            Text(JSONAPI.text(it, "name")).font(.callout.weight(.medium)).lineLimit(1)
                            Text(JSONAPI.text(it, "subtitle")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        AscActionButton(action: AscActions.appInfoText(app: appID, locale: locale, name: JSONAPI.text(it, "name"), subtitle: JSONAPI.text(it, "subtitle")), done: reload)
                            .controlSize(.small).labelStyle(.iconOnly)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    if i < items.count - 1 { Divider().opacity(0.5) }
                }
                if items.isEmpty { Text(L.t("asc.empty")).foregroundStyle(.secondary).padding(12) }
            }
            .vitrinCard(padding: 4)
        }
    }
}

// MARK: builds, TestFlight, reviews, money

private struct AscBuildsTab: View {
    var app: ASCApp
    @State private var tick = 0
    var body: some View {
        TabPage {
            BuildCounters(appID: app.id, version: app.current?.version, platform: app.current?.platform)
            AscLoad(args: ["builds", "list", "--app", app.id, "--limit", "50", "--sort", "-uploadedDate"]) { doc, reload in
                let builds = AscActions.options(doc) { b in "\(JSONAPI.text(b, "version")) · \(ASCWords.state(JSONAPI.text(b, "processingState"))) · \(JSONAPI.date(JSONAPI.text(b, "uploadedDate")))" }
                AscLoad(args: ["testflight", "groups", "list", "--app", app.id]) { gdoc, _ in
                    let groups = AscActions.options(gdoc) { JSONAPI.text($0, "name") }
                    ActionBar(title: L.t("act.section.builds")) {
                        AscActionButton(action: AscActions.addBuildToGroups(builds: builds, groups: groups), done: { reload(); tick += 1 })
                        AscActionButton(action: AscActions.testNotes(builds: builds), done: reload)
                        AscActionButton(action: AscActions.expireBuild(builds: builds), done: { reload(); tick += 1 })
                    }
                }
            }
            BuildList(appID: app.id).id(tick)
            AscSection(title: L.t("asc.builds.uploads"), args: ["builds", "uploads", "list", "--app", app.id, "--limit", "20"])
        }
    }
}

private struct AscTestFlightTab: View {
    var app: ASCApp
    @State private var tick = 0
    var body: some View {
        TabPage {
            AscLoad(args: ["testflight", "groups", "list", "--app", app.id]) { doc, reload in
                let groups = AscActions.options(doc) { JSONAPI.text($0, "name") }
                ActionBar(title: L.t("act.section.testflight")) {
                    AscActionButton(action: AscActions.inviteTester(app: app.id, groups: groups), done: { reload(); tick += 1 }, prominent: true)
                    AscActionButton(action: AscActions.createGroup(app: app.id), done: reload)
                    AscActionButton(action: AscActions.removeTester(app: app.id), done: { tick += 1 })
                    if !groups.isEmpty { AscActionButton(action: AscActions.deleteGroup(groups: groups), done: reload) }
                }
                SectionTitle(L.t("asc.tf.groups"), info: "info.asc.tf.groups")
                BetaGroupList(doc: doc)
            }
            SectionTitle(L.t("asc.tf.testers"), info: "info.asc.tf.testers")
            AscLoad(args: ["testflight", "testers", "list", "--app", app.id, "--limit", "200"], refresh: tick) { doc, _ in
                ResourceTable(items: JSONAPI.items(doc), columns: [
                    (L.t("asc.field.firstName"), "firstName", .text), (L.t("asc.field.lastName"), "lastName", .text),
                    (L.t("asc.field.email"), "email", .mono), (L.t("asc.field.state"), "state", .state),
                ], empty: L.t("asc.empty"))
            }
            AscSection(title: L.t("asc.tf.feedback"), args: ["testflight", "feedback", "list", "--app", app.id, "--limit", "30"], empty: L.t("asc.tf.noFeedback"))
            AscSection(title: L.t("asc.tf.crashes"), args: ["testflight", "crashes", "list", "--app", app.id, "--limit", "30"], empty: L.t("asc.tf.noCrashes"))
            AscSection(title: L.t("asc.tf.betaInfo"), args: ["testflight", "app-localizations", "list", "--app", app.id])
            AscSection(title: L.t("asc.tf.reviewInfo"), args: ["testflight", "review", "view", "--app", app.id])
        }
    }
}

private struct AscReviewsTab: View {
    var app: ASCApp
    @State private var replyTo: [String: VitrinJSON]?
    @State private var onlyUnanswered = false
    @State private var stars = ""
    @State private var query = ""
    var body: some View {
        TabPage {
            AscLoad(args: ["reviews", "ratings", "--app", app.id, "--all"], errorText: L.t("act.ratingsNone")) { doc, _ in
                RatingsCard(doc: doc)
            }
            AscLoad(args: ["reviews", "summarizations", "--app", app.id, "--platform", app.current?.platform ?? "IOS", "--limit", "5"], errorText: L.t("asc.reviews.noSummary")) { doc, _ in
                if !JSONAPI.items(doc).isEmpty { AscDataView(doc: doc) }
            }
            VStack(alignment: .leading, spacing: 8) {
                Toggle(L.t("act.onlyUnanswered"), isOn: $onlyUnanswered)
                HStack {
                    Text(L.t("act.stars"))
                    Spacer()
                    Picker(L.t("act.stars"), selection: $stars) {
                        Text(L.t("act.allStars")).tag("")
                        ForEach((1...5).reversed(), id: \.self) { n in Text(verbatim: String(repeating: "★", count: n)).tag(String(n)) }
                    }
                    .labelsHidden()
                }
            }
            .font(.callout)
            AscLoad(args: ["reviews", "list", "--app", app.id, "--limit", "100", "--sort", "-createdDate"] + (onlyUnanswered ? ["--only-unresponded"] : []) + (stars.isEmpty ? [] : ["--stars", stars])) { doc, reload in
                let all = JSONAPI.items(doc)
                let items = all.filter { r in ["title", "body", "reviewerNickname"].contains { JSONAPI.text(r, $0).matches(search: query) } || AscText.territory(JSONAPI.text(r, "territory")).matches(search: query) }
                if all.count > AscListSearch.threshold { AscListSearch(text: $query) }
                if all.isEmpty { Text(L.t("asc.reviews.none")).foregroundStyle(.secondary).vitrinCard(padding: 14) }
                else if items.isEmpty { Text(L.t("search.noResults")).foregroundStyle(.secondary).vitrinCard(padding: 14) }
                ForEach(items.indices, id: \.self) { i in
                    let r = items[i]
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: String(repeating: "★", count: Int(JSONAPI.attr(r, "rating")?.numberValue ?? 0)) + String(repeating: "☆", count: 5 - Int(JSONAPI.attr(r, "rating")?.numberValue ?? 0))).foregroundStyle(.orange)
                        Text(JSONAPI.text(r, "title")).font(.headline)
                        Text(verbatim: "\(JSONAPI.text(r, "reviewerNickname")) · \(AscText.territory(JSONAPI.text(r, "territory"))) · \(JSONAPI.date(JSONAPI.text(r, "createdDate")))").font(.caption).foregroundStyle(.secondary)
                        Text(JSONAPI.text(r, "body")).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        Button { replyTo = r } label: { Label(L.t("asc.reviews.reply"), systemImage: "arrowshape.turn.up.left") }.buttonStyle(.bordered).controlSize(.small)
                    }
                    .vitrinCard(padding: 14)
                }
                Color.clear.frame(height: 0).sheet(item: Binding(get: { replyTo.map { ReplyTarget(item: $0) } }, set: { replyTo = $0?.item })) { t in
                    ReplySheet(review: t.item) { replyTo = nil; reload() }
                }
            }
        }
    }
    struct ReplyTarget: Identifiable { var item: [String: VitrinJSON]; var id: String { item["id"]?.stringValue ?? "" } }
}

private struct ReplySheet: View {
    var review: [String: VitrinJSON]
    var done: () -> Void
    @State private var text = ""
    @State private var error: String?
    @State private var sending = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(JSONAPI.text(review, "body")).font(.callout).foregroundStyle(.secondary).lineLimit(6)
                }
                Section {
                    TextEditor(text: $text).font(.callout).frame(minHeight: 120)
                } footer: {
                    Text(L.t("asc.reviews.public"))
                }
                if let error { Section { Text(error).foregroundStyle(.red).font(.callout) } }
                Section {
                    Button(L.t("asc.reviews.send")) { Task { await send() } }.buttonStyle(VitrinGradientButtonStyle()).disabled(sending || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            .navigationTitle(L.t("asc.reviews.reply"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.t("common.cancel")) { done() }
                }
            }
        }
    }
    private func send() async {
        guard let id = review["id"]?.stringValue else { return }
        sending = true
        defer { sending = false }
        do {
            let r = try await AscCLI.run(["reviews", "respond", "--review-id", id, "--response", text.trimmingCharacters(in: .whitespacesAndNewlines), "--output", "json"], readOnly: false)
            if r.ok { done() } else { error = r.errorLine }
        } catch { self.error = error.localizedDescription }
    }
}

private struct AscMoneyTab: View {
    var app: ASCApp
    var body: some View {
        TabPage {
            AscLoad(args: ["pricing", "current", "--app", app.id]) { doc, _ in
                let o = doc.objectValue ?? [:]
                HStack(spacing: 14) {
                    VitrinBadge(symbol: "dollarsign", colors: BadgeColors.fresh, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        SectionTitle(L.t("act.price"), info: "info.act.price")
                        Text(o["isFree"]?.boolValue == true ? L.t("act.free") : "\(o["customerPrice"]?.display ?? "—") \(o["currency"]?.display ?? "")").font(.title2.bold())
                        Text(verbatim: "\(L.t("act.baseTerritory")): \(AscText.territory(o["baseTerritory"]?.display ?? "")) · \(L.t("act.proceeds")): \(o["proceeds"]?.display ?? "—")").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .vitrinCard(padding: 14)
            }
            PriceList(title: L.t("asc.money.subscriptions"), args: ["subscriptions", "pricing", "summary", "--app", app.id], key: "subscriptions")
            AscSection(title: L.t("asc.money.groups"), args: ["subscriptions", "groups", "list", "--app", app.id], empty: L.t("asc.money.noGroups"))
            PriceList(title: L.t("asc.money.iap"), args: ["iap", "pricing", "summary", "--app", app.id], key: "iaps")
            AscSection(title: L.t("asc.money.promoted"), args: ["iap", "promoted-purchases", "list", "--app", app.id], empty: L.t("asc.money.noPromoted"))
            AscSection(title: L.t("asc.money.availability"), args: ["pricing", "availability", "view", "--app", app.id])
        }
    }
}

/// What can be done with the release right now, from its state in `asc status`: a new version, the readiness check,
/// the build, the submission, its cancellation, the release, the phased rollout and the version's settings.
private struct ReleaseActions: View {
    var app: ASCApp
    var status: [String: VitrinJSON]
    var reload: () -> Void

    private var appstore: [String: VitrinJSON] { status["appstore"]?.objectValue ?? [:] }
    private var versionID: String? { appstore["versionId"]?.stringValue }
    private var state: String { appstore["state"]?.stringValue ?? "" }
    private var phased: [String: VitrinJSON] { status["phasedRelease"]?.objectValue ?? [:] }

    private static let editable: Set<String> = ["PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY"]
    private static let inReview: Set<String> = ["WAITING_FOR_REVIEW", "IN_REVIEW", "READY_FOR_REVIEW"]
    private static let live: Set<String> = ["READY_FOR_SALE", "READY_FOR_DISTRIBUTION", "REPLACED_WITH_NEW_VERSION", "PROCESSING_FOR_DISTRIBUTION"]

    var body: some View {
        ActionBar(title: L.t("act.section.release")) {
            if versionID == nil || Self.live.contains(state) {
                AscActionButton(action: AscActions.createVersion(app: app.id), done: reload, prominent: true)
            }
            if let v = versionID {
                if Self.editable.contains(state) {
                    AscActionButton(action: AscActions.submit(app: app.id, versionID: v), done: reload, prominent: true)
                    AscActionButton(action: AscActions.attachBuild(versionID: v, app: app.id), done: reload)
                    AscActionButton(action: AscActions.updateVersion(versionID: v), done: reload)
                }
                if Self.inReview.contains(state) {
                    AscActionButton(action: AscActions.cancelSubmission(app: app.id, versionID: v), done: reload)
                }
                if state == "PENDING_DEVELOPER_RELEASE" {
                    AscActionButton(action: AscActions.release(versionID: v), done: reload, prominent: true)
                }
                if let pid = phased["id"]?.stringValue {
                    AscActionButton(action: AscActions.phasedUpdate(phasedID: pid), done: reload)
                } else if !Self.live.contains(state) {
                    AscActionButton(action: AscActions.phasedCreate(versionID: v), done: reload)
                }
            }
            AscActionButton(action: AscActions.validate(app: app.id, versionID: versionID), done: reload)
        }
    }
}

/// `asc reviews ratings --all`: the average and the count, overall and per country (the strongest first).
private struct RatingsCard: View {
    var doc: VitrinJSON
    var body: some View {
        let o = doc.objectValue ?? [:]
        let avg = o["averageRating"]?.numberValue ?? o["average"]?.numberValue ?? o["summary"]?.objectValue?["averageRating"]?.numberValue
        let count = o["totalCount"]?.numberValue ?? o["ratingCount"]?.numberValue
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 16) {
                VitrinBadge(symbol: "star.fill", colors: BadgeColors.warm, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: avg.map { String(format: "%.2f", $0) } ?? "—").font(.largeTitle.bold().monospacedDigit())
                    Text(count.map { L.t("act.ratingCount").replacingOccurrences(of: "{n}", with: String(Int($0))) } ?? L.t("asc.reviews.none")).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }
            let countries = (o["countries"]?.arrayValue ?? o["byCountry"]?.arrayValue ?? []).compactMap(\.objectValue)
                .sorted { ($0["ratingCount"]?.numberValue ?? 0) > ($1["ratingCount"]?.numberValue ?? 0) }.prefix(6)
            if !countries.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(countries.enumerated()), id: \.offset) { _, c in
                        Text(verbatim: "\(AscText.territory(c["country"]?.stringValue ?? c["countryCode"]?.stringValue ?? "")) · \(c["averageRating"]?.numberValue.map { String(format: "%.1f", $0) } ?? "—") · \(Int(c["ratingCount"]?.numberValue ?? 0))")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .vitrinCard(padding: 16)
    }
}

/// What the store shows: the screenshots of the current version as images, then the other kinds of store media.
private struct AscVisualsTab: View {
    var app: ASCApp
    var body: some View {
        TabPage {
            ScreenshotGallery(app: app)
            AscSection(title: L.t("asc.visuals.pages"), args: ["product-pages", "custom-pages", "list", "--app", app.id], empty: L.t("asc.visuals.noPages"))
            if let v = app.current { AscSection(title: L.t("asc.visuals.experiments"), args: ["product-pages", "experiments", "list", "--version-id", v.id], empty: L.t("asc.visuals.noExperiments")) }
            AscSection(title: L.t("asc.visuals.events"), args: ["app-events", "list", "--app", app.id], empty: L.t("asc.visuals.noEvents"))
        }
    }
}

/// The rest of the store: only what the app has shows up here as a list.
private struct AscMoreTab: View {
    var app: ASCApp
    var body: some View {
        TabPage {
            AscSection(title: L.t("asc.more.appClips"), args: ["app-clips", "list", "--app", app.id], empty: L.t("asc.more.noAppClips"))
            AscSection(title: L.t("asc.more.achievements"), args: ["game-center", "achievements", "list", "--app", app.id], empty: L.t("asc.more.noGameCenter"))
            AscSection(title: L.t("asc.more.leaderboards"), args: ["game-center", "leaderboards", "list", "--app", app.id], empty: L.t("asc.more.noGameCenter"))
            AscSection(title: L.t("asc.more.webhooks"), args: ["webhooks", "list", "--app", app.id], empty: L.t("asc.more.noWebhooks"))
            AscSection(title: L.t("asc.more.assets"), args: ["background-assets", "list", "--app", app.id], empty: L.t("asc.more.noAssets"))
        }
    }
}

/// Sales and usage: the weekly insights from App Store Connect's analytics (asc insights), when available.
private struct AscAnalyticsTab: View {
    var app: ASCApp
    var body: some View {
        TabPage {
            WebAnalytics(appID: app.id)
            AnalyticsAccess(appID: app.id)
            WeeklyInsights(appID: app.id)
            PerformanceOverview(appID: app.id)
        }
    }
}
