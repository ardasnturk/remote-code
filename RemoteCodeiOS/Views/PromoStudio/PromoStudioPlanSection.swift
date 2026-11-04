import SwiftUI

/// Says how far a planned post goes on its own.
struct PromoStudioPlanFootnote: View {
    let needsAccount: Bool
    let autoPublish: Bool
    let autoApprove: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if autoApprove, autoPublish {
                Text("It runs from start to finish and posts without asking you.")
            } else if autoPublish {
                Text("It waits for your approval of the storyboard, then posts when it’s ready.")
            } else if autoApprove {
                Text("It’s made without asking you, then waits for you to post it.")
            } else {
                Text("It stops at the storyboard and waits for your approval.")
            }
            if needsAccount {
                Text("To post automatically, choose an Instagram account or a project with one.")
            }
            Text("Promo Studio has to be open and the Mac awake at that time; otherwise it starts when they are. If that’s over an hour late, it isn’t posted automatically.")
        }
    }
}

/// A planned post before its time: the request and its options can still change.
struct PromoStudioPlanSection: View {
    let store: PromoStudioStore
    let post: PromoStudioPost
    var onError: (String) -> Void
    @State private var request = ""
    @State private var date = Date()
    @State private var working = false

    private var original: String { post.brief?.prompt ?? post.external?.request ?? "" }
    private var hasAccount: Bool { store.account(for: post) != nil }

    var body: some View {
        let plan = post.plan
        VStack(alignment: .leading, spacing: 12) {
            Text("Request").font(.headline)
            TextField("Request", text: $request, axis: .vertical)
                .lineLimit(3...10)
                .textFieldStyle(.roundedBorder)
            if request != original {
                Button("Save") { update(["request": request]) }
                    .buttonStyle(.bordered).controlSize(.small)
                    .disabled(post.external == nil && request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Divider()
            DatePicker("Start at", selection: $date, in: Date()...)
                .onChange(of: date) {
                    if date != plan?.runAt { update(["runAt": ISO8601DateFormatter().string(from: date)]) }
                }
            if post.external == nil {
                Toggle(isOn: Binding(get: { plan?.autoApprove == true }, set: { update(["autoApprove": $0]) })) {
                    post.isImage ? Text("Approve the design automatically") : Text("Approve the storyboard automatically")
                }
            }
            Toggle("Post automatically when it’s ready", isOn: Binding(get: { plan?.autoPublish == true && hasAccount }, set: { update(["autoPublish": $0]) }))
                .disabled(!hasAccount)
            if plan?.autoPublish == true, hasAccount, post.canPostToFeed != false {
                Picker("Share as", selection: Binding(get: { post.placement == "story" }, set: { update(["placement": $0 ? "story" : "feed"]) })) {
                    PromoStudioShareSection.label(post, story: false).tag(false)
                    PromoStudioShareSection.label(post, story: true).tag(true)
                }
                .pickerStyle(.segmented)
            }
            PromoStudioPlanFootnote(needsAccount: !hasAccount, autoPublish: plan?.autoPublish == true, autoApprove: plan?.autoApprove == true || post.external != nil)
                .font(.footnote).foregroundStyle(.secondary)
            Button {
                working = true
                Task {
                    do { _ = try await store.action("startPlan", ["postId": post.id]) } catch { onError(error.localizedDescription) }
                    working = false
                }
            } label: {
                Label("Start Now", systemImage: "play.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.promoStudioPrimary)
            .disabled(working || store.job(post.id) != nil)
        }
        .onAppear {
            request = original
            date = plan?.runAt ?? Date()
        }
    }

    private func update(_ change: [String: Any]) {
        Task {
            do {
                _ = try await store.action("updatePlan", change.merging(["postId": post.id]) { new, _ in new })
            } catch {
                onError(error.localizedDescription)
            }
        }
    }
}
