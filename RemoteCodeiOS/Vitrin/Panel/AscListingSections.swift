// Ported from Vitrin for Mac (apps/VitrinMac/VitrinMac/Views/AscListingSections.swift).
import SwiftUI

/// The app's store settings besides the text: categories, age rating, content rights, licence, declarations.
struct StoreSettings: View {
    var appID: String

    private var infoArgs: [String] {
        ["api", "GET", "/v1/apps/\(appID)/appInfos", "--query", "include=primaryCategory,secondaryCategory",
         "--query", "fields[appInfos]=primaryCategory,secondaryCategory,state,appStoreAgeRating"]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(L.t("asc.store.title"), info: "info.asc.store.title")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 12, alignment: .top)], spacing: 12) {
                AscLoad(args: infoArgs) { doc, reload in
                    let info = JSONAPI.items(doc).first ?? [:]
                    SettingCard(symbol: "square.grid.2x2.fill", colors: BadgeColors.magic, title: L.t("asc.store.categories"), info: "info.asc.store.categories") {
                        row(L.t("asc.store.primary"), category(info, "primaryCategory"))
                        row(L.t("asc.store.secondary"), category(info, "secondaryCategory"))
                        AscActionButton(action: AscActions.categories(app: appID), done: reload).controlSize(.small)
                    }
                    SettingCard(symbol: "person.crop.circle.badge.checkmark", colors: BadgeColors.warm, title: L.t("asc.store.age"), info: "info.asc.store.age") {
                        row(L.t("asc.store.ageRating"), JSONAPI.attr(info, "appStoreAgeRating").map { AscText.value($0.display) } ?? "—")
                        AgeRatingDetails(appID: appID)
                    }
                }
                AscLoad(args: ["apps", "content-rights", "view", "--app", appID]) { doc, _ in
                    let value = doc.objectValue?["content_rights_declaration"]?.stringValue ?? ""
                    SettingCard(symbol: "c.circle.fill", colors: BadgeColors.cool, title: L.t("asc.store.rights"), info: "info.asc.store.rights") {
                        Text(value.isEmpty ? L.t("asc.store.notSet") : AscText.value(value)).font(.callout)
                    }
                }
                AscLoad(args: ["eula", "view", "--app", appID], errorText: L.t("asc.store.standardEula")) { doc, _ in
                    let text = JSONAPI.items(doc).first.map { JSONAPI.text($0, "agreementText") } ?? ""
                    SettingCard(symbol: "doc.text.fill", colors: BadgeColors.gray, title: L.t("asc.store.eula"), info: "info.asc.store.eula") {
                        Text(text.isEmpty ? L.t("asc.store.standardEula") : text).font(.callout).lineLimit(4)
                    }
                }
            }
            AscSection(title: L.t("asc.store.encryption"), args: ["encryption", "declarations", "list", "--app", appID], empty: L.t("asc.store.noEncryption"))
            AscSection(title: L.t("asc.store.accessibility"), args: ["accessibility", "list", "--app", appID], empty: L.t("asc.store.noAccessibility"))
            AscSection(title: L.t("asc.store.tags"), args: ["app-tags", "list", "--app", appID], empty: L.t("asc.store.noTags"))
        }
    }

    private func category(_ info: [String: VitrinJSON], _ key: String) -> String {
        guard let id = info["relationships"]?.objectValue?[key]?.objectValue?["data"]?.objectValue?["id"]?.stringValue else { return L.t("asc.store.notSet") }
        return AscText.value(id)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).lineLimit(1)
        }
        .font(.callout)
    }
}

private struct SettingCard<Content: View>: View {
    var symbol: String
    var colors: [Color]
    var title: String
    var info: String? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) { VitrinBadge(symbol: symbol, colors: colors, size: 24); Text(title).font(.headline); if let info { InfoButton(key: info) } }
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .vitrinCard(padding: 14)
    }
}

/// The age rating questionnaire, opened on demand: only what was answered with something other than "none".
private struct AgeRatingDetails: View {
    var appID: String
    @State private var open = false
    var body: some View {
        DisclosureGroup(L.t("asc.store.ageAnswers"), isExpanded: $open) {
            if open {
                AscLoad(args: ["age-rating", "view", "--app", appID]) { doc, _ in
                    let item = JSONAPI.items(doc).first ?? [:]
                    let answers = (item["attributes"]?.objectValue ?? [:]).filter { _, v in
                        if v.boolValue == true { return true }
                        if let s = v.stringValue { return s != "NONE" && !s.isEmpty }
                        return false
                    }
                    if answers.isEmpty {
                        Text(L.t("asc.store.ageNone")).font(.callout).foregroundStyle(.secondary)
                    } else {
                        AscFields(fields: answers.sorted { $0.key < $1.key }.map { (key: $0.key, value: $0.value) })
                    }
                }
            }
        }
        .font(.callout)
    }
}

/// The screenshots of a version in App Store Connect, per language and device, as images.
struct ScreenshotGallery: View {
    var app: ASCApp
    @State private var locale: String?
    @State private var device: String?
    @State private var preview: URL?

    struct Shot: Hashable { var url: URL; var large: URL; var ratio: CGFloat }
    struct Language { var locale: String; var localizationID: String; var devices: [(type: String, shots: [Shot])] }

