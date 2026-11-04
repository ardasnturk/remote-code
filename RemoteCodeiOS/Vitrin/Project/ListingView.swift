// Ported from Vitrin for Mac (apps/VitrinMac/VitrinMac/Views/ListingView.swift) and Vitrin Studio
// (packages/studio/src/pages/Metadata.tsx), reshaped for a phone.
import SwiftUI

/// The store text per language with the App Store Connect counters and the validation issues next to their fields, and
/// the app-level fields.
struct ListingView: View {
    @Environment(VitrinPanelModel.self) private var model
    var session: ProjectSession
    var overview: Overview
    @State private var importing = false
    @State private var importPreview: AscListingImport.Result?
    @State private var importMessage: (String, Bool)?
    @State private var tab = ""
    @State private var file = StudioFile()
    @State private var json = false
    @State private var report: [ValidationIssue]?
    @FocusState private var focusedURL: String?

    private static let appTab = "__app"
    private static let urlFields: [(key: String, config: String, label: String)] = [
        ("supportUrl", "support", "listing.support"),
        ("marketingUrl", "marketing", "listing.marketing"),
        ("privacyUrl", "privacy", "listing.privacy"),
    ]

    private var locales: [String] { overview.config?.locales ?? [] }
    private var tabs: [String] { locales + [Self.appTab] }
    private var onLocale: Bool { tab != Self.appTab }
    private var path: String {
        switch tab {
        case "": return ""
        case Self.appTab: return "metadata/listing/app.json"
        default: return "metadata/listing/\(tab).json"
        }
    }
    /// Only the text: image, screenshot, badge and video issues belong to the design and video pages. The report itself
    /// has every issue and its fix hint; the overview carries the first 200 without them.
    private var textIssues: [ValidationIssue] {
        (report ?? overview.validation?.issues ?? []).filter { !$0.code.hasPrefix("image.") && !$0.code.hasPrefix("shot.") && !$0.code.hasPrefix("badge.") && !$0.code.hasPrefix("video.") }
    }
    private var issues: [ValidationIssue] { textIssues.filter { $0.locale == tab || $0.file == path } }
    private var app: ASCApp? { overview.app?.bundleId.flatMap { id in model.ascApps.apps.first { $0.bundleId == id } } }
    /// The raw editor brings its own save button; the form has the bar along the bottom.
    private var showsRawEditor: Bool {
        json || file.data == nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(L.t("listing.intro")).font(.callout).foregroundStyle(.secondary)
                FlowLayout(spacing: 8) {
                    Button(L.t("listing.write")) { Task { await session.run("write") } }
                        .buttonStyle(.borderedProminent).disabled(session.isBusy).accessibilityIdentifier("listing.write")
                    Button(L.t("listing.research")) { Task { await session.run("research") } }
                        .buttonStyle(.bordered).disabled(session.isBusy).accessibilityIdentifier("listing.research")
                    if overview.stage("write")?.brief != nil { ClaudeButton(session: session, overview: overview, stage: "write") }
                }
                CapsuleTabs(items: tabs, selection: $tab, title: tabTitle)
                switch tab {
                case Self.appTab: appForm
                default: localeForm
                }
            }
            .padding(14)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            if tab.isEmpty { tab = overview.config?.startLocale ?? "en-US" }
        }
        .studioFile(file, path: path, session: session)
        .task(id: "\(overview.files["validation"] == true)|\(overview.validation?.generatedAt ?? "")") { await loadReport() }
        .safeAreaInset(edge: .bottom) {
            if file.dirty, !showsRawEditor {
                HStack {
                    Text(L.t("listing.unsaved")).font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button(L.t("common.revert")) { Task { await file.revert(session) } }.buttonStyle(.bordered).accessibilityIdentifier("listing.revert")
                    Button(file.saving ? L.t("common.saving") : L.t("common.save")) { Task { await file.save(session) } }
                        .buttonStyle(.borderedProminent).disabled(file.saving).accessibilityIdentifier("listing.save")
                }
                .padding(10).background(.bar)
            }
        }
    }

    private func loadReport() async {
        struct Report: Decodable { var issues: [ValidationIssue] }
        guard overview.files["validation"] == true, let f = try? await session.readFile("metadata/validation.json"), f.exists else { report = nil; return }
        report = (try? JSONDecoder().decode(Report.self, from: Data(f.text.utf8)))?.issues
    }

    private func tabTitle(_ tab: String) -> String {
        switch tab {
        case Self.appTab: return L.t("listing.appLevel")
        default: return tab
        }
    }

    private func edit(_ change: (inout [String: Any]) -> Void) {
        guard var d = file.data else { return }
        change(&d)
        file.setData(d)
    }

    private func text(_ key: String) -> Binding<String> {
        Binding(get: { file.data?.str(key) ?? "" }, set: { v in edit { $0[key] = v } })
    }

    private func optionalText(_ key: String) -> Binding<String> {
        Binding(get: { file.data?.str(key) ?? "" }, set: { v in edit { $0[key] = v.isEmpty ? nil : v } })
    }

    private var modeHeader: some View {
        HStack {
            Spacer()
            StudioModeToggle(json: $json)
        }
    }

    // MARK: One language

    @ViewBuilder private var localeForm: some View {
        if let app, model.connection.isConnected { importCard(app) }
        if let (m, ok) = importMessage {
            Label(m, systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill").foregroundStyle(ok ? .green : .red).font(.callout)
        }
        if file.loading {
            ProgressView().frame(maxWidth: .infinity)
        } else if !file.exists, !file.dirty {
            Card {
                if let error = file.error { Text(verbatim: error).foregroundStyle(.secondary) }
                else { Text(verbatim: L.t("listing.missing").replacingOccurrences(of: "{path}", with: path)).foregroundStyle(.secondary) }
                Text(L.t("listing.noFile")).font(.callout)
                Button(L.t("studio.startEmpty")) { startEmptyLocale() }.buttonStyle(.bordered).accessibilityIdentifier("listing.startEmpty")
            }
        } else if showsRawEditor {
            Card {
                modeHeader
                StudioCodeEditor(file: file, session: session, identifier: "listing.json.save")
            }
        } else {
            editor
            claimsCard
            urlsCard
            issuesCard
        }
    }

    private func startEmptyLocale() {
        file.setData(["locale": tab, "name": "", "subtitle": "", "promotionalText": "", "description": "", "keywords": "", "whatsNew": "", "claims": [Any]()])
    }

    private var editor: some View {
        Card {
            modeHeader
            ForEach(TextLimits.fields, id: \.key) { f in
                FieldEditor(key: f.key, limit: f.limit, text: text(f.key), issues: issues.filter { $0.field == f.key })
                if f.key == "keywords" {
                    let d = file.data ?? [:]
                    KeywordChips(session: session, locale: tab, used: [d.str("keywords"), d.str("name"), d.str("subtitle")], keywords: d.str("keywords")) { v in edit { $0["keywords"] = v } }
                }
            }
            StudioFileIssues(file: file)
        }
    }

    private var claims: [[String: Any]] { file.data?.objects("claims") ?? [] }

    private func setClaim(_ i: Int, _ change: (inout [String: Any]) -> Void) {
        edit { d in
            var list = d.objects("claims")
            guard list.indices.contains(i) else { return }
            change(&list[i])
            d["claims"] = list
        }
    }

    private var claimsCard: some View {
        Card {
            HStack {
                SectionTitle(L.t("listing.claims"))
                Spacer()
                Button {
                    edit { d in d["claims"] = d.objects("claims") + [["text": "", "featureIds": [String]()]] }
                } label: { Image(systemName: "plus") }
                    .buttonStyle(.bordered).controlSize(.small).accessibilityLabel(L.t("listing.addClaim")).accessibilityIdentifier("listing.addClaim")
            }
            if claims.isEmpty { Text(L.t("listing.claimsHint")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            ForEach(claims.indices, id: \.self) { i in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        TextField(L.t("listing.claimPlaceholder"), text: Binding(get: { claims[safe: i]?.str("text") ?? "" }, set: { v in setClaim(i) { $0["text"] = v } }), axis: .vertical)
                            .textFieldStyle(.roundedBorder).font(.callout).accessibilityIdentifier("listing.claim.\(i)")
                        Button {
                            edit { d in
                                var list = d.objects("claims")
                                list.remove(at: i)
                                d["claims"] = list
                            }
                        } label: { Image(systemName: "xmark") }
                            .buttonStyle(.borderless).accessibilityLabel(L.t("listing.removeClaim")).accessibilityIdentifier("listing.removeClaim.\(i)")
                    }
                    StudioListField(value: claims[i].strings("featureIds"), placeholder: "feature-id, other-id") { v in setClaim(i) { $0["featureIds"] = v } }
                }
                .padding(.vertical, 2)
            }
        }
    }

    /// A language's own links; empty ones come from the config.
    private var urlsCard: some View {
        Card(L.t("listing.urls")) {
            ForEach(Self.urlFields, id: \.key) { f in
                StudioField(label: L.t(f.label)) {
                    TextField(configURL(f.config).map { L.t("listing.urlFromConfig").replacingOccurrences(of: "{url}", with: $0) } ?? "", text: optionalText(f.key))
                        .textFieldStyle(.roundedBorder).font(.callout.monospaced())
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($focusedURL, equals: f.key)
                        .accessibilityIdentifier("listing.url.\(f.key)")
                }
            }
            ForEach(issues.filter { i in Self.urlFields.contains { $0.key == i.field } }) { i in
                IssueRow(issue: i)
                Button(L.t("listing.fixIt")) { fixURL(i) }.buttonStyle(.bordered).controlSize(.small)
            }
            Text(L.t("listing.urlsHint")).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func configURL(_ key: String) -> String? {
        switch key {
        case "support": return overview.config?.urls.support
        case "privacy": return overview.config?.urls.privacy
        default: return overview.config?.urls.marketing
        }
    }

    /// A placeholder URL comes from the config unless this language sets its own: fix it where it lives.
    private func fixURL(_ issue: ValidationIssue) {
        guard let field = issue.field else { return }
        if file.data?.str(field).isEmpty == false { focusedURL = field } else { tab = Self.appTab }
    }

    private var issuesCard: some View {
        Card(L.t("listing.issues")) {
            let inline = Set(TextLimits.fields.map(\.key) + Self.urlFields.map(\.key) + ["reviewNotes"])
            let general = issues.filter { i in !inline.contains(i.field ?? "") }
            if issues.isEmpty { Text(overview.validation == nil ? L.t("listing.notValidated") : L.t("listing.noIssues")).foregroundStyle(.secondary) }
            ForEach(general) { IssueRow(issue: $0) }
            if !issues.isEmpty, general.count < issues.count { Text(L.t("listing.fieldIssues", issues.count - general.count)).font(.caption).foregroundStyle(.secondary) }
            Button(L.stage("validate")) { Task { await session.run("validate") } }.controlSize(.small).buttonStyle(.bordered).disabled(session.isBusy)
        }
    }

    // MARK: App level

    @ViewBuilder private var appForm: some View {
        ListingURLsCard(session: session, overview: overview)
        if file.loading {
            ProgressView().frame(maxWidth: .infinity)
        } else if !file.exists, !file.dirty {
            Card {
                Text(L.t("listing.noMetadata")).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button(L.t("studio.startEmpty")) {
                    file.setData(["copyright": "\(Calendar.current.component(.year, from: .now)) ", "primaryCategory": "", "reviewNotes": ""])
                }
                .buttonStyle(.bordered).accessibilityIdentifier("listing.app.startEmpty")
            }
        } else if showsRawEditor {
            Card {
                modeHeader
                StudioCodeEditor(file: file, session: session, identifier: "listing.app.save")
            }
        } else {
            Card(L.t("listing.appLevel")) {
                modeHeader
                StudioTextField(label: L.t("listing.copyright"), text: text("copyright"), identifier: "listing.copyright")
                StudioTextField(label: L.t("listing.primaryCategory"), text: text("primaryCategory"), hint: L.t("listing.primaryCategoryHint"), mono: true, identifier: "listing.primaryCategory")
                StudioTextField(label: L.t("listing.secondaryCategory"), text: optionalText("secondaryCategory"), mono: true, identifier: "listing.secondaryCategory")
                StudioTextField(label: L.t("listing.reviewNotes"), text: text("reviewNotes"), multiline: true, minHeight: 120, max: 4000, bytes: true, identifier: "listing.reviewNotes")
                ForEach(textIssues.filter { $0.locale == nil }) { IssueRow(issue: $0) }
                StudioFileIssues(file: file)
            }
        }
    }

    /// App Store Connect's live text for the linked app: shown, then written into metadata/listing/ on confirmation.
    @ViewBuilder private func importCard(_ app: ASCApp) -> some View {
        let missing = !file.exists && !file.dirty
        VStack(alignment: .leading, spacing: 8) {
            Text(L.t(missing ? "listing.asc.missingTitle" : "listing.asc.title")).font(.headline)
            Text(verbatim: L.t("listing.asc.detail").replacingOccurrences(of: "{app}", with: app.name)).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button { Task { await fetchImport(app) } } label: { Label(L.t("listing.asc.import"), systemImage: "arrow.down.circle") }
                    .buttonStyle(VitrinGradientButtonStyle(fullWidth: false)).disabled(importing || session.isBusy)
                if importing { ProgressView().controlSize(.small) }
            }
        }
        .vitrinCard(padding: 14)
        .confirmationDialog(L.t("listing.asc.confirm"), isPresented: Binding(get: { importPreview != nil }, set: { if !$0 { importPreview = nil } }), titleVisibility: .visible) {
            Button(L.t("listing.asc.write")) { Task { await writeImport() } }
            Button(L.t("common.cancel"), role: .cancel) { importPreview = nil }
        } message: {
            if let r = importPreview {
                let locales = overview.config?.locales ?? []
                let hits = locales.filter { r.listings[$0] != nil }
                Text(verbatim: L.t("listing.asc.confirmDetail").replacingOccurrences(of: "{version}", with: r.versionString).replacingOccurrences(of: "{locales}", with: hits.joined(separator: ", ")).replacingOccurrences(of: "{skipped}", with: r.listings.keys.filter { !locales.contains($0) }.sorted().joined(separator: ", ")).replacingOccurrences(of: #"\s*[^.]*:\s*\.$"#, with: "", options: .regularExpression))
            }
        }
    }

    private func fetchImport(_ app: ASCApp) async {
        importing = true
        defer { importing = false }
        importMessage = nil
        do { importPreview = try await AscListingImport.fetch(appID: app.id) } catch { importMessage = (error.localizedDescription, false) }
    }

    private func writeImport() async {
        guard let r = importPreview else { return }
        importPreview = nil
        importing = true
        defer { importing = false }
        var written: [String] = []
        for locale in overview.config?.locales ?? [] {
            guard let o = r.listings[locale] else { continue }
            do {
                try await session.client.save("metadata/listing/\(locale).json", text: AscListingImport.fileText(o))
                written.append(locale)
            } catch {
                importMessage = ("\(locale): \(error.localizedDescription)", false)
                return
            }
        }
        importMessage = (L.t("listing.asc.done").replacingOccurrences(of: "{n}", with: "\(written.count)"), true)
        await file.revert(session)
        await session.refresh()
    }
}

/// urls.* in vitrin.config.yaml: one place for every language, saved with `vitrin select`.
private struct ListingURLsCard: View {
    var session: ProjectSession
    var overview: Overview
    @State private var draft = Links()

    struct Links: Hashable {
        var support = "", privacy = "", marketing = ""
    }

    private var saved: Links {
        let u = overview.config?.urls
        return Links(support: u?.support ?? "", privacy: u?.privacy ?? "", marketing: u?.marketing ?? "")
    }
    private var args: [String: VitrinJSON] {
        var a: [String: VitrinJSON] = [:]
        if draft.support != saved.support { a["supportUrl"] = .string(draft.support) }
        if draft.privacy != saved.privacy { a["privacyUrl"] = .string(draft.privacy) }
        if draft.marketing != saved.marketing { a["marketingUrl"] = .string(draft.marketing) }
        return a
    }

    var body: some View {
        Card(L.t("listing.urlsTitle")) {
            Text(L.t("listing.urlsAllHint")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            row(L.t("listing.support"), $draft.support, "support")
            row(L.t("listing.privacy"), $draft.privacy, "privacy")
            row(L.t("listing.marketing"), $draft.marketing, "marketing")
            Button(L.t("common.save")) { Task { await session.run("select", args: args) } }
                .buttonStyle(.borderedProminent).disabled(session.isBusy || args.isEmpty).accessibilityIdentifier("listing.urls.save")
        }
        .task(id: saved) { draft = saved }
    }

    private func row(_ label: String, _ text: Binding<String>, _ id: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(verbatim: label).font(.callout.weight(.medium))
                if text.wrappedValue.range(of: #"\bexample\.(com|org|net)\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
                    Pill(L.t("listing.placeholderUrl"), .err)
                }
            }
            TextField(String("https://"), text: text)
                .textFieldStyle(.roundedBorder).font(.callout.monospaced())
                .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                .accessibilityIdentifier("listing.urls.\(id)")
        }
    }
}

/// The research's best keywords that are not in the name, subtitle or keyword field yet: one tap adds one.
private struct KeywordChips: View {
    var session: ProjectSession
    var locale: String
    var used: [String]
    var keywords: String
    var onAdd: (String) -> Void
    @State private var candidates: [ResearchView.KeywordCandidate] = []

    private struct Plan: Decodable { var candidates: [ResearchView.KeywordCandidate] }

    private func score(_ c: ResearchView.KeywordCandidate) -> Double {
        c.total ?? c.popularity.score * (1 - c.competition.score) - 1
    }

    private var terms: [String] {
        let tag = Locale(identifier: locale)
        let have = used.joined(separator: " ").lowercased(with: tag)
        let sorted = candidates.sorted { score($0) > score($1) }.map(\.term)
        let open = sorted.filter { term in !term.lowercased(with: tag).split(whereSeparator: \.isWhitespace).allSatisfy { have.contains($0) } }
        return Array(open.prefix(12))
    }

    var body: some View {
        Group {
            if !terms.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L.t("listing.suggestedKeywords")).font(.caption).foregroundStyle(.secondary)
                    FlowLayout(spacing: 6) {
                        ForEach(terms, id: \.self) { term in
                            Button { add(term) } label: { Text(verbatim: "+ \(term)").font(.caption) }
                                .buttonStyle(.bordered).controlSize(.mini).accessibilityIdentifier("listing.keyword.\(term)")
                        }
                    }
                }
            }
        }
        .task(id: "\(locale)|\(session.changedTick)") {
            guard let f = try? await session.readFile("metadata/research/keywords/\(locale).json"), f.exists,
                  let plan = try? JSONDecoder().decode(Plan.self, from: Data(f.text.utf8)) else { candidates = []; return }
            candidates = plan.candidates
        }
    }

    private func add(_ term: String) {
        var base = keywords.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix(",") { base.removeLast() }
        let next = keywords.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? term : "\(base),\(term)"
        if next.utf8.count > (TextLimits.limit("keywords")?.max ?? 100) {
            session.toast(L.t("listing.keywordNoRoom").replacingOccurrences(of: "{term}", with: term), .error)
        } else {
            onAdd(next)
        }
    }
}

