import SwiftUI

/// Everything that would be uploaded, grouped as `metadata/report.html` groups it (store → platform → language), with
/// approve and reject. The Mac shows that page; here the same items are drawn by the app from `/api/review`.
struct ReviewView: View {
    var session: ProjectSession
    var overview: Overview
    @State private var review: ReviewState?
    @State private var loading = false
    @State private var confirmApprove = false
    @State private var showReject = false
    @State private var preview: RenderedFile?

    private var invalid: Bool { overview.validation.map { !$0.ok } ?? false }

    private struct Group: Identifiable {
        var title: String
        var items: [ReviewItem]
        var id: String { title }
    }

    private var groups: [Group] {
        var order: [String] = []
        var byTitle: [String: [ReviewItem]] = [:]
        for item in review?.items ?? [] {
            let title = [item.platform, item.locale].compactMap { $0 }.joined(separator: " · ")
            if byTitle[title] == nil { order.append(title) }
            byTitle[title, default: []].append(item)
        }
        return order.map { Group(title: $0, items: byTitle[$0] ?? []) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(L.t("review.intro")).font(.callout).foregroundStyle(.secondary)
                status
                FlowLayout(spacing: 8) {
                    Button(L.t("review.approveAll")) { confirmApprove = true }
                        .buttonStyle(.borderedProminent)
                        .disabled(session.isBusy || loading || review == nil || review?.approval.ok == true || invalid)
                        .accessibilityIdentifier("review.approveAll")
                    Button(L.t("review.reject")) { showReject = true }
                        .buttonStyle(.bordered).disabled(session.isBusy || review == nil).accessibilityIdentifier("review.reject")
                    Button(L.stage("validate")) { Task { await session.run("validate") } }
                        .buttonStyle(.bordered).disabled(session.isBusy)
                    Button(L.t("review.rebuild")) { Task { await load() } }
                        .buttonStyle(.bordered).disabled(session.isBusy || loading)
                }
                if invalid, review?.approval.ok != true { Text(L.t("review.needsValid")).font(.callout).foregroundStyle(.secondary) }
                if let r = review, !r.summary.isEmpty {
                    FlowLayout(spacing: 4) { ForEach(r.summary, id: \.self) { Pill($0) } }
                }
                if review != nil, groups.isEmpty { EmptyHint(text: L.t("review.noReport"), symbol: "checklist") }
                ForEach(groups) { group in
                    Card(group.title) { groupContent(group) }
                }
            }
            .padding(14)
        }
        .refreshable { await load() }
        .task(id: "\(session.changedTick)-\(session.finishedJob?.id ?? "")") { if session.job == nil { await load() } }
        .confirmationDialog(L.t("review.approveAll"), isPresented: $confirmApprove, titleVisibility: .visible) {
            Button(L.t("review.approveConfirm", review?.items.count ?? 0)) { Task { await approve() } }
            Button(L.t("common.cancel"), role: .cancel) {}
        } message: {
            Text(verbatim: L.t("review.approveMessage") + "\n" + (review?.summary.joined(separator: "\n") ?? "") + "\n" + (review?.overallHash ?? ""))
        }
        .sheet(isPresented: $showReject) {
            if let r = review { RejectSheet(review: r, session: session) { showReject = false; Task { await load() } } }
        }
        .sheet(item: $preview) { MediaSheet(client: session.client, file: $0) }
    }

    @ViewBuilder private var status: some View {
        FlowLayout(spacing: 6) {
            if loading { ProgressView().controlSize(.small) }
            if let r = review {
                if r.approval.ok, let a = overview.approval, a.valid {
                    Pill("\(L.t("review.approved")) · \(L.date(a.approvedAt))", .ok)
                } else if r.approval.ok, let a = overview.approval {
                    Pill(L.t("review.approvalInvalid").replacingOccurrences(of: "{reason}", with: L.reason(StageView(id: "review", status: "blocked", reason: a.problem), overview)), .err)
                } else {
                    Pill(r.approval.reason ?? L.t("review.notApproved"), .warn)
                }
                Text(verbatim: "\(L.t("review.items", r.items.count)) · \(L.t("review.hash")) \(r.overallHash.prefix(12))").font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            if let v = overview.validation { Pill(v.ok ? L.t("review.validationOk") : L.t("review.validationErrors", v.counts.error), v.ok ? .ok : .err) }
            if let a = overview.approval, a.rejections > 0 { Pill(L.t("review.rejections", a.rejections), .warn) }
        }
    }

    @ViewBuilder private func groupContent(_ group: Group) -> some View {
        let media = group.items.filter { $0.media != nil }
        ForEach(group.items.filter { $0.media == nil }) { item in
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: item.label).font(.callout.weight(.medium))
                ForEach(item.fields ?? [], id: \.key) { field in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: field.key).font(.caption).foregroundStyle(.secondary)
                        Text(verbatim: field.value).font(.callout).textSelection(.enabled)
                    }
                }
            }
        }
        if !media.isEmpty {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104, maximum: 180), spacing: 8)], spacing: 8) {
                ForEach(media) { item in
                    if let file = item.media {
                        Button { preview = file } label: {
                            VStack(spacing: 3) {
                                MediaThumb(client: session.client, file: file, height: 170)
                                Text(verbatim: item.target ?? item.label).font(.caption2).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.center)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            review = try await session.client.review()
        } catch {
            session.report(error)
        }
    }

    private func approve() async {
        guard let r = review else { return }
        do {
            try await session.client.approve(overallHash: r.overallHash)
            session.toast(L.t("review.approved"), .ok)
        } catch {
            session.report(error)
        }
        await load()
        await session.refresh()
    }
}

/// Reject items with a comment each; Claude reads them from metadata/review-feedback.json.
struct RejectSheet: View {
    var review: ReviewState
    var session: ProjectSession
    var done: () -> Void
    @State private var selected: Set<String> = []
    @State private var comment = ""
    @State private var sending = false

    var body: some View {
        NavigationStack {
            List {
                Section { Text(L.t("review.rejectIntro")).font(.callout).foregroundStyle(.secondary) }
                Section {
                    ForEach(review.items) { item in
                        Button {
                            if selected.contains(item.id) { selected.remove(item.id) } else { selected.insert(item.id) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(verbatim: item.label).foregroundStyle(.primary)
                                    Text(verbatim: [item.kind, item.locale, item.target].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if selected.contains(item.id) { Image(systemName: "checkmark").foregroundStyle(.tint) }
                            }
                        }
                    }
                }
                Section {
                    TextField(L.t("review.comment"), text: $comment, axis: .vertical).lineLimit(2...5).accessibilityIdentifier("review.comment")
                } footer: {
                    Text(L.t("review.selected", selected.count))
                }
            }
            .navigationTitle(L.t("review.reject"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L.t("common.cancel")) { done() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.t("review.sendRejections")) { Task { await send() } }
                        .disabled(sending || selected.isEmpty || comment.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func send() async {
        sending = true
        defer { sending = false }
        do {
            let n = try await session.client.reject(overallHash: review.overallHash, rejections: selected.sorted().map { StudioClient.Rejection(item: $0, comment: comment.trimmingCharacters(in: .whitespaces)) })
            session.toast(L.t("review.rejectionsSent", n), .ok)
            done()
        } catch {
            session.report(error)
        }
    }
}
