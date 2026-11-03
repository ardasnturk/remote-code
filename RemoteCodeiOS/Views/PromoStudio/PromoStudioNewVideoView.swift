import Photos
import PhotosUI
import SwiftUI

/// A library video template (skill) picked for a new video.
struct PromoStudioTemplateRef: Hashable {
    let libraryId: String
    let skill: String
}

struct PromoStudioNewVideoRequest: Identifiable {
    let id = UUID()
    var template: PromoStudioTemplateRef?
    var prompt = ""
}

/// New video that doesn't have to belong to a project: from a prompt (directed by Claude) or from a library template.
/// A project and an Instagram account are both optional and independent of each other.
struct PromoStudioNewVideoView: View {
    let store: PromoStudioStore
    let request: PromoStudioNewVideoRequest
    var onCreated: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var prompt = ""
    @State private var template: PromoStudioTemplateRef?
    @State private var projectId = ""
    @State private var accountId = ""
    @State private var promo = false
    @State private var language = "tr"
    @State private var seconds = 20
    @State private var voiceover = true
    @State private var research = true
    @State private var sending = false
    @State private var error: String?
    @State private var image = false
    @State private var size = "portrait"
    @State private var picked: [PhotosPickerItem] = []
    /// Images for Claude to look at and use, with a thumbnail to show here
    @State private var photos: [(id: UUID, data: Data, thumbnail: UIImage)] = []
    @State private var status: String?

    var body: some View {
        let skill = template.flatMap { t in store.library(t.libraryId)?.skills.first { $0.name == t.skill } }
        let project = store.project(projectId.isEmpty ? nil : projectId)
        NavigationStack {
            Form {
                Section {
                    Picker("Make", selection: $image) {
                        Text("Video").tag(false)
                        Text("Image").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: image) { if image { template = nil } }
                }
                Section {
                    TextField(skill?.argumentHint.flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: "e.g. Tonight’s derby in 20 seconds: the key stats, the lineups and a prediction."), text: $prompt, axis: .vertical)
                        .lineLimit(4...10)
                    if !image {
                    Picker("Template", selection: $template) {
                        Text("None: Claude directs it from scratch").tag(PromoStudioTemplateRef?.none)
                        ForEach(store.state?.libraries ?? []) { library in
                            Section(library.name) {
                                ForEach(Self.videoSkills(library)) { s in
                                    Text(verbatim: "/\(s.name)").tag(Optional(PromoStudioTemplateRef(libraryId: library.id, skill: s.name)))
                                }
                            }
                        }
                    }
                    }
                } header: {
                    image ? Text("What should the image show?") : Text("What should the video be about?")
                } footer: {
                    if let skill {
                        Text(skill.description)
                    }
                }
                if template == nil {
                    Section {
                        if !photos.isEmpty {
                            ScrollView(.horizontal) {
                                HStack(spacing: 8) {
                                    ForEach(photos, id: \.id) { photo in
                                        Image(uiImage: photo.thumbnail).resizable().scaledToFill()
                                            .frame(width: 72, height: 72)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                            .overlay(alignment: .topTrailing) {
                                                Button { photos.removeAll { $0.id == photo.id } } label: { Image(systemName: "xmark.circle.fill") }
                                                    .foregroundStyle(.white, .black.opacity(0.6)).padding(3)
                                            }
                                    }
                                }
                            }
                        }
                        PhotosPicker(selection: $picked, maxSelectionCount: 6, matching: .images) {
                            Label("Add Photos", systemImage: "photo.badge.plus")
                        }
                    } header: {
                        Text("Your Images")
                    } footer: {
                        Text("Optional. Claude looks at them and builds the \(image ? String(localized: "image") : String(localized: "video")) around them; people and objects in them are also cut out of their background.")
                    }
                    .onChange(of: picked) { _, items in load(items) }
                }
                Section {
                    Picker("Project", selection: $projectId) {
                        Text("None").tag("")
                        ForEach((store.state?.projects ?? []).filter { $0.analysis != nil || template != nil }) { Text($0.name).tag($0.id) }
                    }
                    Picker("Instagram account", selection: $accountId) {
                        if let a = store.account(project?.accountId) {
                            Text("Project’s account (@\(a.username))").tag("")
                        } else {
                            Text("None").tag("")
                        }
                        ForEach(store.state?.accounts ?? []) { Text(verbatim: "@\($0.username)").tag($0.userId) }
                    }
                } footer: {
                    Text("Both are optional. Without a project the video isn’t about any app; without an account you can save the video and post it yourself.")
                }
                if template == nil, image {
                    Section {
                        Picker("Size", selection: $size) {
                            Text("Portrait 4:5").tag("portrait")
                            Text("Square 1:1").tag("square")
                            Text("Story 9:16").tag("story")
                        }
                        Picker("Language", selection: $language) {
                            ForEach(store.state?.languages ?? []) { Text($0.label).tag($0.id) }
                        }
                        Toggle("Research on the web", isOn: $research)
                    } footer: {
                        Text("Claude first writes a design brief. Nothing is rendered until you approve it.")
                    }
                } else if template == nil {
                    Section {
                        if !projectId.isEmpty {
                            Picker("Type", selection: $promo) {
                                Text("Free-form video").tag(false)
                                Text("Promo film for the app").tag(true)
                            }
                        }
                        Picker("Language", selection: $language) {
                            ForEach(store.state?.languages ?? []) { Text($0.label).tag($0.id) }
                        }
                        Stepper(value: $seconds, in: 10...60) {
                            Text("Length: \(seconds) s")
                        }
                        Toggle("Voiceover", isOn: $voiceover)
                        Toggle("Research on the web", isOn: $research)
                    } footer: {
                        Text("Claude first writes a scene-by-scene storyboard. Nothing is rendered until you approve it.")
                    }
                } else {
                    Section {
                    } footer: {
                        Text("Claude Code runs the template on the Mac in the background: it writes, checks and renders the video. This may take a few minutes.")
                    }
                }
                if let status {
                    Section { Label { Text(status) } icon: { ProgressView() } }
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle(image ? Text("New Image") : Text("New Video"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }
                        .disabled(sending || (template == nil && trimmed.isEmpty && photos.isEmpty))
                }
            }
            .onAppear {
                prompt = request.prompt
                template = request.template
                language = store.state?.settings.contentLanguage ?? "tr"
                voiceover = store.state?.settings.voiceoverEnabled ?? true
            }
        }
    }

