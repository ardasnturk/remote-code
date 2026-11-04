// Ported from Vitrin Studio (packages/studio/src/pages/Design.tsx), one column for a phone.
import SwiftUI
import UIKit

/// The store screenshots in three steps: pick a style from the samples, write each screenshot's text, render and
/// preview the set. The steps share their files, so an edit survives a look at another step.
struct DesignView: View {
    var session: ProjectSession
    var overview: Overview
    @State private var step: DesignStep?
    @State private var artDirection = StudioFile()
    @State private var shots = StudioFile()
    @State private var preview: RenderedFile?
    @State private var document: StudioSheetFile?

    private var bust: String { String(session.changedTick) }
    private var hasBrief: Bool { overview.briefs.contains { $0.name == "design" } }
    /// Open where the work is: the style while a choice is open or none was made, the texts otherwise.
    private var startStep: DesignStep {
        let waiting = overview.blocker("design-choice") != nil || overview.questions.contains { $0.stage == "design" }
        return waiting || overview.files["artDirection"] != true ? .style : .copy
    }
    private var current: DesignStep { step ?? startStep }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(L.t("design.intro")).font(.callout).foregroundStyle(.secondary)
                CapsuleTabs(items: DesignStep.allCases, selection: Binding(get: { current }, set: { step = $0 }), title: { "\($0.number) · \(L.t($0.title))" })
                if hasBrief { ClaudeButton(session: session, overview: overview, stage: "design") }
                switch current {
                case .style:
                    DesignStyleStep(session: session, overview: overview, file: artDirection, preview: $preview, document: $document)
                case .copy:
                    DesignCopyStep(session: session, overview: overview, file: shots, preview: $preview)
                case .render:
                    DesignRenderStep(session: session, overview: overview, file: shots, preview: $preview)
                }
            }
            .padding(14)
        }
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await session.refresh() }
        .studioFile(artDirection, path: "metadata/art-direction.json", session: session)
        .studioFile(shots, path: "metadata/shots.json", session: session)
        .sheet(item: $preview) { MediaSheet(client: session.client, file: $0, bust: bust) }
        .sheet(item: $document) { StudioDocumentSheet(client: session.client, path: $0.path, title: L.t("visuals.storePreview"), bust: bust) }
    }
}

private enum DesignStep: String, CaseIterable, Hashable {
    case style, copy, render
    var number: Int { (Self.allCases.firstIndex(of: self) ?? 0) + 1 }
    var title: String { "design.step.\(rawValue)" }
}

/// Rendered screenshots are named `<id>_<slug>_<target>.png`.
private enum ShotFiles {
    static func target(of name: String) -> String? {
        guard name.range(of: #"^\d{2}_[a-z0-9-]+_[a-z0-9.-]+\.(png|jpe?g)$"#, options: [.regularExpression, .caseInsensitive]) != nil else { return nil }
        let rest = name.split(separator: "_", maxSplits: 2).last.map(String.init) ?? name
        return (rest as NSString).deletingPathExtension
    }

    static func targets(_ files: [RenderedFile]) -> [String] {
        var seen = Set<String>()
        return files.compactMap { target(of: $0.name) }.filter { seen.insert($0).inserted }
    }

    /// The iPhone target the set was rendered for, so the strip and the thumbnails show one format.
    static func primary(_ files: [RenderedFile]) -> String? {
        let list = targets(files)
        return list.first { $0.hasPrefix("iphone-6.3") } ?? list.first { $0.hasPrefix("iphone") } ?? list.first
    }

    static func image(for id: String, in files: [RenderedFile]) -> RenderedFile? {
        let primary = primary(files)
        return files.first { $0.name.hasPrefix("\(id)_") && (primary == nil || $0.name.contains("_\(primary ?? "").")) } ?? files.first { $0.name.hasPrefix("\(id)_") }
    }
}

// MARK: Step 1: the style

/// The samples, the open choice (or the one in use) and, tucked away, other styles and the art direction itself.
private struct DesignStyleStep: View {
    var session: ProjectSession
    var overview: Overview
    var file: StudioFile
    @Binding var preview: RenderedFile?
    @Binding var document: StudioSheetFile?
    @State private var styles: [String] = []
    @State private var showOthers = false
    @State private var showArtDirection = false

