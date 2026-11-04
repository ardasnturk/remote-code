// Ported from Vitrin Studio (packages/studio/src/pages/Screens.tsx), one column for a phone.
import SwiftUI

/// The app's screens as a strip per language and device (the raw captures), the device mockups, and under Advanced the
/// HTML of each screen with its source files and strings.
struct ScreensView: View {
    var session: ProjectSession
    var overview: Overview
    @State private var locale = ""
    @State private var family: String?
    @State private var preview: RenderedFile?
    @State private var editing: StudioSheetFile?
    @State private var gallery: StudioSheetFile?
    @State private var advanced = false

    private var bust: String { String(session.changedTick) }
    private var cfg: ProjectConfig? { overview.config }
    private var raw: [String: [RenderedFile]] { overview.raw[locale] ?? [:] }
    private var families: [String] { raw.keys.sorted() }
    private var currentFamily: String? {
        if let family, families.contains(family) { return family }
        return families.contains("iphone") ? "iphone" : families.first
    }
    private var wide: Bool { ["mac", "tv", "vision"].contains(currentFamily ?? "") }
    private var hasBrief: Bool { overview.briefs.contains { $0.name == "screens" } }

    /// A screen the config names, with its capture if there is one; then captures of screens it doesn't name (a manual
    /// capture has those too).
    private struct Tile: Identifiable {
        var id: String
        var file: RenderedFile?
    }
    private var tiles: [Tile] {
        let files = currentFamily.flatMap { raw[$0] } ?? []
        let screens = cfg?.screens ?? []
        var list = screens.map { s in Tile(id: s.id, file: files.first { $0.name == "\(s.id).png" }) }
        let named = Set(list.compactMap { $0.file?.path })
        list += files.filter { !named.contains($0.path) }.map { Tile(id: $0.name, file: $0) }
        return list
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(L.t("screens.intro")).font(.callout).foregroundStyle(.secondary)
                actions
                if let cfg {
                    CapsuleTabs(items: cfg.locales, selection: $locale, title: { $0 }, mono: true)
                    if families.count > 1 {
                        CapsuleTabs(items: families, selection: Binding(get: { currentFamily ?? "" }, set: { family = $0 }), title: { $0 })
                    }
                    if tiles.isEmpty {
                        EmptyHint(text: L.t("screens.noScreens"), symbol: "camera")
                    } else {
                        strip
                        advancedSection(cfg)
                    }
                }
                mockups
            }
            .padding(14)
        }
        .refreshable { await session.refresh() }
        .onAppear { if locale.isEmpty { locale = cfg?.startLocale ?? "en-US" } }
        .sheet(item: $preview) { MediaSheet(client: session.client, file: $0, bust: bust) }
        .sheet(item: $editing) { StudioFileSheet(path: $0.path, json: $0.json, session: session) }
        .sheet(item: $gallery) { StudioDocumentSheet(client: session.client, path: $0.path, title: L.t("screens.mockups"), bust: bust) }
    }

    private var actions: some View {
        FlowLayout(spacing: 8) {
            if hasBrief { ClaudeButton(session: session, overview: overview, stage: "screens") }
            Button(L.t("screens.render")) { Task { await session.run("capture") } }
                .buttonStyle(hasBrief ? AnyButtonStyle(.bordered) : AnyButtonStyle(.borderedProminent))
                .disabled(session.isBusy).accessibilityIdentifier("screens.render")
            Button(L.t("screens.renderMockups")) { Task { await session.run("mockups", args: ["screens": true]) } }
                .buttonStyle(.bordered).disabled(session.isBusy).accessibilityIdentifier("screens.renderMockups")
            if let index = overview.mockups?.index {
                Button(L.t("screens.openMockups")) { gallery = StudioSheetFile(path: index) }
                    .buttonStyle(.bordered).accessibilityIdentifier("screens.openMockups")
            }
        }
    }

    private var strip: some View {
        let width: CGFloat = wide ? 300 : 170
        let height: CGFloat = wide ? 180 : 320
        return ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 10) {
                ForEach(tiles) { tile in
                    if let f = tile.file {
                        Button { preview = f } label: { MediaThumb(client: session.client, file: f, bust: bust, height: height).frame(width: width) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("screens.screen.\(tile.id)")
                    } else {
                        missing(tile.id, width: width, height: height)
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func missing(_ id: String, width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color(.tertiarySystemFill))
                Text(L.t("screens.notRendered")).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(8)
            }
            .frame(height: height)
            Text(verbatim: id).font(.caption).lineLimit(1).truncationMode(.middle)
        }
        .padding(6)
        .frame(width: width)
    }

    private func advancedSection(_ cfg: ProjectConfig) -> some View {
        DisclosureGroup(L.t("screens.advanced"), isExpanded: $advanced) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L.t("screens.advancedHint")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                ForEach(cfg.screens, id: \.id) { s in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: s.id).font(.callout.monospaced())
                            Text(verbatim: (s.source ?? []).isEmpty ? "—" : (s.source ?? []).joined(separator: ", "))
                                .font(.caption.monospaced()).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Button(L.t("screens.editHtml")) { editing = StudioSheetFile(path: "metadata/screens/\(s.id).html") }
                            .buttonStyle(.bordered).controlSize(.small).accessibilityIdentifier("screens.edit.\(s.id)")
                    }
                    Divider()
                }
                Text(L.t("screens.strings")).font(.caption).foregroundStyle(.secondary)
                FlowLayout(spacing: 6) {
                    ForEach(cfg.locales, id: \.self) { l in
                        Button(l) { editing = StudioSheetFile(path: "metadata/screens/strings/\(l).json", json: true) }
                            .buttonStyle(.bordered).controlSize(.small).font(.caption.monospaced()).accessibilityIdentifier("screens.strings.\(l)")
                    }
                }
            }
            .padding(.top, 8)
        }
        .font(.callout.weight(.medium))
        .accessibilityIdentifier("screens.advanced")
    }

    @ViewBuilder private var mockups: some View {
        if let files = overview.mockups?.screens, !files.isEmpty {
            Card(L.t("visuals.mockups")) {
                MediaStrip(client: session.client, files: files, bust: bust, width: 220, height: 220) { preview = $0 }
            }
        }
    }
}
