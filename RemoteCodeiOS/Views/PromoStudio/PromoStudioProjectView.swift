import SwiftUI

/// One Promo Studio project: account, analysis, new video from a prompt, features, suggestions and posts.
struct PromoStudioProjectView: View {
    let store: PromoStudioStore
    let projectId: String
    @State private var composer: PromoStudioComposerRequest?
    @State private var openedPost: String?
    @State private var error: String?

    var body: some View {
        if let project = store.project(projectId) {
            List {
                Section {
                    HStack(spacing: 14) {
                        PromoStudioImage(store: store, path: project.logo)
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 13))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(project.name).font(.title3.bold())
                            if let tagline = project.analysis?.tagline {
                                Text(tagline).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Picker("Instagram account", selection: Binding(
                        get: { project.accountId ?? "" },
                        set: { id in run("setAccount", ["projectId": projectId, "accountId": id.isEmpty ? NSNull() : id]) }
                    )) {
                        Text("None").tag("")
                        ForEach(store.state?.accounts ?? []) { Text(verbatim: "@\($0.username)").tag($0.userId) }
                    }
                    if let job = store.job(projectId) {
                        PromoStudioJobLine(job: job)
                    }
                    Button {
                        run("analyze", ["projectId": projectId])
                    } label: {
                        if project.analysis == nil {
                            Label("Analyze Project", systemImage: "wand.and.stars")
                        } else {
                            Label("Analyze Again", systemImage: "wand.and.stars")
                        }
                    }
                    .disabled(store.job(projectId) != nil)
                }

                if let analysis = project.analysis {
                    Section {
                        Button {
                            composer = PromoStudioComposerRequest(projectId: projectId, featureId: nil)
                        } label: {
                            Label("New Video from a Prompt", systemImage: "text.bubble")
                        }
                    } footer: {
                        Text("Claude writes a storyboard, you approve or revise it, then Claude produces the video.")
                    }
                    Section("Features") {
                        ForEach(analysis.features) { feature in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: "\(feature.emoji) \(feature.name)").font(.headline)
                                Text(feature.summary).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                                HStack {
                                    Button("Quick Video") {
                                        create("createPost", ["projectId": projectId, "featureId": feature.id, "seconds": 15, "autoRender": true])
                                    }
                                    .buttonStyle(.borderedProminent)
                                    Button("Prompt…") { composer = PromoStudioComposerRequest(projectId: projectId, featureId: feature.id) }
                                        .buttonStyle(.bordered)
                                }
                                .controlSize(.small)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    Section("Ideas") {
                        ForEach(analysis.suggestions) { idea in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(idea.title).font(.headline)
                                Text(idea.angle).font(.caption).foregroundStyle(.secondary)
                                Button("Create") {
                                    create("createPost", ["projectId": projectId, "featureId": idea.featureId ?? "", "suggestionId": idea.id, "seconds": 15, "autoRender": true])
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                }

                let posts = store.posts(for: projectId)
                if !posts.isEmpty {
                    Section("Posts") {
                        ForEach(posts) { post in
                            NavigationLink(value: PromoStudioRoute.post(post.id)) {
                                PromoStudioPostRow(store: store, post: post)
                            }
                        }
                    }
                }
            }
            .navigationTitle(project.name)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $composer) { request in
                PromoStudioComposerView(store: store, request: request) { openedPost = $0 }
            }
            .navigationDestination(item: $openedPost) { PromoStudioPostView(store: store, postId: $0) }
            .alert("Promo Studio", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
        } else {
            ContentUnavailableView("Project not found", systemImage: "folder.badge.questionmark")
        }
    }

    private func run(_ action: String, _ body: [String: Any]) {
        Task {
            do { try await store.action(action, body) } catch { self.error = error.localizedDescription }
        }
    }

    private func create(_ action: String, _ body: [String: Any]) {
        Task {
            do {
                let result = try await store.action(action, body)
                openedPost = result["postId"] as? String
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

struct PromoStudioComposerRequest: Identifiable {
    let id = UUID()
    let projectId: String
    let featureId: String?
}

/// New video from the user's own prompt: a promo film directed by Claude, or a quick screenshot template.
struct PromoStudioComposerView: View {
    let store: PromoStudioStore
    let request: PromoStudioComposerRequest
    var onCreated: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var prompt = ""
    @State private var directed = true
    @State private var research = true
    @State private var voiceover = true
    @State private var seconds = 20
    @State private var language = "tr"
    @State private var featureId = ""
    @State private var sending = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. The derby is tonight. Make an energetic promo with a countdown and the AI prediction.", text: $prompt, axis: .vertical)
                        .lineLimit(4...10)
                } header: {
                    Text("What should the video be about?")
                }
                Section {
                    Picker("Type", selection: $directed) {
                        Text("Promo film (directed by Claude)").tag(true)
                        Text("Quick template (screenshots)").tag(false)
                    }
                    Toggle("Research on the web", isOn: $research)
                    if let features = store.project(request.projectId)?.analysis?.features {
                        Picker("Feature", selection: $featureId) {
                            Text("Claude chooses").tag("")
                            ForEach(features) { Text(verbatim: "\($0.emoji) \($0.name)").tag($0.id) }
                        }
                    }
                    Picker("Language", selection: $language) {
                        ForEach(store.state?.languages ?? []) { Text($0.label).tag($0.id) }
                    }
                    Stepper(value: $seconds, in: 8...60) {
                        Text("Length: \(seconds) s")
                    }
                    if directed {
                        Toggle("Voiceover", isOn: $voiceover)
                    }
                } footer: {
                    if directed {
                        Text("Claude first writes a scene-by-scene storyboard. Nothing is rendered until you approve it.")
                    }
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle(Text("New Video"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }
                        .disabled(sending || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                language = store.state?.settings.contentLanguage ?? "tr"
                voiceover = store.state?.settings.voiceoverEnabled ?? true
                featureId = request.featureId ?? ""
            }
        }
    }

    private func create() {
        sending = true
        var body: [String: Any] = [
            "projectId": request.projectId, "prompt": prompt, "research": research,
            "seconds": seconds, "language": language,
        ]
        if !featureId.isEmpty { body["featureId"] = featureId }
        if directed { body["voiceover"] = voiceover }
        Task {
            do {
                let result = try await store.action(directed ? "createDirectedPost" : "createScriptPost", body)
                dismiss()
                if let id = result["postId"] as? String { onCreated(id) }
            } catch {
                self.error = error.localizedDescription
                sending = false
            }
        }
    }
}