    private var bust: String { String(session.changedTick) }
    private var samples: DesignSamples? { overview.samples }
    private var question: StudioQuestion? { overview.questions.first { $0.stage == "design" } }
    private var decision: Blocker? { overview.blocker("design-choice") }
    private var openStorePreview: () -> Void { { if let p = samples?.storePreview { document = StudioSheetFile(path: p) } } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let question {
                QuestionCard(question: question, session: session, overview: overview)
            } else if let decision {
                BlockerCard(blocker: decision, session: session, overview: overview, openPreview: openStorePreview)
            } else if let chosen {
                chosenCard(chosen)
            }
            samplesContent
            DisclosureGroup(L.t("design.tryOtherStyles"), isExpanded: $showOthers) { otherStyles.padding(.top, 8) }
                .font(.callout.weight(.medium)).accessibilityIdentifier("design.otherStyles")
            DisclosureGroup(L.t("design.artDirectionAdvanced"), isExpanded: $showArtDirection) {
                ArtDirectionEditor(session: session, overview: overview, file: file).padding(.top, 8)
            }
            .font(.callout.weight(.medium)).accessibilityIdentifier("design.artDirection")
        }
    }

    private var chosen: [String: Any]? {
        file.data?.objects("options").first { $0.str("id") == file.data?.str("selected") }
    }