    private var trimmed: String { prompt.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Templates that make a video (an idea-research skill doesn't)
    static func videoSkills(_ library: PromoStudioLibrary) -> [PromoStudioLibrary.Skill] {
        library.skills.filter { !$0.name.contains("idea") && !$0.name.contains("fikir") }
    }

    /// Reads the picked photos (their thumbnails show in the form; the full image is sent on Create)
    private func load(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        picked = []
        Task {
            for item in items {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let thumbnail = UIImage(data: data)?.preparingThumbnail(of: CGSize(width: 200, height: 200)) else { continue }
                photos.append((UUID(), data, thumbnail))
            }
        }
    }

    private func create() {
        sending = true
        error = nil
        var body: [String: Any] = ["accountId": accountId]
        if !projectId.isEmpty { body["projectId"] = projectId }
        let action: String
        if let template {
            action = "generateFromSkill"
            body["libraryId"] = template.libraryId
            body["skill"] = template.skill
            body["request"] = trimmed
        } else {
            action = "createDirectedPost"
            body["prompt"] = trimmed
            body["research"] = research
            body["seconds"] = seconds
            body["language"] = language
            body["voiceover"] = voiceover && !image
            body["style"] = promo && !projectId.isEmpty ? "promo" : "freeform"
            if image {
                body["format"] = "image"
                body["size"] = size
            }
        }
        let uploads = template == nil ? photos.map(\.data) : []
        Task {
            do {
                // One request per photo, sent ahead of the post
                var ids: [String] = []
                for (i, data) in uploads.enumerated() {
                    status = String(localized: "Sending photo \(i + 1) of \(uploads.count)…")
                    ids.append(try await store.uploadImage(data))
                }
                status = nil
                if !ids.isEmpty { body["uploads"] = ids }
                let result = try await store.action(action, body)
                dismiss()
                if let id = result["postId"] as? String { onCreated(id) }
            } catch {
                self.error = error.localizedDescription
                status = nil
                sending = false
            }
        }
    }
}

/// A new video template for a library, described in the user's own words; Claude Code writes it on the Mac.
struct PromoStudioNewTemplateView: View {
    let store: PromoStudioStore
    let libraryId: String
    @Environment(\.dismiss) private var dismiss
    @State private var prompt = ""
    @State private var sending = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. A wordless video where colored marbles race down a spiral track; the winner’s color is a guess for the comments.", text: $prompt, axis: .vertical)
                        .lineLimit(5...12)
                } header: {
                    Text("Describe the new template")
                } footer: {
                    Text("Claude Code adds a new video template to the library on the Mac: a skill and a reference video, following the library’s rules. When it’s done, the template appears in the list. This may take several minutes.")
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle(Text("New Template"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        sending = true
                        Task {
                            do {
                                try await store.action("createTemplate", ["libraryId": libraryId, "prompt": prompt.trimmingCharacters(in: .whitespacesAndNewlines)])
                                dismiss()
                            } catch {
                                self.error = error.localizedDescription
                                sending = false
                            }
                        }
                    }
                    .disabled(sending || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

/// Downloads the post's video (or an image post's picture) from the Mac and saves it to Photos, or shares it (Files, AirDrop, other apps).
struct PromoStudioSaveVideo: View {
    let store: PromoStudioStore
    let post: PromoStudioPost
    var onError: (String) -> Void
    @State private var progress: Double?
    @State private var file: URL?
    @State private var saved = false
    /// The share sheet opens as soon as the file is downloaded (one tap)
    @State private var sharing: SharedFile?

    var body: some View {
        HStack {
            Button {
                Task { await saveToPhotos() }
            } label: {
                if let progress {
                    ProgressView(value: progress).frame(maxWidth: 120)
                } else if saved {
                    Label("Saved to Photos", systemImage: "checkmark.circle.fill")
                } else {
                    Label("Save to Photos", systemImage: "square.and.arrow.down")
                }
            }
            .buttonStyle(.bordered)
            .disabled(progress != nil)
            Spacer()
            Button {
                Task { sharing = await download().map(SharedFile.init) }
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
            .disabled(progress != nil)
        }
        .controlSize(.small)
        .sheet(item: $sharing) { shared in
            PromoStudioShareSheet(items: [shared.url]).presentationDetents([.medium, .large])
        }
        // A re-rendered video or image is a new file
        .onChange(of: post.isImage ? post.media.image : post.media.video) { file = nil; saved = false }
    }

    /// The file under a readable name (the cache file is named by a hash)
    private func download() async -> URL? {
        if let file { return file }
        guard let path = post.isImage ? post.media.image : post.media.video else { return nil }
        progress = 0
        defer { progress = nil }
        do {
            let cached = try await store.mediaFile(path) { progress = $0 }
            let name = post.title.components(separatedBy: CharacterSet(charactersIn: "/\\:?*\"<>|")).joined().trimmingCharacters(in: .whitespaces)
            let named = FileManager.default.temporaryDirectory.appendingPathComponent((name.isEmpty ? "Promo Studio" : String(name.prefix(60))) + "." + cached.pathExtension)
            try? FileManager.default.removeItem(at: named)
            try FileManager.default.copyItem(at: cached, to: named)
            file = named
            return named
        } catch {
            onError(error.localizedDescription)
            return nil
        }
    }

    private func saveToPhotos() async {
        guard let url = await download() else { return }
        guard await PHPhotoLibrary.requestAuthorization(for: .addOnly) == .authorized else {
            onError(String(localized: "Allow Remote Code to add to Photos in Settings to save videos."))
            return
        }
        do {
            try await Self.addToPhotos(url, isImage: post.isImage)
            saved = true
        } catch {
            onError(error.localizedDescription)
        }
    }

    /// Photos runs the change block on its own queue. Written inside the view, the block would be
    /// main-actor isolated and Swift's isolation check would stop the app there; here it is not.
    nonisolated private static func addToPhotos(_ url: URL, isImage: Bool) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            if isImage {
                PHAssetCreationRequest.creationRequestForAssetFromImage(atFileURL: url)
            } else {
                PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }
        }
    }
}

/// The system share sheet (Files, AirDrop, Messages, Instagram…)
struct PromoStudioShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct SharedFile: Identifiable {
    let id = UUID()
    let url: URL
}
