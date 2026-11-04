import SwiftUI

/// A template library on the Mac (e.g. Promo Templates): its video templates, trend ideas and the videos made from it.
struct PromoStudioLibraryView: View {
    let store: PromoStudioStore
    let libraryId: String
    @State private var generate: PromoStudioNewVideoRequest?
    @State private var newTemplate = false
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
                                generate = PromoStudioNewVideoRequest(template: PromoStudioTemplateRef(libraryId: libraryId, skill: idea.skill), prompt: idea.request)
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
                    Button {
                        newTemplate = true
                    } label: {
                        Label("New Template…", systemImage: "wand.and.stars")
                    }
                    .disabled(store.job(libraryId) != nil)
                    ForEach(PromoStudioNewVideoView.videoSkills(library)) { skill in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: "/\(skill.name)").font(.headline.monospaced())
                            Text(skill.description).font(.caption).foregroundStyle(.secondary).lineLimit(4)
                            Button("Generate…") { generate = PromoStudioNewVideoRequest(template: PromoStudioTemplateRef(libraryId: libraryId, skill: skill.name)) }
                                .buttonStyle(.promoStudioPrimary)
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
            .promoStudioScreen()
            .navigationTitle(library.name)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $generate) { request in
                PromoStudioNewVideoView(store: store, request: request) { openedPost = $0 }
            }
            .sheet(isPresented: $newTemplate) { PromoStudioNewTemplateView(store: store, libraryId: libraryId) }
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