    private func chosenCard(_ option: [String: Any]) -> some View {
        Card {
            Text(verbatim: L.t("design.chosen").replacingOccurrences(of: "{name}", with: option.str("name"))).font(.body.weight(.semibold))
            if let reason = file.data?.str("selectionReason"), !reason.isEmpty {
                Text(verbatim: reason).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if samples?.options.isEmpty == false {
                Text(L.t("design.chooseDesign")).font(.caption).foregroundStyle(.secondary)
                DesignOptions(session: session, overview: overview, openPreview: openStorePreview)
            }
        }
    }

    @ViewBuilder private var samplesContent: some View {
        if let samples {
            if let store = samples.storePreview {
                Card(L.t("visuals.storePreview")) {
                    Button(L.t("design.open")) { document = StudioSheetFile(path: store) }
                        .buttonStyle(.bordered).controlSize(.small).accessibilityIdentifier("design.storePreview")
                }
            }
            if let sheet = samples.contactSheet {
                Card(L.t("design.contactSheet")) {
                    Button { preview = RenderedFile(path: sheet, name: (sheet as NSString).lastPathComponent, bytes: 0) } label: {
                        StudioImage(client: session.client, path: sheet, bust: bust, maxPixels: 1400).frame(maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain).accessibilityIdentifier("design.contactSheet")
                }
            }
        } else {
            Card {
                Text(L.t("design.noSamples")).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button(L.t("visuals.renderSamples")) { Task { await session.run("design", args: ["samples": true]) } }
                    .buttonStyle(.borderedProminent).disabled(session.isBusy).accessibilityIdentifier("design.renderSamples")
            }
        }
    }

    private var otherStyles: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(overview.enums?.presets ?? [], id: \.self) { p in
                StudioCheckRow(on: styles.contains(p), action: { on in if on { styles.append(p) } else { styles.removeAll { $0 == p } } }) {
                    Text(verbatim: p).font(.callout)
                }
            }
            Button(styles.isEmpty ? L.t("visuals.renderSamples") : "\(L.t("visuals.renderSamples")) (\(styles.count))") {
                var args: [String: VitrinJSON] = ["samples": true]
                if !styles.isEmpty { args["styles"] = .array(styles.map { .string($0) }) }
                Task { await session.run("design", args: args) }
            }
            .buttonStyle(.borderedProminent).disabled(session.isBusy).accessibilityIdentifier("design.renderOtherSamples")
            if let s = overview.platforms?.samples, let locale = s.locale, let target = s.target {
                Text(verbatim: "\(locale) · \(target)").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct ArtDirectionEditor: View {
    var session: ProjectSession
    var overview: Overview
    var file: StudioFile
    @State private var json = false

    private var presets: [String] { overview.enums?.presets ?? [] }
    private var options: [[String: Any]] { file.data?.objects("options") ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L.t("design.artDirection")).font(.headline)
                Spacer()
                StudioModeToggle(json: $json)
            }
            if file.loading {
                ProgressView().frame(maxWidth: .infinity)
            } else if file.data == nil || json {
                if !file.exists, !file.dirty {
                    Button(L.t("studio.startEmpty")) { startEmpty() }.buttonStyle(.bordered).accessibilityIdentifier("design.artDirection.startEmpty")
                } else {
                    StudioCodeEditor(file: file, session: session, identifier: "design.artDirection.save", minHeight: 300)
                }
            } else {
                form
            }
        }
    }

    private func startEmpty() {
        var option: [String: Any] = ["id": "brand", "name": "Brand", "rationale": "", "differentiation": ""]
        option["preset"] = presets.first
        file.setData(["options": [option], "selected": "brand", "selectionReason": ""])
    }

    private func edit(_ change: (inout [String: Any]) -> Void) {
        guard var d = file.data else { return }
        change(&d)
        file.setData(d)
    }

    private func setOption(_ i: Int, _ change: (inout [String: Any]) -> Void) {
        edit { d in
            var list = d.objects("options")
            guard list.indices.contains(i) else { return }
            change(&list[i])
            d["options"] = list
        }
    }

    private func remove(_ i: Int) {
        edit { d in
            var list = d.objects("options")
            let id = list[i].str("id")
            list.remove(at: i)
            d["options"] = list
            if d.str("selected") == id { d["selected"] = list.first?.str("id") }
        }
    }

    private func optionText(_ i: Int, _ key: String) -> Binding<String> {
        Binding(get: { options[safe: i]?.str(key) ?? "" }, set: { v in setOption(i) { $0[key] = v } })
    }

    @ViewBuilder private var form: some View {
        StudioPicker(
            L.t("design.selectedOption"), value: file.data?.str("selected") ?? "",
            labeled: options.map { .init(value: $0.str("id"), label: "\($0.str("name")) (\($0.str("id")))") }
        ) { v in edit { $0["selected"] = v } }
        StudioTextField(label: L.t("design.rationale"), text: Binding(get: { file.data?.str("selectionReason") ?? "" }, set: { v in edit { $0["selectionReason"] = v } }), identifier: "design.selectionReason")
        ForEach(options.indices, id: \.self) { optionCard($0) }
        if options.count < 6 {
            Button {
                edit { d in
                    var list = d.objects("options")
                    let n = list.count
                    var option: [String: Any] = ["id": "option-\(n + 1)", "name": "Option \(n + 1)", "rationale": "", "differentiation": ""]
                    if !presets.isEmpty { option["preset"] = presets[n % presets.count] }
                    list.append(option)
                    d["options"] = list
                }
            } label: { Label(L.t("design.options"), systemImage: "plus") }
                .buttonStyle(.bordered).accessibilityIdentifier("design.addOption")
        }
        StudioSaveBar(file: file, session: session, identifier: "design.save")
    }

    private func optionCard(_ i: Int) -> some View {
        let opt = options[i]
        let selected = opt.str("id") == file.data?.str("selected")
        return Card(accent: selected) {
            HStack {
                Text(verbatim: opt.str("name")).font(.headline)
                Text(verbatim: opt.str("id")).font(.caption.monospaced()).foregroundStyle(.secondary)
                Spacer()
                if options.count > 1 {
                    Button { remove(i) } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless).accessibilityLabel(L.t("design.removeOption")).accessibilityIdentifier("design.removeOption.\(i)")
                }
            }
            StudioTextField(
                label: L.t("design.slug"),
                text: Binding(get: { options[safe: i]?.str("id") ?? "" }, set: { v in setOption(i) { $0["id"] = DesignSlug.clean(v) } }),
                mono: true, identifier: "design.option.id.\(i)"
            )
            StudioTextField(label: L.t("design.name"), text: optionText(i, "name"), identifier: "design.option.name.\(i)")
            StudioPicker(L.t("design.preset"), value: opt.str("preset"), options: presets, empty: opt["palette"] != nil ? L.t("design.bespokePalette") : "—") { v in setOption(i) { $0["preset"] = v.isEmpty ? nil : v } }
            brandColor(i, opt)
            StudioPicker(L.t("design.emphasis"), value: opt.str("emphasis"), options: overview.enums?.emphasis ?? [], empty: L.t("design.fromPreset")) { v in setOption(i) { $0["emphasis"] = v.isEmpty ? nil : v } }
            StudioPicker(L.t("design.kicker"), value: opt.str("kicker"), options: ["plain", "tag"], empty: L.t("design.fromPreset")) { v in setOption(i) { $0["kicker"] = v.isEmpty ? nil : v } }
            StudioField(label: L.t("design.cycle"), hint: L.t("design.cycleHint")) {
                StudioListField(value: opt.strings("cycle"), placeholder: "#3D5AFE, #FF6A3D, #0B7A5E") { v in setOption(i) { $0["cycle"] = v.isEmpty ? nil : v } }
                HStack(spacing: 4) {
                    ForEach(Array(opt.strings("cycle").enumerated()), id: \.offset) { _, c in
                        Circle().fill(HexColor.color(c) ?? .clear).frame(width: 16, height: 16).overlay(Circle().strokeBorder(.secondary.opacity(0.4), lineWidth: 0.5))
                    }
                }
            }
            StudioTextField(label: L.t("design.rationale"), text: optionText(i, "rationale"), multiline: true, minHeight: 60, identifier: "design.option.rationale.\(i)")
            StudioTextField(label: L.t("design.differentiation"), text: optionText(i, "differentiation"), multiline: true, minHeight: 60, identifier: "design.option.differentiation.\(i)")
        }
    }

