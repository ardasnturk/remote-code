import SwiftUI

/// A template library on the Mac (e.g. Promo Templates): its video templates, trend ideas and the videos made from it.
struct PromoStudioLibraryView: View {
    let store: PromoStudioStore
    let libraryId: String
    @State private var generate: PromoStudioGenerateRequest?
    @State private var focus = ""
    @State private var openedPost: String?
    @State private var error: String?

    var body: some View {
        if let library = store.library(libraryId) {
            List {
                Section {
                    if let job = store.job(libraryId) {
                        PromoStudioJobLine(job: job)
                    }
                    TextField("Focus (optional), e.g. football, finance apps", text: $focus)
                    Button {
                        run("generateIdeas", ["libraryId": libraryId, "focus": focus])
                    } label: {
                        Label("Research Trends", systemImage: "sparkle.magnifyingglass")
                    }
                    .disabled(store.job(libraryId) != nil)
                    ForEach(library.ideas ?? []) { idea in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(idea.title).font(.headline)
                            Text(verbatim: "“\(idea.hook)”").font(.callout).foregroundStyle(.tint)
                            Text(idea.why).font(.caption).foregroundStyle(.secondary)
                            Text(verbatim: "/\(idea.skill) · \(idea.difficulty)").font(.caption2.monospaced()).foregroundStyle(.tertiary)
                            Button("Generate This") {
                                generate = PromoStudioGenerateRequest(skill: idea.skill, request: idea.request)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("Find Ideas")
                } footer: {
                    Text("Claude researches what's trending and suggests videos you can make with these templates.")
                }

                Section("Video Templates") {
                    ForEach(library.skills) { skill in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: "/\(skill.name)").font(.headline.monospaced())
                            Text(skill.description).font(.caption).foregroundStyle(.secondary).lineLimit(4)
                            Button("Generate…") { generate = PromoStudioGenerateRequest(skill: skill.name, request: "") }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                        }
                        .padding(.vertical, 2)
                    }
                }

                let posts = store.state?.posts.filter { $0.external?.libraryId == libraryId } ?? []
                if !posts.isEmpty {
                    Section("Generated from This Library") {
                        ForEach(posts) { post in
                            NavigationLink(value: PromoStudioRoute.post(post.id)) {
                                PromoStudioPostRow(store: store, post: post)
                            }
                        }
                    }
                }
            }
            .navigationTitle(library.name)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $generate) { request in
                PromoStudioGenerateView(store: store, library: library, request: request) { openedPost = $0 }
            }
            .navigationDestination(item: $openedPost) { PromoStudioPostView(store: store, postId: $0) }
            .alert("Promo Studio", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
        } else {
            ContentUnavailableView {
                Label("Library not found", systemImage: "square.stack.3d.up.slash")
            }
        }
    }

    private func run(_ action: String, _ body: [String: Any]) {
        Task {
            do { try await store.action(action, body) } catch { self.error = error.localizedDescription }
        }
    }
}

struct PromoStudioGenerateRequest: Identifiable {
    let id = UUID()
    let skill: String
    let request: String
}

/// Runs one of the library's video templates: Claude Code writes, checks and renders the video on the Mac.
struct PromoStudioGenerateView: View {
    let store: PromoStudioStore
    let library: PromoStudioLibrary
    let request: PromoStudioGenerateRequest
    var onCreated: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var projectId = ""
    @State private var sending = false
    @State private var error: String?

    var body: some View {
        let skill = library.skills.first { $0.name == request.skill }
        NavigationStack {
            Form {
                Section {
                    TextField(skill?.argumentHint.flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: "What should the video show?"), text: $text, axis: .vertical)
                        .lineLimit(3...8)
                } header: {
                    Text(verbatim: "/\(request.skill)")
                } footer: {
                    if let description = skill?.description { Text(description) }
                }
                Section {
                    Picker("Project", selection: $projectId) {
                        ForEach(store.state?.projects ?? []) { Text($0.name).tag($0.id) }
                    }
                } footer: {
                    Text("Claude Code runs the template on the Mac in the background: it writes, checks and renders the video. This may take a few minutes.")
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
                    Button("Generate") { create() }
                        .disabled(sending || projectId.isEmpty)
                }
            }
            .onAppear {
                text = request.request
                projectId = skill?.suggestedProjectId ?? store.state?.projects.first?.id ?? ""
            }
        }
    }

    private func create() {
        sending = true
        let body: [String: Any] = ["libraryId": library.id, "skill": request.skill, "request": text, "projectId": projectId]
        Task {
            do {
                let result = try await store.action("generateFromSkill", body)
                dismiss()
                if let id = result["postId"] as? String { onCreated(id) }
            } catch {
                self.error = error.localizedDescription
                sending = false
            }
        }
    }
}
