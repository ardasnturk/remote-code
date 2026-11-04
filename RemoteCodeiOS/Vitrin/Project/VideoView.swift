// Ported from Vitrin Studio (packages/studio/src/pages/Video.tsx), one column for a phone.
import SwiftUI

/// The video plan (previews, beats, loops), the four-style comparison and the rendered App Previews.
struct VideoView: View {
    var session: ProjectSession
    var overview: Overview
    @State private var locale = ""
    @State private var file = StudioFile()
    @State private var json = false
    @State private var player: RenderedFile?

    private var bust: String { String(session.changedTick) }
    private var cfg: ProjectConfig? { overview.config }
    private var screens: [String] { cfg?.screens.map(\.id) ?? [] }
    private var firstScreen: String { screens.first ?? "" }
    private var hasBrief: Bool { overview.briefs.contains { $0.name == "video" } }
    /// Rendering needs ffmpeg; editing the plan does not.
    private var ffmpeg: Blocker? { overview.blocker("ffmpeg-missing") }
    private var previews: [[String: Any]] { file.data?.objects("previews") ?? [] }
    private var creatives: [RenderedFile] { (overview.creatives[locale] ?? []).filter(\.isVideo) }
    private var anyVideoCreatives: Bool { overview.creatives.values.contains { $0.contains(where: \.isVideo) } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(L.t("video.intro")).font(.callout).foregroundStyle(.secondary)
                if let ffmpeg { BlockerCard(blocker: ffmpeg, session: session, overview: overview) }
                actions
                remotion
                CapsuleTabs(items: cfg?.locales ?? [], selection: $locale, title: { $0 }, mono: true)
                planHeader
                plan
                Card("\(L.t("visuals.previews")) · \(locale)") { players(overview.previews[locale] ?? []) }
                Card("\(L.t("video.compareStyles")) · \(locale)") { players(overview.videoStyles[locale] ?? []) }
                if anyVideoCreatives {
                    Card(L.t("visuals.creatives")) { players(creatives) }
                }
            }
            .padding(14)
        }
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await session.refresh() }
        .onAppear { if locale.isEmpty { locale = cfg?.startLocale ?? "en-US" } }
        .studioFile(file, path: "metadata/video-plan.json", session: session)
        .sheet(item: $player) { MediaSheet(client: session.client, file: $0, bust: bust) }
    }

    private var actions: some View {
        FlowLayout(spacing: 8) {
            Button(L.t("video.render")) { Task { await session.run("video") } }
                .buttonStyle(.borderedProminent).disabled(session.isBusy || ffmpeg != nil).accessibilityIdentifier("video.render")
            Button(L.t("video.compareStyles")) { Task { await session.run("video", args: ["styles": .array(["all"]), "locales": .array([.string(locale)])]) } }
                .buttonStyle(.bordered).disabled(session.isBusy || ffmpeg != nil).accessibilityIdentifier("video.compareStyles")
            if hasBrief { ClaudeButton(session: session, overview: overview, stage: "video") }
        }
    }

    /// Remotion Studio serves on the Mac's 127.0.0.1, out of the phone's reach: its state and the switch, no link.
    @ViewBuilder private var remotion: some View {
        if session.remotion?.running == true {
            Card {
                HStack(spacing: 8) {
                    Text(verbatim: "Remotion Studio").font(.callout.weight(.medium))
                    Pill(L.t("common.running"), .accent)
                }
                Text(L.t("video.remotionOnMac")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button(L.t("video.remotionStop"), role: .destructive) { Task { await session.stopRemotion() } }
                    .buttonStyle(.bordered).controlSize(.small).accessibilityIdentifier("video.remotionStop")
            }
        } else if overview.remotion?.available == true {
            Card {
                Button(L.t("video.remotionStart")) { Task { await session.startRemotion(locale: locale) } }
                    .buttonStyle(.bordered).controlSize(.small).disabled(session.isBusy).accessibilityIdentifier("video.remotionStart")
                Text(L.t("video.remotionOnMac")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Text(L.t("video.remotionDevOnly")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var planHeader: some View {
        HStack {
            Text(L.t("visuals.previews")).font(.headline)
            Spacer()
            StudioModeToggle(json: $json)
        }
    }

    @ViewBuilder private var plan: some View {
        if file.loading {
            ProgressView().frame(maxWidth: .infinity)
        } else if file.data == nil || json {
            if !file.exists, !file.dirty {
                Card {
                    Text(L.t("video.noPlan")).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button(L.t("studio.startEmpty")) { startEmpty() }.buttonStyle(.bordered).accessibilityIdentifier("video.startEmpty")
                }
            } else {
                StudioCodeEditor(file: file, session: session, identifier: "video.save")
            }
        } else {
            ForEach(previews.indices, id: \.self) { previewCard($0) }
            if previews.count < 3 {
                Button { addPreview() } label: { Label(L.t("video.addPreview"), systemImage: "plus") }
                    .buttonStyle(.bordered).accessibilityIdentifier("video.addPreview")
            }
            StudioSaveBar(file: file, session: session, identifier: "video.save")
        }
    }

    // MARK: Editing

    private func localized(_ text: String) -> [String: Any] {
        Dictionary(uniqueKeysWithValues: (cfg?.locales ?? []).map { ($0, text) })
    }

    private func newBeat(to: Double, caption: [String: Any]) -> [String: Any] {
        ["scene": "device", "source": firstScreen, "from": 0.0, "to": to, "caption": caption, "featureIds": [String]()]
    }

    private func startEmpty() {
        let source = screens.first ?? "home"
        var beat = newBeat(to: 2.5, caption: localized("Caption"))
        beat["source"] = source
        let preview: [String: Any] = ["id": "01", "device": "iphone", "style": "showcase", "hook": localized("Hook"), "hookSource": source, "beats": [beat]]
        file.setData(["previews": [preview], "loops": [String: Any]()])
    }

    private func addPreview() {
        guard var d = file.data else { return }
        var list = previews
        list.append([
            "id": String(format: "%02d", list.count + 1), "device": "iphone", "style": "showcase", "hook": [locale: ""], "hookSource": firstScreen,
            "beats": [newBeat(to: 2.5, caption: [locale: ""])],
        ])
        d["previews"] = list
        file.setData(d)
    }

    private func setPreview(_ i: Int, _ patch: (inout [String: Any]) -> Void) {
        guard var d = file.data else { return }
        var list = d.objects("previews")
        guard list.indices.contains(i) else { return }
        patch(&list[i])
        d["previews"] = list
        file.setData(d)
    }

    private func removePreview(_ i: Int) {
        guard var d = file.data else { return }
        var list = d.objects("previews")
        list.remove(at: i)
        d["previews"] = list
        file.setData(d)
    }

    private func setBeat(_ i: Int, _ j: Int, _ patch: (inout [String: Any]) -> Void) {
        setPreview(i) { p in
            var beats = p.objects("beats")
            guard beats.indices.contains(j) else { return }
            patch(&beats[j])
            p["beats"] = beats
        }
    }

    private func previewCard(_ i: Int) -> some View {
        let p = previews[i]
        let beats = p.objects("beats")
        return Card {
            HStack {
                Text(verbatim: "\(p.str("id")) · \(p.str("device"))").font(.headline)
                Spacer()
                Button { removePreview(i) } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless).disabled(previews.count <= 1)
                    .accessibilityLabel(L.t("video.removePreview")).accessibilityIdentifier("video.removePreview.\(i)")
            }
            StudioPicker(L.t("video.device"), value: p.str("device"), options: ["iphone", "ipad", "mac", "tv", "vision"]) { v in setPreview(i) { $0["device"] = v } }
            StudioPicker(L.t("video.style"), value: p["style"] as? String ?? "showcase", options: overview.enums?.videoStyles ?? []) { v in setPreview(i) { $0["style"] = v } }
            StudioPicker(L.t("video.transition"), value: p["transition"] as? String ?? "auto", options: overview.enums?.transitions ?? []) { v in setPreview(i) { $0["transition"] = v } }
            StudioTextField(
                label: "\(L.t("video.hook")) · \(locale)",
                text: Binding(get: { previews[safe: i]?.object("hook").str(locale) ?? "" }, set: { v in setPreview(i) { p in
                    var hook = p.object("hook")
                    hook[locale] = v
                    p["hook"] = hook
                } }),
                identifier: "video.hook.\(i)"
            )
            StudioPicker(L.t("video.hookSource"), value: p.str("hookSource"), options: screens) { v in setPreview(i) { $0["hookSource"] = v } }
            VideoTimeline(preview: p, locale: locale)
            HStack {
                Text(L.t("video.beats")).font(.callout.weight(.semibold))
                Spacer()
                Button {
                    setPreview(i) { p in
                        var list = p.objects("beats")
                        list.append(newBeat(to: 2, caption: [locale: ""]))
                        p["beats"] = list
                    }
                } label: { Label(L.t("video.addBeat"), systemImage: "plus") }
                    .buttonStyle(.bordered).controlSize(.small).disabled(beats.count >= 8).accessibilityIdentifier("video.addBeat.\(i)")
            }
            Text(L.t("video.beatTimesHint")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ForEach(beats.indices, id: \.self) { beatCard(i, $0, beats[$0], count: beats.count) }
        }
    }

    private func beatCard(_ i: Int, _ j: Int, _ b: [String: Any], count: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(verbatim: "\(j + 1)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button {
                    setPreview(i) { p in
                        var list = p.objects("beats")
                        list.remove(at: j)
                        p["beats"] = list
                    }
                } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless).disabled(count <= 1)
                    .accessibilityLabel(L.t("video.removeBeat")).accessibilityIdentifier("video.removeBeat.\(i).\(j)")
            }
            StudioPicker(L.t("video.scene"), value: b["scene"] as? String ?? "device", options: overview.enums?.scenes ?? []) { v in setBeat(i, j) { $0["scene"] = v } }
            StudioTextField(
                label: "\(L.t("video.caption")) · \(locale)",
                text: Binding(get: { previews[safe: i]?.objects("beats")[safe: j]?.object("caption").str(locale) ?? "" }, set: { v in setBeat(i, j) { b in
                    var caption = b.object("caption")
                    caption[locale] = v
                    b["caption"] = caption
                } }),
                identifier: "video.caption.\(i).\(j)"
            )
            StudioPicker(L.t("video.beatScreen"), value: b.str("source"), options: screens.filter { !$0.isEmpty }, empty: L.t("video.beatSource")) { v in setBeat(i, j) { $0["source"] = v } }
            StudioField(label: L.t("video.featureIds")) {
                StudioListField(value: b.strings("featureIds"), placeholder: L.t("video.featureIdsPlaceholder")) { v in setBeat(i, j) { $0["featureIds"] = v } }
            }
            HStack(spacing: 10) {
                StudioNumberField(label: L.t("video.beatStart"), value: b.number("from") ?? 0) { v in setBeat(i, j) { $0["from"] = v } }
                StudioNumberField(label: L.t("video.beatEnd"), value: b.number("to") ?? 0) { v in setBeat(i, j) { $0["to"] = v } }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground).opacity(0.7)))
    }

    @ViewBuilder private func players(_ files: [RenderedFile]) -> some View {
        if files.isEmpty {
            Text(L.t("studio.nothingYet")).font(.callout).foregroundStyle(.secondary)
        } else {
            MediaStrip(client: session.client, files: files, bust: bust, width: 170, height: 240) { player = $0 }
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

/// The preview as it plays: the hook, each scene as long as it lasts, the closing line, and the total against 15–30 s.
private struct VideoTimeline: View {
    var preview: [String: Any]
    var locale: String

    // The renderer's fixed parts (packages/video: HOOK_SEC, OUTRO_SEC).
    private static let hookSeconds = 2.2
    private static let outroSeconds = 2.4

    private struct Part: Identifiable {
        var id: Int
        var seconds: Double
        var label: String
        var tint: Color
    }

    private var parts: [Part] {
        let hook = preview.object("hook").str(locale)
        var list = [Part(id: 0, seconds: Self.hookSeconds, label: hook.isEmpty ? L.t("video.hook") : hook, tint: VitrinBrand.coral)]
        for (n, b) in preview.objects("beats").enumerated() {
            let caption = b.object("caption").str(locale)
            list.append(Part(id: n + 1, seconds: max(0, (b.number("to") ?? 0) - (b.number("from") ?? 0)), label: caption.isEmpty ? b.str("scene") : caption, tint: VitrinBrand.indigo))
        }
        if preview["outro"] != nil { list.append(Part(id: list.count, seconds: Self.outroSeconds, label: L.t("video.outro"), tint: VitrinBrand.pink)) }
        return list
    }

    var body: some View {
        let list = parts
        let total = list.reduce(0) { $0 + $1.seconds }
        let fits = total >= 15 && total <= 30
        let line = L.t("video.timelineTotal").replacingOccurrences(of: "{total}", with: String(format: "%.1f", total))
        VStack(alignment: .leading, spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(list) { p in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: p.label).font(.caption2).lineLimit(1)
                            Text(verbatim: String(format: "%.1f", p.seconds)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 5).padding(.vertical, 4)
                        .frame(width: max(max(p.seconds, 0.3) * 26, 58), alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 4).fill(p.tint.opacity(0.18)))
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: fits ? line : "\(line) · \(L.t("video.timelineFit"))")
                .font(.caption).foregroundStyle(fits ? .secondary : Color.red).fixedSize(horizontal: false, vertical: true)
        }
    }
}