    private func brandColor(_ i: Int, _ opt: [String: Any]) -> some View {
        let primary = opt.object("brand").str("primary")
        return StudioField(label: L.t("design.brandPrimary")) {
            HStack {
                ColorPicker(
                    selection: Binding(
                        get: { HexColor.color(primary.isEmpty ? "#7B6CFF" : primary) ?? .accentColor },
                        set: { c in setBrand(i, HexColor.hex(c)) }
                    ), supportsOpacity: false
                ) { EmptyView() }
                .labelsHidden()
                TextField(String("#RRGGBB"), text: Binding(get: { options[safe: i]?.object("brand").str("primary") ?? "" }, set: { setBrand(i, $0) }))
                    .textFieldStyle(.roundedBorder).font(.callout.monospaced())
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    .accessibilityIdentifier("design.option.brand.\(i)")
            }
        }
    }

    /// An empty color clears the brand block, as in the Studio; its other keys go with it.
    private func setBrand(_ i: Int, _ value: String) {
        setOption(i) { o in
            guard !value.isEmpty else { o["brand"] = nil; return }
            var brand = o["brand"] as? [String: Any] ?? ["primary": "#000000"]
            brand["primary"] = value
            o["brand"] = brand
        }
    }
}

private enum DesignSlug {
    /// What the Studio does to a short name as it is typed.
    static func clean(_ text: String) -> String {
        text.lowercased().unicodeScalars.map { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" ? String($0) : "-" }.joined()
    }
}

private enum HexColor {
    static func color(_ hex: String) -> Color? {
        let digits = hex.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        return Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }

    static func hex(_ color: Color) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: nil)
        let byte = { (v: CGFloat) in Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
    }
}

// MARK: Step 2: the texts

private struct DesignCopyStep: View {
    var session: ProjectSession
    var overview: Overview
    var file: StudioFile
    @Binding var preview: RenderedFile?
    @State private var locale = ""
    @State private var selected = 0
    @State private var json = false
    @State private var technical = false

