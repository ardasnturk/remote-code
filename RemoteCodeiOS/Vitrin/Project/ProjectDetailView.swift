import SwiftUI

/// A project on the phone: its pages under a row of tabs, what runs along the bottom, Claude and the log in sheets.
/// Everything here is drawn by the app; the Studio on the Mac is only the API behind it.
struct ProjectDetailView: View {
    let project: VitrinProject
    let store: VitrinStore
    @Environment(VitrinPanelModel.self) private var model

    private var session: ProjectSession { store.session(for: project) }

    var body: some View {
        @Bindable var session = session
        ProjectContent(session: session)
            .brandWindowBackground()
            .navigationTitle(Text(verbatim: session.overview?.app?.name ?? project.name))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { session.showLog = true } label: { Image(systemName: "terminal") }
                        .accessibilityLabel(L.t("log.toggle")).accessibilityIdentifier("project.log")
                    Button { session.showClaude = true } label: { Image(systemName: "sparkles") }
                        .accessibilityLabel(L.t("claude.toggle")).accessibilityIdentifier("project.claude")
                }
            }
            .sheet(isPresented: $session.showClaude) {
                NavigationStack { ClaudePanel(session: session) }.environment(model)
            }
            .sheet(isPresented: $session.showLog) {
                NavigationStack { LogPanel(session: session) }
            }
            .task(id: project.id) { await session.start() }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("vitrin.project")
    }
}

private struct ProjectContent: View {
    @Bindable var session: ProjectSession

    var body: some View {
        if !session.project.exists {
            EmptyHint(text: L.t("projects.missingFolder").replacingOccurrences(of: "{path}", with: session.project.path), symbol: "folder.badge.questionmark")
        } else if let o = session.overview {
            if o.initialized {
                pages(o)
            } else {
                InitOfferView(session: session)
            }
        } else if let error = session.loadError {
            StartFailedView(session: session, error: error)
        } else {
            VStack(spacing: 12) {
                ProgressView()
                Text(L.t("project.starting")).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func pages(_ o: Overview) -> some View {
        VStack(spacing: 0) {
            CapsuleTabs(items: ProjectPage.allCases, selection: $session.page, title: { L.t($0.titleKey) })
                .padding(.horizontal, 12).padding(.vertical, 8)
            page(o)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottom) { ToastStack(session: session) }
            JobBar(session: session)
        }
    }

    @ViewBuilder private func page(_ o: Overview) -> some View {
        switch session.page {
        case .flow: FlowView(session: session, overview: o)
        case .setup: SetupView(session: session, overview: o)
        case .research: ResearchView(session: session, overview: o)
        case .listing: ListingView(session: session, overview: o)
        case .screens: ScreensView(session: session, overview: o)
        case .design: DesignView(session: session, overview: o)
        case .video: VideoView(session: session, overview: o)
        case .review: ReviewView(session: session, overview: o)
        case .upload: UploadView(session: session, overview: o)
        case .asc: AscLinkView(session: session)
        }
    }
}

/// What runs now, for as long as it runs; a tap opens the log.
private struct JobBar: View {
    var session: ProjectSession

    var body: some View {
        if session.job != nil || session.claudeRunning {
            Button {
                if session.job != nil { session.showLog = true } else { session.showClaude = true }
            } label: {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(verbatim: session.job.map { L.job($0) } ?? L.t("claude.busy")).font(.callout.weight(.medium)).lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.up").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(.bar)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("project.jobBar")
        }
    }
}

/// The App Store Connect page of the app this project ships.
private struct AscLinkView: View {
    @Environment(VitrinPanelModel.self) private var model
    var session: ProjectSession

    var body: some View {
        if let app = session.overview?.app?.bundleId.flatMap({ id in model.ascApps.apps.first { $0.bundleId == id } }) {
            AppOverviewView(app: app)
        } else {
            EmptyHint(text: L.t("apps.notLinked"), symbol: "storefront")
        }
    }
}

private struct StartFailedView: View {
    var session: ProjectSession
    var error: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L.t("project.startFailed"), systemImage: "exclamationmark.triangle.fill").font(.title3).foregroundStyle(.red)
            Text(verbatim: error).font(.callout.monospaced()).textSelection(.enabled)
            Button(L.t("common.retry")) { Task { await session.retry() } }.buttonStyle(.borderedProminent)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// A folder without vitrin.config.yaml: offer `vitrin init`.
private struct InitOfferView: View {
    var session: ProjectSession
    @State private var language = "en"
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(L.t("init.title")).font(.title2.bold())
                Text(L.t("init.intro")).foregroundStyle(.secondary)
                Card {
                    Picker(L.t("init.language"), selection: $language) {
                        Text(verbatim: "English").tag("en")
                        Text(verbatim: "Türkçe").tag("tr")
                    }
                    Text(L.t("init.hint")).font(.callout).foregroundStyle(.secondary)
                    Button(L.t("init.run")) { Task { await session.run("init", args: ["language": .string(language)]) } }
                        .buttonStyle(.borderedProminent).disabled(session.isBusy).accessibilityIdentifier("project.init")
                }
                Text(verbatim: session.project.path).font(.caption.monospaced()).foregroundStyle(.tertiary)
            }
            .padding(16)
        }
    }
}