    private var args: [String] {
        ["screenshots", "list", "--app", app.id] + (app.current.map { ["--version", $0.version, "--platform", $0.platform] } ?? [])
    }

    var body: some View {
        AscLoad(args: args) { doc, _ in
            let languages = Self.languages(doc)
            if languages.isEmpty {
                Label(L.t("asc.visuals.none"), systemImage: "photo").foregroundStyle(.secondary).font(.callout).vitrinCard(padding: 14)
            } else {
                let current = languages.first { $0.locale == locale } ?? languages.first { $0.locale == app.primaryLocale } ?? languages[0]
                let devices = current.devices
                let shown = devices.first { $0.type == device } ?? devices.first
                VStack(alignment: .leading, spacing: 10) {
                    FlowLayout(spacing: 10) {
                        Picker(L.t("asc.visuals.language"), selection: Binding(get: { current.locale }, set: { locale = $0 })) {
                            ForEach(languages, id: \.locale) { l in Text(AscText.language(l.locale)).tag(l.locale) }
                        }
                        if devices.count > 1 {
                            Picker(L.t("asc.visuals.device"), selection: Binding(get: { shown?.type ?? "" }, set: { device = $0 })) {
                                ForEach(devices, id: \.type) { d in Text(verbatim: "\(AscText.value(d.type)) (\(d.shots.count))").tag(d.type) }
                            }
                        }
                    }
                    if let shown, !shown.shots.isEmpty {
                        ScrollView(.horizontal) {
                            HStack(alignment: .top, spacing: 10) {
                                ForEach(shown.shots, id: \.self) { s in
                                    Button { preview = s.large } label: {
                                        AsyncImage(url: s.url) { phase in
                                            if let image = phase.image { image.resizable().scaledToFit() } else { RoundedRectangle(cornerRadius: 8).fill(.quaternary) }
                                        }
                                        .frame(width: 240 * min(s.ratio, 1.6), height: 240)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .frame(height: 250)
                    } else {
                        Text(L.t("asc.visuals.empty")).foregroundStyle(.secondary).font(.callout)
                    }
                    AscLoad(args: ["video-previews", "list", "--version-localization", current.localizationID]) { doc, _ in
                        let previews = Self.previews(doc)
                        if !previews.isEmpty {
                            SectionTitle(L.t("asc.visuals.previews"))
                            FlowLayout(spacing: 8) {
                                ForEach(previews, id: \.self) { p in StatusPill(text: Text(verbatim: "\(AscText.value(p.type)): \(p.count)"), color: p.count > 0 ? .green : .secondary) }
                            }
                        }
                    }
                    .id(current.localizationID)
                }
                .vitrinCard(padding: 14)
            }
        }
        .sheet(item: Binding(get: { preview.map { Identified(url: $0) } }, set: { preview = $0?.url })) { p in
            VStack(spacing: 0) {
                AsyncImage(url: p.url) { phase in
                    if let image = phase.image { image.resizable().scaledToFit() } else { ProgressView() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack { Spacer(); Button(L.t("common.close")) { preview = nil } }.padding(10)
            }
        }
    }

    struct Identified: Identifiable { var url: URL; var id: String { url.absoluteString } }
    struct PreviewSet: Hashable { var type: String; var count: Int }

    /// asc's shape: localizations[] = { locale, versionLocalizationId, sets[] = { set.attributes.screenshotDisplayType, screenshots[] } }.
    nonisolated static func languages(_ doc: VitrinJSON) -> [Language] {
        (doc.objectValue?["localizations"]?.arrayValue ?? []).compactMap(\.objectValue).map { l in
            let devices = (l["sets"]?.arrayValue ?? []).compactMap(\.objectValue).compactMap { s -> (type: String, shots: [Shot])? in
                guard let type = s["set"]?.objectValue?["attributes"]?.objectValue?["screenshotDisplayType"]?.stringValue else { return nil }
                let shots = (s["screenshots"]?.arrayValue ?? []).compactMap { shot -> Shot? in
                    guard let image = shot.objectValue?["attributes"]?.objectValue?["imageAsset"]?.objectValue, let template = image["templateUrl"]?.stringValue,
                          let small = AppIconStore.url(template: template, size: 240), let large = AppIconStore.url(template: template, size: 700) else { return nil }
                    let w = image["width"]?.numberValue ?? 1, h = image["height"]?.numberValue ?? 1
                    return Shot(url: small, large: large, ratio: CGFloat(w / max(h, 1)))
                }
                return (type, shots)
            }
            return Language(locale: l["locale"]?.stringValue ?? "", localizationID: l["versionLocalizationId"]?.stringValue ?? "", devices: devices)
        }
        .sorted { $0.locale < $1.locale }
    }

    nonisolated static func previews(_ doc: VitrinJSON) -> [PreviewSet] {
        (doc.objectValue?["sets"]?.arrayValue ?? []).compactMap(\.objectValue).compactMap { s in
            guard let type = s["set"]?.objectValue?["attributes"]?.objectValue?["previewType"]?.stringValue else { return nil }
            return PreviewSet(type: type, count: s["previews"]?.arrayValue?.count ?? 0)
        }
    }
}