    private var bust: String { String(session.changedTick) }
    private var locales: [String] { overview.config?.locales ?? [] }
    private var shots: [[String: Any]] { file.data?.objects("shots") ?? [] }
    private var shot: [String: Any]? { shots[safe: selected] }
    private var rendered: [RenderedFile] { overview.screenshots[locale] ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if file.loading {
                ProgressView().frame(maxWidth: .infinity)
            } else if file.data == nil || json {
                HStack { Text(verbatim: "shots.json").font(.headline); Spacer(); StudioModeToggle(json: $json) }
                if !file.exists, !file.dirty {
                    Card {
                        Text(L.t("design.noShots")).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Button(L.t("studio.startEmpty")) { file.setData(["shots": [newShot("01")]]) }.buttonStyle(.bordered).accessibilityIdentifier("design.startEmpty")
                    }
                } else {
                    StudioCodeEditor(file: file, session: session, identifier: "design.shots.save")
                }
            } else {
                CapsuleTabs(items: locales, selection: $locale, title: { $0 }, mono: true)
                HStack { Spacer(); StudioModeToggle(json: $json) }
                shotList
                if let shot {
                    editor(shot)
                    shotPreview(shot)
                } else {
                    EmptyHint(text: L.t("design.noShots"), symbol: "photo")
                }
            }
        }
        .onAppear { if locale.isEmpty { locale = locales.first ?? "en-US" } }
        .onChange(of: shots.count) { if selected >= shots.count { selected = max(0, shots.count - 1) } }
    }

    private func newShot(_ id: String) -> [String: Any] {
        let copy: [String: Any] = Dictionary(uniqueKeysWithValues: locales.map { ($0, ["kicker": "", "headline": "Headline", "subheadline": ""] as [String: Any]) })
        return ["id": id, "slug": "shot-\(id)", "archetype": "hero", "screens": [String](), "copy": copy, "featureIds": [String](), "framing": "auto"]
    }

    private func numbered(_ n: Int) -> String { String(format: "%02d", n) }

    private func setShots(_ list: [[String: Any]]) {
        guard var d = file.data else { return }
        d["shots"] = list
        file.setData(d)
    }

    private func setShot(_ change: (inout [String: Any]) -> Void) {
        var list = shots
        guard list.indices.contains(selected) else { return }
        change(&list[selected])
        setShots(list)
    }

    /// Ids follow the order.
    private func renumber(_ list: [[String: Any]]) -> [[String: Any]] {
        list.enumerated().map { n, s in
            var s = s
            s["id"] = numbered(n + 1)
            return s
        }
    }

    private func move(_ direction: Int) {
        let j = selected + direction
        guard shots.indices.contains(selected), shots.indices.contains(j) else { return }
        var list = shots
        list.swapAt(selected, j)
        setShots(renumber(list))
        selected = j
    }

    private var shotList: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 8) {
                ForEach(shots.indices, id: \.self) { i in shotTile(i, shots[i]) }
                Button {
                    setShots(shots + [newShot(numbered(shots.count + 1))])
                    selected = shots.count - 1
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "plus").font(.title3)
                        Text(L.t("design.addShot")).font(.caption)
                    }
                    .frame(width: 96, height: 184)
                    .background(RoundedRectangle(cornerRadius: 10).strokeBorder(.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4])))
                }
                .buttonStyle(.plain).disabled(shots.count >= 10).accessibilityIdentifier("design.addShot")
            }
            .padding(.vertical, 2)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func shotTile(_ i: Int, _ s: [String: Any]) -> some View {
        let on = i == selected
        let headline = s.object("copy").object(locale).str("headline")
        return Button { selected = i } label: {
            VStack(alignment: .leading, spacing: 3) {
                Group {
                    if let image = ShotFiles.image(for: s.str("id"), in: rendered) {
                        StudioImage(client: session.client, path: image.path, bust: bust, maxPixels: 320)
                    } else {
                        RoundedRectangle(cornerRadius: 6).fill(Color(.tertiarySystemFill))
                    }
                }
                .frame(width: 96, height: 118)
                Text(verbatim: s.str("id")).font(.caption.weight(.semibold))
                Text(verbatim: headline.isEmpty ? "—" : headline).font(.caption2).foregroundStyle(.secondary).lineLimit(2).frame(width: 96, alignment: .leading)
            }
            .padding(5)
            .frame(height: 184, alignment: .top)
            .background(RoundedRectangle(cornerRadius: 10).fill(on ? Color.accentColor.opacity(0.14) : Color(.secondarySystemBackground).opacity(0.7)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(on ? Color.accentColor : .clear))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("design.shot.\(i)")
    }

    private func copyText(_ key: String) -> Binding<String> {
        Binding(get: { shot?.object("copy").object(locale).str(key) ?? "" }, set: { v in
            setShot { s in
                var copy = s.object("copy")
                var entry = copy[locale] as? [String: Any] ?? ["headline": ""]
                entry[key] = v
                copy[locale] = entry
                s["copy"] = copy
            }
        })
    }

    private func editor(_ s: [String: Any]) -> some View {
        let headline = s.object("copy").object(locale).str("headline")
        let words = headline.split(whereSeparator: \.isWhitespace).count
        return Card {
            HStack {
                Text(verbatim: s.str("id")).font(.headline)
                Text(verbatim: s.str("slug")).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
            }
            FlowLayout(spacing: 8) {
                Button { move(-1) } label: { Image(systemName: "arrow.up") }.buttonStyle(.bordered).controlSize(.small).disabled(selected == 0)
                    .accessibilityLabel(L.t("design.moveUp")).accessibilityIdentifier("design.moveUp")
                Button { move(1) } label: { Image(systemName: "arrow.down") }.buttonStyle(.bordered).controlSize(.small).disabled(selected == shots.count - 1)
                    .accessibilityLabel(L.t("design.moveDown")).accessibilityIdentifier("design.moveDown")
                Button(L.t("design.removeShot"), role: .destructive) {
                    var list = shots
                    list.remove(at: selected)
                    setShots(renumber(list))
                }
                .buttonStyle(.bordered).controlSize(.small).disabled(shots.count <= 1).accessibilityIdentifier("design.removeShot")
                Button(L.t("design.renderShot")) { Task { await session.run("design", args: ["only": .array([.string(s.str("id"))])]) } }
                    .buttonStyle(.borderedProminent).controlSize(.small).disabled(session.isBusy || file.dirty).accessibilityIdentifier("design.renderShot")
            }
            if file.dirty { Text(L.t("design.saveToRender")).font(.caption).foregroundStyle(.secondary) }
            StudioTextField(label: L.t("design.kicker"), text: copyText("kicker"), identifier: "design.kicker")
            StudioTextField(label: L.t("design.headline"), text: copyText("headline"), hint: L.t("design.headlineHint").replacingOccurrences(of: "{n}", with: "\(words)"), identifier: "design.headline")
            StudioTextField(label: L.t("design.subheadline"), text: copyText("subheadline"), identifier: "design.subheadline")
            BulletsField(shot: s, locale: locale) { bullets in setShot { $0["bullets"] = bullets } }
            ScreenPicker(session: session, overview: overview, locale: locale, value: s.strings("screens")) { screens in setShot { $0["screens"] = screens } }
            StudioField(label: L.t("design.featureIds")) {
                StudioListField(value: s.strings("featureIds"), placeholder: "feature-id") { v in setShot { $0["featureIds"] = v } }
            }
            DisclosureGroup(L.t("design.shotTechnical"), isExpanded: $technical) { technicalFields(s).padding(.top, 8) }
                .font(.callout.weight(.medium)).accessibilityIdentifier("design.shotTechnical")
            StudioSaveBar(file: file, session: session, identifier: "design.shots.save")
        }
    }

    private func optionalText(_ key: String) -> Binding<String> {
        Binding(get: { shot?.str(key) ?? "" }, set: { v in setShot { $0[key] = v.isEmpty ? nil : v } })
    }

    private func technicalFields(_ s: [String: Any]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            StudioTextField(
                label: L.t("design.slug"),
                text: Binding(get: { shot?.str("slug") ?? "" }, set: { v in setShot { $0["slug"] = DesignSlug.clean(v) } }),
                mono: true, identifier: "design.slug"
            )
            StudioPicker(L.t("design.archetype"), value: s.str("archetype"), options: overview.enums?.archetypes ?? []) { v in setShot { $0["archetype"] = v } }
            StudioPicker(L.t("design.framing"), value: s["framing"] as? String ?? "auto", options: overview.enums?.framings ?? []) { v in setShot { $0["framing"] = v } }
            Toggle(L.t("design.captionBottom"), isOn: Binding(get: { shot?.str("captionPosition") == "bottom" }, set: { on in setShot { $0["captionPosition"] = on ? "bottom" : "top" } }))
            Toggle(L.t("design.inverted"), isOn: Binding(get: { shot?.flag("inverted") ?? false }, set: { on in setShot { $0["inverted"] = on ? true : nil } }))
            Toggle(L.t("design.bridge"), isOn: Binding(get: { shot?.flag("bridge") ?? false }, set: { on in setShot { $0["bridge"] = on } }))
            Toggle(L.t("design.brandMark"), isOn: Binding(get: { shot?.flag("brandMark") ?? false }, set: { on in setShot { $0["brandMark"] = on } }))
            StudioPicker(L.t("design.bulletStyle"), value: s["bulletStyle"] as? String ?? "check", options: ["check", "chips"]) { v in setShot { $0["bulletStyle"] = v } }
            StudioTextField(label: L.t("design.photo"), text: optionalText("photo"), placeholder: "metadata/photos/… (relative: scene.jpg)", mono: true, identifier: "design.photo")
            StudioTextField(label: L.t("design.template"), text: optionalText("template"), placeholder: "hero.html", mono: true, identifier: "design.template")
            ShotAdvancedJSON(shot: s) { patch in
                setShot { shot in
                    for key in ShotAdvancedJSON.keys { shot[key] = patch[key] }
                }
            }
        }
        .font(.callout)
    }

    @ViewBuilder private func shotPreview(_ s: [String: Any]) -> some View {
        let id = s.str("id")
        if let image = ShotFiles.image(for: id, in: rendered) {
            Card {
                Button { preview = image } label: {
                    StudioImage(client: session.client, path: image.path, bust: bust, maxPixels: 1100).frame(maxWidth: .infinity, maxHeight: 460)
                }
                .buttonStyle(.plain).accessibilityIdentifier("design.shotPreview")
                MediaStrip(client: session.client, files: rendered.filter { $0.name.hasPrefix("\(id)_") }, bust: bust, width: 110, height: 180) { preview = $0 }
            }
        } else {
            EmptyHint(text: L.t("studio.nothingYet"), symbol: "photo")
        }
    }
}

