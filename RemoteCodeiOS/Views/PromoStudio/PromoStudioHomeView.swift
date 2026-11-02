import RemoteCodeKit
import SwiftUI

/// The Promo Studio tab: projects, scheduled and recent posts of the Promo Studio app on the Mac.
struct PromoStudioHomeView: View {
    let store: PromoStudioStore
    @Environment(AppModel.self) private var model
    @State private var showAccounts = false
    @State private var newVideo: PromoStudioNewVideoRequest?
    @State private var path: [PromoStudioRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let state = store.state {
                    content(state)
                } else if let error = store.lastError {
                    ContentUnavailableView {
                        Label("Promo Studio", systemImage: "sparkles.tv")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Try Again") { Task { await store.retry() } }
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(Text("Promo Studio"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAccounts = true } label: { Image(systemName: "person.crop.circle") }
                        .accessibilityLabel(Text("Instagram Accounts"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { newVideo = PromoStudioNewVideoRequest() } label: { Image(systemName: "plus") }
                        .accessibilityLabel(Text("New Video"))
                        .disabled(store.state == nil)
                }
            }
            .refreshable { await store.refresh() }
            .navigationDestination(for: PromoStudioRoute.self) { route in
                switch route {
                case .project(let id): PromoStudioProjectView(store: store, projectId: id)
                case .library(let id): PromoStudioLibraryView(store: store, libraryId: id)
                case .post(let id): PromoStudioPostView(store: store, postId: id)
                }
            }
            .sheet(isPresented: $showAccounts) { PromoStudioAccountsView(store: store) }
            .sheet(item: $newVideo) { request in
                PromoStudioNewVideoView(store: store, request: request) { path = [.post($0)] }
            }
            // A tapped notification opens its post (D-113)
            .onChange(of: model.promoStudioPostToOpen, initial: true) { _, postId in
                guard let postId else { return }
                path = [.post(postId)]
                model.promoStudioPostToOpen = nil
            }
            .promoStudioAlert(store)
        }
    }

    @ViewBuilder private func content(_ state: PromoStudioState) -> some View {
        let scheduled = state.posts.filter { $0.status == .scheduled }.sorted { ($0.scheduledAt ?? .distantFuture) < ($1.scheduledAt ?? .distantFuture) }
        let recent = state.posts.filter { $0.status != .scheduled }
        List {
            Section("Projects") {
                ForEach(state.projects) { project in
                    NavigationLink(value: PromoStudioRoute.project(project.id)) {
                        HStack(spacing: 12) {
                            PromoStudioImage(store: store, path: project.logo)
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
            if let libraries = state.libraries, !libraries.isEmpty {
                Section {
                    ForEach(libraries) { library in
                        NavigationLink(value: PromoStudioRoute.library(library.id)) {
                            HStack(spacing: 12) {
                                Image(systemName: "square.stack.3d.up.fill")
                                    .font(.title3)
                                    .foregroundStyle(.white)
                                    .frame(width: 40, height: 40)
                                    .background(LinearGradient(colors: [.purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 10))
                                VStack(alignment: .leading) {
                                    Text(library.name).font(.headline)
                                    Text("\(library.skills.count) video templates").font(.caption).foregroundStyle(.secondary)
                                }
                                if let job = store.job(library.id) {
                                    Spacer()
                                    ProgressView().accessibilityLabel(Text(job.message))
                                }
                            }
                        }
                    }
                } header: {
                    Text("Templates")
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

    private func postLink(_ post: PromoStudioPost) -> some View {
        NavigationLink(value: PromoStudioRoute.post(post.id)) {
            PromoStudioPostRow(store: store, post: post)
        }
    }
}

enum PromoStudioRoute: Hashable {
    case project(String)
    case library(String)
    case post(String)
}

struct PromoStudioPostRow: View {
    let store: PromoStudioStore
    let post: PromoStudioPost

    var body: some View {
        HStack(spacing: 12) {
            PromoStudioImage(store: store, path: post.media.cover)
                .frame(width: 44, height: 78)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) {
                Text(post.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                HStack(spacing: 6) {
                    PromoStudioStatusPill(status: post.status)
                    if let project = store.project(post.projectId) {
                        Text(project.name).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                if let job = store.job(post.id) {
                    PromoStudioJobLine(job: job)
                } else if let date = post.scheduledAt, post.status == .scheduled {
                    Label(date.formatted(date: .abbreviated, time: .shortened), systemImage: "clock").font(.caption)
                }
            }
        }
    }
}

struct PromoStudioStatusPill: View {
    let status: PromoStudioPost.Status

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

struct PromoStudioJobLine: View {
    let job: PromoStudioJob

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(job.message).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Spacer(minLength: 6)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    if let text = job.remainingText(now: context.date) {
                        Text(text).font(.caption.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            if let progress = job.progress {
                ProgressView(value: progress).tint(.orange)
            } else {
                ProgressView().progressViewStyle(.linear)
            }
        }
    }
}

/// An image from the Promo Studio app (logo, cover, project screenshot), loaded over the encrypted channel.
struct PromoStudioImage: View {
    let store: PromoStudioStore
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
    /// Shows the alerts Promo Studio raises on the Mac (errors and notices) on the phone too.
    func promoStudioAlert(_ store: PromoStudioStore) -> some View {
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
