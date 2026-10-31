import RemoteCodeKit
import SwiftUI

/// The Automat tab: projects, scheduled and recent posts of the Automat app on the Mac.
struct AutomatHomeView: View {
    let store: AutomatStore
    @State private var showAccounts = false

    var body: some View {
        NavigationStack {
            Group {
                if let state = store.state {
                    content(state)
                } else if let error = store.lastError {
                    ContentUnavailableView {
                        Label("Automat", systemImage: "sparkles.tv")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Try Again") { Task { await store.retry() } }
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(Text("Automat"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAccounts = true } label: { Image(systemName: "person.crop.circle") }
                        .accessibilityLabel(Text("Instagram Accounts"))
                }
            }
            .refreshable { await store.refresh() }
            .navigationDestination(for: AutomatRoute.self) { route in
                switch route {
                case .project(let id): AutomatProjectView(store: store, projectId: id)
                case .post(let id): AutomatPostView(store: store, postId: id)
                }
            }
            .sheet(isPresented: $showAccounts) { AutomatAccountsView(store: store) }
            .automatAlert(store)
        }
    }

    @ViewBuilder private func content(_ state: AutomatState) -> some View {
        let scheduled = state.posts.filter { $0.status == .scheduled }.sorted { ($0.scheduledAt ?? .distantFuture) < ($1.scheduledAt ?? .distantFuture) }
        let recent = state.posts.filter { $0.status != .scheduled }
        List {
            Section("Projects") {
                ForEach(state.projects) { project in
                    NavigationLink(value: AutomatRoute.project(project.id)) {
                        HStack(spacing: 12) {
                            AutomatImage(store: store, path: project.logo)
                                .frame(width: 40, height: 40)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            VStack(alignment: .leading) {
                                Text(project.name).font(.headline)
                                if let tagline = project.analysis?.tagline {
                                    Text(tagline).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                        }
                    }
                }
            }
            if !scheduled.isEmpty {
                Section("Scheduled") {
                    ForEach(scheduled) { post in postLink(post) }
                }
            }
            Section("Posts") {
                ForEach(recent) { post in postLink(post) }
            }
        }
    }

    private func postLink(_ post: AutomatPost) -> some View {
        NavigationLink(value: AutomatRoute.post(post.id)) {
            AutomatPostRow(store: store, post: post)
        }
    }
}

enum AutomatRoute: Hashable {
    case project(String)
    case post(String)
}

struct AutomatPostRow: View {
    let store: AutomatStore
    let post: AutomatPost

    var body: some View {
        HStack(spacing: 12) {
            AutomatImage(store: store, path: post.media.cover)
                .frame(width: 44, height: 78)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) {
                Text(post.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                HStack(spacing: 6) {
                    AutomatStatusPill(status: post.status)
                    if let project = store.project(post.projectId) {
                        Text(project.name).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                if let job = store.job(post.id) {
                    AutomatJobLine(job: job)
                } else if let date = post.scheduledAt, post.status == .scheduled {
                    Label(date.formatted(date: .abbreviated, time: .shortened), systemImage: "clock").font(.caption)
                }
            }
        }
    }
}

struct AutomatStatusPill: View {
    let status: AutomatPost.Status

    var body: some View {
        label
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }

    private var label: Text {
        switch status {
        case .draft: Text("Draft")
        case .rendering: Text("Rendering")
        case .ready: Text("Ready")
        case .scheduled: Text("Scheduled")
        case .publishing: Text("Publishing")
        case .published: Text("Published")
        case .failed: Text("Failed")
        }
    }

    private var color: Color {
        switch status {
        case .draft: .gray
        case .rendering, .publishing: .orange
        case .ready: .blue
        case .scheduled: .purple
        case .published: .green
        case .failed: .red
        }
    }
}

struct AutomatJobLine: View {
    let job: AutomatJob

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(job.message).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            if let progress = job.progress {
                ProgressView(value: progress).tint(.orange)
            } else {
                ProgressView().progressViewStyle(.linear)
            }
        }
    }
}

/// An image from the Automat app (logo, cover, project screenshot), loaded over the encrypted channel.
struct AutomatImage: View {
    let store: AutomatStore
    let path: String?
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "photo").foregroundStyle(.tertiary)
            }
        }
        .task(id: path) {
            guard let path, let url = try? await store.mediaFile(path) else { return }
            image = UIImage(contentsOfFile: url.path)
        }
    }
}

extension View {
    /// Shows the alerts Automat raises on the Mac (errors and notices) on the phone too.
    func automatAlert(_ store: AutomatStore) -> some View {
        alert(
            store.alert?.title ?? "",
            isPresented: Binding(get: { store.alert != nil }, set: { if !$0 { store.alert = nil } })
        ) {
            Button("OK") {
                store.alert = nil
                Task { _ = try? await store.action("dismissAlert") }
            }
        } message: {
            Text(store.alert?.message ?? "")
        }
    }
}