/// The bullets for one language, one per line, keeping the other languages of each bullet. The text stays as typed: an
/// empty last line is where the next bullet goes.
private struct BulletsField: View {
    var shot: [String: Any]
    var locale: String
    var onChange: ([[String: Any]]) -> Void
    @State private var text = ""

    private var bullets: [[String: Any]] { shot.objects("bullets") }
    private var saved: String { bullets.map { $0.str(locale) }.joined(separator: "\n") }

    private func parsed(_ text: String) -> [[String: Any]] {
        let list = text.components(separatedBy: "\n").enumerated().map { n, line -> [String: Any] in
            var b = bullets[safe: n] ?? [:]
            b[locale] = line
            return b
        }
        return Array(list.filter { b in b.values.contains { ($0 as? String)?.isEmpty == false } }.prefix(4))
    }

    private func lines(_ list: [[String: Any]]) -> String { list.map { $0.str(locale) }.joined(separator: "\n") }

    var body: some View {
        StudioTextField(label: L.t("design.bullets"), text: $text, multiline: true, minHeight: 80, identifier: "design.bullets")
            .onAppear { text = saved }
            .onChange(of: saved) { if lines(parsed(text)) != saved { text = saved } }
            .onChange(of: locale) { text = saved }
            .onChange(of: shot.str("id")) { text = saved }
            .onChange(of: text) { if lines(parsed(text)) != saved { onChange(parsed(text)) } }
    }
}