struct FieldEditor: View {
    var key: String
    var limit: TextLimits.Limit
    @Binding var text: String
    var issues: [ValidationIssue]
    private var length: Int { TextLimits.length(text, limit) }
    private var over: Bool { length > limit.max || (limit.required && text.isEmpty) }
    private var multiline: Bool { limit.max > 200 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(L.t("field.\(key)")).font(.callout.weight(.medium))
                if limit.required { Text(verbatim: "*").foregroundStyle(.red) }
                Spacer()
                Text(verbatim: "\(length) / \(limit.max)\(limit.bytes ? " B" : "")").font(.caption.monospacedDigit()).foregroundStyle(over ? .red : length > Int(Double(limit.max) * 0.9) ? .orange : .secondary)
            }
            if multiline {
                TextEditor(text: $text).font(.body).frame(minHeight: key == "description" ? 220 : 120)
                    .scrollContentBackground(.hidden).padding(6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(.tertiarySystemFill)))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(over ? Color.red : .clear))
                    .accessibilityIdentifier("listing.field.\(key)")
            } else {
                TextField("", text: $text).textFieldStyle(.roundedBorder)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(over ? Color.red : .clear))
                    .accessibilityIdentifier("listing.field.\(key)")
            }
            if key == "keywords" {
                let terms = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                Text(L.t("field.keywordsHint", terms.count)).font(.caption).foregroundStyle(text.contains(", ") ? .orange : .secondary)
            }
            ForEach(issues) { IssueRow(issue: $0) }
        }
        .padding(.vertical, 4)
    }
}

struct IssueRow: View {
    var issue: ValidationIssue
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: issue.severity == "error" ? "xmark.octagon.fill" : issue.severity == "warning" ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundStyle(issue.severity == "error" ? .red : issue.severity == "warning" ? .orange : .blue).font(.caption)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: issue.message).font(.caption).textSelection(.enabled)
                if let fix = issue.fix { Text(verbatim: "→ \(fix)").font(.caption).foregroundStyle(.secondary) }
                Text(verbatim: issue.code).font(.caption2.monospaced()).foregroundStyle(.tertiary)
            }
        }
    }
}
