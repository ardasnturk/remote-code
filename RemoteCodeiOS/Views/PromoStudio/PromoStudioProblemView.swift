import SwiftUI

/// A failed step on a post, as Promo Studio explained it: what went wrong, the fix as a button, and the raw output.
struct PromoStudioProblemCard: View {
    let store: PromoStudioStore
    let problem: PromoStudioProblem
    let postId: String
    var onError: (String) -> Void
    @State private var showDetails = false
    @State private var showHealth = false
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(problem.title).font(.subheadline.weight(.semibold))
                    Text(problem.message).font(.footnote).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            HStack {
                if let fix = problem.fix, let label = Self.label(fix, problem) {
                    Button {
                        run(fix)
                    } label: {
                        if working { ProgressView() } else { Text(label) }
                    }
                    .buttonStyle(.promoStudioPrimary)
                    .controlSize(.small)
                    .disabled(working || store.job(postId) != nil)
                }
                if problem.details != nil {
                    Button(showDetails ? "Hide Details" : "Details") { showDetails.toggle() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            if showDetails, let details = problem.details {
                ScrollView {
                    Text(details).font(.caption2.monospaced()).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 160)
                .padding(8)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .sheet(isPresented: $showHealth) { NavigationStack { PromoStudioHealthView(store: store) } }
    }

    /// The button text; nil when the fix can only be done at the Mac (its message says what to do)
    static func label(_ fix: PromoStudioProblem.Fix, _ problem: PromoStudioProblem) -> LocalizedStringKey? {
        switch fix {
        case .retry: "Try Again"
        case .repair: "Let Claude Fix It"
        case .withoutVoiceover: "Produce Without Voiceover"
        case .reconnect: "Reconnect Account"
        case .settings: problem.isInstagram ? "Instagram Accounts" : nil
        case .setup: "Mac Status"
        }
    }

    private func run(_ fix: PromoStudioProblem.Fix) {
        switch fix {
        case .reconnect, .settings: store.accountsRequested = true
        case .setup: showHealth = true
        case .retry, .repair, .withoutVoiceover:
            working = true
            Task {
                do { try await store.fix(fix, postId: postId) } catch { onError(error.localizedDescription) }
                working = false
            }
        }
    }
}

/// The Mac's setup checklist: Claude Code, Node.js, the video engine, keys, Instagram sessions and disk space.
struct PromoStudioHealthView: View {
    let store: PromoStudioStore
    @Environment(\.dismiss) private var dismiss
    @State private var checking = false

    var body: some View {
        let items = store.state?.health ?? []
        List {
            if items.isEmpty {
                Text("Update Promo Studio on your Mac to see its status here.").foregroundStyle(.secondary)
            }
            ForEach(items) { item in
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                        if !item.detail.isEmpty {
                            Text(item.detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } icon: {
                    Self.icon(item)
                }
            }
        }
        .promoStudioScreen()
        .navigationTitle(Text("Mac Status"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    checking = true
                    Task {
                        _ = try? await store.action("checkHealth")
                        await store.refresh()
                        checking = false
                    }
                } label: {
                    if checking { ProgressView() } else { Text("Check Again") }
                }
                .disabled(checking)
            }
        }
    }

    @ViewBuilder static func icon(_ item: PromoStudioHealth) -> some View {
        switch item.status {
        case "ready": Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case "warning": Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case "missing": Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        default: Image(systemName: "circle.dashed").foregroundStyle(.secondary)
        }
    }
}