/// The app's screens as thumbnails: the ones this screenshot shows are marked, a tap adds or removes one.
private struct ScreenPicker: View {
    var session: ProjectSession
    var overview: Overview
    var locale: String
    var value: [String]
    var onChange: ([String]) -> Void

    private var raw: [String: [RenderedFile]] { overview.raw[locale] ?? overview.raw.keys.sorted().first.flatMap { overview.raw[$0] } ?? [:] }
    private var family: String? { raw["iphone"] != nil ? "iphone" : raw.keys.sorted().first }
    private var ids: [String] {
        var seen = Set<String>()
        return ((overview.config?.screens.map(\.id) ?? []) + value).filter { seen.insert($0).inserted }
    }

    var body: some View {
        StudioField(label: L.t("design.screensPick")) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(ids, id: \.self) { tile($0) }
                }
                .padding(.vertical, 2)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func tile(_ id: String) -> some View {
        let file = family.flatMap { raw[$0] }?.first { $0.name == "\(id).png" }
        let index = value.firstIndex(of: id)
        return Button {
            if let index {
                var next = value
                next.remove(at: index)
                onChange(next)
            } else {
                onChange(value + [id])
            }
        } label: {
            VStack(spacing: 3) {
                Group {
                    if let file {
                        StudioImage(client: session.client, path: file.path, bust: String(session.changedTick), maxPixels: 260)
                    } else {
                        RoundedRectangle(cornerRadius: 6).fill(Color(.tertiarySystemFill))
                    }
                }
                .frame(width: 72, height: 130)
                Text(verbatim: index.map { "\($0 + 1) · \(id)" } ?? id).font(.caption2).lineLimit(1).truncationMode(.middle).frame(width: 72)
            }
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 8).fill(index != nil ? Color.accentColor.opacity(0.14) : .clear))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(index != nil ? Color.accentColor : .clear))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(index != nil ? .isSelected : [])
        .accessibilityIdentifier("design.screen.\(id)")
    }
}

/// badges, callouts, quotes, wall, stat, targets: the rarer fields, as JSON. What parses counts at once.
private struct ShotAdvancedJSON: View {
    static let keys = ["badges", "callouts", "quotes", "wall", "stat", "targets"]
    var shot: [String: Any]
    var onChange: ([String: Any]) -> Void
    @State private var text = ""
    @State private var problem: String?

