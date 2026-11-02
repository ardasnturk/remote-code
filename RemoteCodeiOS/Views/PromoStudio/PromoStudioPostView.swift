import AVKit
import SwiftUI

/// One Promo Studio post: video, production, storyboard, revisions, caption and sharing.
struct PromoStudioPostView: View {
    let store: PromoStudioStore
    let postId: String
    @Environment(\.dismiss) private var dismiss
    @State private var section = Section.storyboard
    @State private var error: String?
    @State private var confirmDelete = false

    enum Section: Hashable { case storyboard, revise, caption, share }

    var body: some View {
        if let post = store.post(postId) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    PromoStudioVideoPanel(store: store, post: post)
                    statusArea(post)
                    actions(post)
                    Picker("Section", selection: $section) {
                        (post.directed != nil ? Text("Storyboard") : Text("Scenes")).tag(Section.storyboard)
                        Text("Revise").tag(Section.revise)
                        Text("Caption").tag(Section.caption)
                        Text("Share").tag(Section.share)
                    }
                    .pickerStyle(.segmented)
                    switch section {
                    case .storyboard: PromoStudioStoryboardSection(post: post)
                    case .revise: PromoStudioReviseSection(store: store, post: post, onError: { error = $0 })
                    case .caption: PromoStudioCaptionSection(store: store, post: post, onError: { error = $0 })
                    case .share: PromoStudioShareSection(store: store, post: post, onError: { error = $0 })
                    }
                }
                .padding()
            }
            .navigationTitle(post.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Delete Post", systemImage: "trash", role: .destructive) { confirmDelete = true }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .confirmationDialog(Text("Delete this post?"), isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    run("deletePost", ["postId": postId]) { dismiss() }
                }
            }
            .alert("Promo Studio", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
            .onAppear { if post.directed == nil, post.brief != nil, post.media.video == nil { section = .revise } }
        } else {
            ContentUnavailableView("Post not found", systemImage: "trash")
        }
    }

    @ViewBuilder private func statusArea(_ post: PromoStudioPost) -> some View {
        HStack {
            PromoStudioStatusPill(status: post.status)
            if let project = store.project(post.projectId) {
                Text(project.name).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(verbatim: duration(post)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        if let job = store.job(postId) {
            HStack(alignment: .top) {
                PromoStudioJobLine(job: job)
                Button("Cancel") { run("cancel", ["id": postId]) }
                    .buttonStyle(.bordered).controlSize(.small)
            }
        }
        if let message = post.lastError {
            Text(message).font(.caption).foregroundStyle(.red)
        }
    }

    @ViewBuilder private func actions(_ post: PromoStudioPost) -> some View {
        let busy = store.job(postId) != nil
        if let directed = post.directed, !directed.produced {
            HStack {
                Button {
                    run("produce", ["postId": postId, "voiceover": true])
                } label: {
                    Label("Approve & Produce", systemImage: "film.stack").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button("No Voiceover") { run("produce", ["postId": postId, "voiceover": false]) }
                    .buttonStyle(.bordered)
            }
            .disabled(busy || directed.storyboard.scenes.isEmpty)
        } else if post.external == nil {
            Button {
                run("render", ["postId": postId])
            } label: {
                Group {
                    if post.media.video == nil {
                        Label("Render", systemImage: "play.rectangle")
                    } else {
                        Label("Render Again", systemImage: "play.rectangle")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(busy || !post.hasScript)
        }
    }

    private func duration(_ post: PromoStudioPost) -> String {
        let seconds = post.directed.map { $0.storyboard.scenes.reduce(0) { $0 + $1.durationSec } }
            ?? post.spec.scenes.reduce(0) { $0 + ($1.durationSec ?? 3) }
        return "~\(Int(seconds.rounded())) s"
    }

    private func run(_ action: String, _ body: [String: Any], then: (() -> Void)? = nil) {
        Task {
            do {
                try await store.action(action, body)
                then?()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

/// Cover or video player; the video is downloaded in chunks the first time it is played.
struct PromoStudioVideoPanel: View {
    let store: PromoStudioStore
    let post: PromoStudioPost
    @State private var player: AVPlayer?
    @State private var progress: Double?
    @State private var failed = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18).fill(.black)
            if let player {
                VideoPlayer(player: player)
            } else if let progress {
                VStack(spacing: 10) {
                    ProgressView(value: progress).tint(.white).frame(width: 160)
                    Text("Loading video…").font(.caption).foregroundStyle(.white.opacity(0.7))
                }
            } else if post.media.video != nil {
                PromoStudioImage(store: store, path: post.media.cover)
                Button {
                    load()
                } label: {
                    Image(systemName: "play.circle.fill").font(.system(size: 64)).foregroundStyle(.white, .black.opacity(0.4))
                }
                .accessibilityLabel(Text("Play"))
            } else {
                VStack(spacing: 8) {
                    Image(systemName: post.directed?.produced == false ? "rectangle.stack" : "film").font(.largeTitle)
                    (post.directed?.produced == false ? Text("Waiting for storyboard approval") : Text("Not rendered yet"))
                        .font(.footnote)
                }
                .foregroundStyle(.white.opacity(0.7))
            }
        }
        .aspectRatio(9 / 16, contentMode: .fit)
        .frame(maxWidth: 340)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .frame(maxWidth: .infinity)
        // A re-rendered video gets a new cover; drop the old player.
        .onChange(of: post.media.cover) { player = nil; progress = nil }
        .onChange(of: post.status) { _, status in if status == .rendering { player = nil } }
        .alert(Text("The video could not be loaded."), isPresented: $failed) { Button("OK") {} }
    }

    private func load() {
        guard let path = post.media.video else { return }
        progress = 0
        Task {
            do {
                let url = try await store.mediaFile(path) { progress = $0 }
                let player = AVPlayer(url: url)
                self.player = player
                player.play()
            } catch {
                failed = true
            }
            progress = nil
        }
    }
}

struct PromoStudioStoryboardSection: View {
    let post: PromoStudioPost

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let directed = post.directed {
                if directed.storyboard.scenes.isEmpty {
                    Text("Claude is writing the storyboard…").foregroundStyle(.secondary)
                } else {
                    DisclosureGroup {
                        Text(directed.storyboard.concept).font(.callout).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } label: {
                        Text("Concept").font(.headline)
                    }
                    ForEach(Array(directed.storyboard.scenes.enumerated()), id: \.offset) { index, scene in
                        card(index: index, duration: scene.durationSec, text: scene.text, detail: scene.visual, voiceover: scene.voiceover, sfx: scene.sfx)
                    }
                    if let summary = directed.summary {
                        Text(summary).font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                ForEach(Array(post.spec.scenes.enumerated()), id: \.offset) { index, scene in
                    card(index: index, duration: scene.durationSec ?? 3, text: scene.title, detail: scene.subtitle, voiceover: scene.voiceover, sfx: nil)
                }
            }
        }
    }

    private func card(index: Int, duration: Double, text: String, detail: String?, voiceover: String?, sfx: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Scene \(index + 1)").font(.headline)
                Text(verbatim: String(format: "%.1f s", duration)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                if let sfx {
                    Label(sfx, systemImage: "speaker.wave.2").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Text(PromoStudioPost.plain(text)).font(.body.weight(.semibold))
            if let detail, !detail.isEmpty {
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
            if let voiceover {
                Text(voiceover).font(.footnote.italic())
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct PromoStudioReviseSection: View {
    let store: PromoStudioStore
    let post: PromoStudioPost
    var onError: (String) -> Void
    @State private var instruction = ""
    @State private var renderAfter = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let brief = post.brief {
                Text("Prompt").font(.headline)
                Text(brief.prompt).font(.callout).textSelection(.enabled)
                if let findings = brief.findings {
                    Text("Research").font(.headline)
                    Text(findings).font(.footnote).textSelection(.enabled)
                    ForEach(brief.sources ?? [], id: \.self) { source in
                        if let url = URL(string: source) {
                            Link(url.host() ?? source, destination: url).font(.caption)
                        }
                    }
                }
            }
            Text("Instruction").font(.headline)
            TextField("e.g. Make the hook bolder and mention it is free in the last scene", text: $instruction, axis: .vertical)
                .lineLimit(3...8)
                .textFieldStyle(.roundedBorder)
            if post.directed?.produced != false {
                Toggle("Render afterwards", isOn: $renderAfter)
            }
            Button {
                let text = instruction
                instruction = ""
                Task {
                    do { try await store.action("revise", ["postId": post.id, "instruction": text, "renderAfter": renderAfter]) } catch { onError(error.localizedDescription) }
                }
            } label: {
                Label("Revise with Claude", systemImage: "wand.and.stars").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.job(post.id) != nil || post.isLocked || !post.hasScript || instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if post.isLocked {
                Text("Scheduled or published posts cannot be revised.").font(.caption).foregroundStyle(.secondary)
            }

            if let revisions = post.revisions, !revisions.isEmpty {
                Text("Earlier Versions").font(.headline).padding(.top, 6)
                ForEach(revisions.reversed()) { revision in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(revision.title).font(.subheadline.weight(.medium))
                            Text(revision.instruction).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            Text(revision.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Button("Restore") {
                            Task {
                                do { try await store.action("restoreRevision", ["postId": post.id, "revisionId": revision.id]) } catch { onError(error.localizedDescription) }
                            }
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                        .disabled(store.job(post.id) != nil || post.isLocked)
                    }
                }
            }
        }
    }
}

struct PromoStudioCaptionSection: View {
    let store: PromoStudioStore
    let post: PromoStudioPost
    var onError: (String) -> Void
    @State private var caption = ""
    @State private var hashtags = ""
    @State private var instruction = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Caption").font(.headline)
            TextEditor(text: $caption)
                .frame(minHeight: 180)
                .padding(6)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            Text("Hashtags").font(.headline)
            TextField("#tag", text: $hashtags, axis: .vertical).textFieldStyle(.roundedBorder)
            Button {
                let tags = hashtags.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\n" }).map { String($0) }
                Task {
                    do { try await store.action("updatePost", ["postId": post.id, "caption": caption, "hashtags": tags]) } catch { onError(error.localizedDescription) }
                }
            } label: {
                Label("Save", systemImage: "checkmark").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(caption == post.caption && hashtags == tagText(post))
            if let tip = post.postingTip {
                Label(tip, systemImage: "lightbulb").font(.footnote).foregroundStyle(.secondary)
            }
            Text("Rewrite with Claude").font(.headline).padding(.top, 6)
            TextField("Optional direction, e.g. funnier, start with a question", text: $instruction).textFieldStyle(.roundedBorder)
            Button("Rewrite") {
                Task {
                    do { try await store.action("rewriteCaption", ["postId": post.id, "instruction": instruction]) } catch { onError(error.localizedDescription) }
                }
            }
            .buttonStyle(.bordered)
            .disabled(store.job(post.id) != nil)
        }
        .onAppear(perform: load)
        .onChange(of: post.caption) { load() }
        .onChange(of: post.hashtags) { load() }
    }

    private func tagText(_ post: PromoStudioPost) -> String { post.hashtags.map { "#\($0)" }.joined(separator: " ") }

    private func load() {
        caption = post.caption
        hashtags = tagText(post)
    }
}

struct PromoStudioShareSection: View {
    let store: PromoStudioStore
    let post: PromoStudioPost
    var onError: (String) -> Void
    @State private var date = Date().addingTimeInterval(3600)
    @State private var confirmPublish = false
    @State private var pickingCover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if post.media.video != nil {
                HStack(spacing: 12) {
                    PromoStudioImage(store: store, path: post.media.cover)
                        .frame(width: 54, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Cover").font(.headline)
                        if let sec = post.coverSec {
                            Text("Frame at \(String(format: "%.1f", sec)) s").font(.caption).foregroundStyle(.secondary)
                        }
                        Button("Choose Cover…") { pickingCover = true }
                            .buttonStyle(.bordered).controlSize(.small)
                            .disabled(post.status == .published || store.job(post.id) != nil)
                    }
                }
                .sheet(isPresented: $pickingCover) {
                    PromoStudioCoverPicker(store: store, post: post, onError: onError)
                }
                Divider()
            }
            let account = store.project(post.projectId).flatMap { store.account($0.accountId) }
            if let account {
                Label {
                    Text(verbatim: "@\(account.username)")
                } icon: {
                    Image(systemName: "camera.circle")
                }
            } else {
                Label("This project has no Instagram account. Choose one on the project page.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange).font(.footnote)
            }
            let canShare = post.media.video != nil && account != nil && post.status != .published && store.job(post.id) == nil
            Button {
                confirmPublish = true
            } label: {
                Label("Post as Reel Now", systemImage: "paperplane.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canShare)
            .confirmationDialog(Text("Post this video to Instagram now?"), isPresented: $confirmPublish, titleVisibility: .visible) {
                Button("Post Now") { run("publish", ["postId": post.id]) }
            }

            DatePicker("Post at", selection: $date, in: Date()...)
            HStack {
                Button("Schedule") { run("schedule", ["postId": post.id, "at": ISO8601DateFormatter().string(from: date)]) }
                    .buttonStyle(.bordered)
                    .disabled(!canShare)
                if post.status == .scheduled {
                    Button("Unschedule") { run("unschedule", ["postId": post.id]) }
                        .buttonStyle(.bordered)
                }
            }
            if let at = post.scheduledAt, post.status == .scheduled {
                Label(at.formatted(date: .complete, time: .shortened), systemImage: "calendar.badge.clock").font(.footnote)
            }
            Text("Scheduled posts go out while Promo Studio is running on your Mac.").font(.caption).foregroundStyle(.secondary)

            if post.status == .published {
                Divider()
                if let link = post.permalink, let url = URL(string: link) {
                    Link("Open on Instagram", destination: url)
                }
                if let m = post.metrics {
                    Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 6) {
                        GridRow { metric(Text("Views"), m.views); metric(Text("Reach"), m.reach); metric(Text("Likes"), m.likes) }
                        GridRow { metric(Text("Comments"), m.comments); metric(Text("Shares"), m.shares); metric(Text("Saves"), m.saved) }
                    }
                }
                Button("Refresh Statistics") { run("refreshMetrics", [:]) }.buttonStyle(.bordered)
            }
        }
        .onAppear { if let at = post.scheduledAt { date = at } }
    }

    private func metric(_ title: Text, _ value: Int?) -> some View {
        VStack(alignment: .leading) {
            Text(value.map { $0.formatted() } ?? "–").font(.headline.monospacedDigit())
            title.font(.caption).foregroundStyle(.secondary)
        }
    }

    private func run(_ action: String, _ body: [String: Any]) {
        Task {
            do { try await store.action(action, body) } catch { onError(error.localizedDescription) }
        }
    }
}

/// Picks the cover frame from the rendered video; Promo Studio sends the same moment to Instagram.
struct PromoStudioCoverPicker: View {
    let store: PromoStudioStore
    let post: PromoStudioPost
    var onError: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var videoURL: URL?
    @State private var duration: Double = 0
    @State private var sec: Double = 0
    @State private var frame: UIImage?
    @State private var loading: Double? = 0
    @State private var saving = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14).fill(.black)
                    if let frame {
                        Image(uiImage: frame).resizable().aspectRatio(contentMode: .fit)
                    } else if let loading {
                        VStack(spacing: 10) {
                            ProgressView(value: loading).tint(.white).frame(width: 140)
                            Text("Loading video…").font(.caption).foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }
                .aspectRatio(9 / 16, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                Slider(value: $sec, in: 0...max(duration, 0.1)).disabled(duration == 0)
                Text(verbatim: String(format: "%.1f s", sec)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Text("This frame becomes the cover in Promo Studio and on Instagram.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding()
            .navigationTitle(Text("Choose Cover"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use as Cover") { save() }.disabled(duration == 0 || saving)
                }
            }
        }
        .task { await prepare() }
        .task(id: sec) { await loadFrame() }
    }

    private func prepare() async {
        guard let path = post.media.video else { return }
        do {
            let url = try await store.mediaFile(path) { loading = $0 }
            videoURL = url
            duration = (try? await AVURLAsset(url: url).load(.duration).seconds) ?? 0
            sec = min(post.coverSec ?? 1.2, duration)
            loading = nil
            await loadFrame()
        } catch {
            onError(error.localizedDescription)
            dismiss()
        }
    }

    private func loadFrame() async {
        guard let videoURL else { return }
        if let image = await Self.image(videoURL, at: sec) { frame = image }
    }

    /// The exact frame at `sec` (a generator per call: it isn't Sendable, so it can't live in view state).
    nonisolated private static func image(_ url: URL, at sec: Double) async -> UIImage? {
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        gen.appliesPreferredTrackTransform = true
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = .zero
        gen.maximumSize = CGSize(width: 540, height: 960)
        return (try? await gen.image(at: CMTime(seconds: sec, preferredTimescale: 600)).image).map(UIImage.init(cgImage:))
    }

    private func save() {
        saving = true
        Task {
            do {
                try await store.action("setCover", ["postId": post.id, "sec": sec])
                dismiss()
            } catch {
                onError(error.localizedDescription)
                saving = false
            }
        }
    }
}