    private var saved: String {
        var subset: [String: Any] = [:]
        for key in Self.keys { subset[key] = shot[key] }
        return StudioFile.pretty(subset)
    }

    /// The text in the form `saved` has, so a reformat alone is no edit.
    private func normalized(_ value: [String: Any]) -> String {
        var subset: [String: Any] = [:]
        for key in Self.keys { subset[key] = value[key] }
        return StudioFile.pretty(subset)
    }

    private func parse(_ text: String) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else { throw CocoaError(.propertyListReadCorrupt) }
        return value
    }

    var body: some View {
        StudioField(label: L.t("design.advancedJson")) {
            TextEditor(text: $text)
                .font(.caption.monospaced())
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .frame(minHeight: 120)
                .scrollContentBackground(.hidden).padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(.tertiarySystemFill)))
                .accessibilityIdentifier("design.advancedJson")
            if let problem { Text(verbatim: problem).font(.caption).foregroundStyle(.red) }
        }
        .onAppear { text = saved }
        .onChange(of: saved) { if ((try? parse(text)).map(normalized)) != saved { text = saved } }
        .onChange(of: text) {
            do {
                let value = try parse(text)
                problem = nil
                if normalized(value) != saved { onChange(value) }
            } catch {
                problem = L.t("studio.invalidJSON").replacingOccurrences(of: "{error}", with: error.localizedDescription)
            }
        }
    }
}

// MARK: Step 3: render and preview

/// Render the whole set, see it the way the store shows it, the creatives, and the image issues the quality gate found.
private struct DesignRenderStep: View {
    var session: ProjectSession
    var overview: Overview
    var file: StudioFile
    @Binding var preview: RenderedFile?
    @State private var locale = ""
    @State private var target: String?

    private var bust: String { String(session.changedTick) }
    private var locales: [String] { overview.config?.locales ?? [] }
    private var rendered: [RenderedFile] { overview.screenshots[locale] ?? [] }
    private var targets: [String] { ShotFiles.targets(rendered) }
    private var shownTarget: String? {
        if let target, targets.contains(target) { return target }
        return ShotFiles.primary(rendered)
    }
    private var shown: [RenderedFile] {
        guard let t = shownTarget else { return rendered }
        return rendered.filter { $0.name.contains("_\(t).") }
    }
    private var issues: [ValidationIssue] {
        (overview.validation?.issues ?? []).filter { i in
            (i.code.hasPrefix("image.") || i.code.hasPrefix("shot.") || i.code.hasPrefix("badge.")) && (i.locale == nil || i.locale == locale)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            FlowLayout(spacing: 8) {
                Button(L.t("design.renderAll")) { Task { await session.run("design") } }
                    .buttonStyle(.borderedProminent).disabled(session.isBusy).accessibilityIdentifier("design.renderAll")
                Button(L.stage("validate")) { Task { await session.run("validate") } }
                    .buttonStyle(.bordered).disabled(session.isBusy).accessibilityIdentifier("design.validate")
                Button(L.t("flow.openReview")) { session.page = .review }
                    .buttonStyle(.bordered).accessibilityIdentifier("design.openReview")
            }
            CapsuleTabs(items: locales, selection: $locale, title: { $0 }, mono: true)
            if rendered.isEmpty {
                EmptyHint(text: L.t("design.noRender"), symbol: "photo")
            } else {
                Card(shownTarget.map { "\(L.t("design.storeStrip")) · \($0)" } ?? L.t("design.storeStrip")) {
                    if targets.count > 1 {
                        CapsuleTabs(items: targets, selection: Binding(get: { shownTarget ?? "" }, set: { target = $0 }), title: { $0 }, mono: true)
                    }
                    MediaStrip(client: session.client, files: shown, bust: bust, width: 180, height: 340) { preview = $0 }
                    Text(L.t("visuals.count", shown.count, TextLimits.maxScreenshots)).font(.caption).foregroundStyle(.secondary)
                }
            }
            if let creatives = overview.creatives[locale], !creatives.isEmpty {
                Card(L.t("visuals.creatives")) {
                    MediaStrip(client: session.client, files: creatives, bust: bust, width: 220, height: 180) { preview = $0 }
                }
            }
            if !issues.isEmpty {
                Card("\(L.t("design.imageIssues")) · \(issues.count)") {
                    ForEach(issues) { IssueRow(issue: $0) }
                }
            }
        }
        .onAppear { if locale.isEmpty { locale = locales.first ?? "en-US" } }
    }
}
