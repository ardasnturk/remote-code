import SwiftUI

/// The Vitrin tab: who App Store Connect runs as, the team's apps, the projects on the Mac and the team's pages.
struct VitrinHomeView: View {
    let store: VitrinStore

    var body: some View {
        @Bindable var panel = store.panel
        NavigationStack(path: $panel.path) {
            VitrinHomeList(store: store)
                .navigationDestination(for: VitrinRoute.self) { route in
                    switch route {
                    case .app(let app): AppOverviewView(app: app)
                    case .project(let project): ProjectDetailView(project: project, store: store)
                    case .team(let page): TeamView(page: page)
                    case .account: VitrinAccountView()
                    }
                }
        }
        .environment(store.panel)
        .task(id: ObjectIdentifier(store)) {
            store.panel.activate()
            if store.panel.ascApps.loadedAt == nil { await store.panel.refresh() }
        }
    }
}

private struct VitrinHomeList: View {
    let store: VitrinStore
    @Environment(AppModel.self) private var remote
    @Environment(VitrinPanelModel.self) private var model
    @State private var showNewApp = false
    @State private var showFolderPicker = false
    @State private var projectError: String?
    @State private var installError: String?

    var body: some View {
        List {
            if let error = store.loadError { problem(error) }
            connectionSection
            projectsSection
            appsSection
            teamSection
        }
        .brandWindowBackground()
        .navigationTitle(Text(verbatim: "Vitrin"))
        .refreshable { await reload() }
        .sheet(isPresented: $showNewApp) {
            NewAppSheet { showNewApp = false }
        }
        .sheet(isPresented: $showFolderPicker) {
            if let mac = remote.connection {
                VitrinFolderPicker(connection: mac) { path in Task { await add(path) } }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("vitrin.home")
    }

    private func reload() async {
        await store.refresh()
        await model.refresh()
    }

    /// The hub could not be read. A hub older than the Mac's plugin wants goes away with the latest Vitrin.
    @ViewBuilder private func problem(_ error: String) -> some View {
        Section {
            Label(error, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange)
            Button(L.t("common.retry")) { Task { await reload() } }
            if store.hub == nil, error.lowercased().contains("version") {
                if store.isInstalling {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(L.t("vitrin.updating"))
                    }
                } else {
                    Button(L.t("vitrin.updateVitrin")) { Task { await install() } }
                }
                if let installError { Text(installError).font(.footnote).foregroundStyle(.red) }
            }
        }
    }

    private func install() async {
        do {
            installError = nil
            try await store.install()
        } catch {
            installError = error.localizedDescription
        }
    }

    // MARK: Connection

    private var connectionSection: some View {
        Section {
            NavigationLink(value: VitrinRoute.account) {
                HStack(spacing: 12) {
                    VitrinBadge(symbol: "key.horizontal.fill", colors: model.connection.isConnected ? BadgeColors.fresh : BadgeColors.gray, size: 32)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(connectionTitle).lineLimit(1)
                        if let connectionDetail {
                            Text(connectionDetail).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                    }
                }
            }
            .accessibilityIdentifier("vitrin.account")
        }
    }

    private var connectionTitle: String {
        switch model.connection.state {
        case .unknown: L.t("asc.loading")
        case .missingCLI: L.t("asc.missing")
        case .vitrinKey, .ascLogin: L.t("account.connected")
        case .none: L.t("account.none")
        }
    }

    /// As in the Mac's sidebar: the key, the asc login, or what to do.
    private var connectionDetail: String? {
        switch model.connection.state {
        case .vitrinKey(let id): id
        case .ascLogin(let name, let id): "asc · \(name) · \(id)"
        case .none, .missingCLI: L.t("account.add")
        case .unknown: nil
        }
    }

    // MARK: Apps

    private var appsSection: some View {
        Section {
            let list = model.ascApps
            if list.loading && list.apps.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(L.t("asc.loading")).foregroundStyle(.secondary)
                }
            } else if let error = list.error {
                Label(error, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange)
            } else if list.apps.isEmpty, model.connection.isConnected {
                Text(L.t("asc.empty")).foregroundStyle(.secondary)
            }
            ForEach(list.apps) { app in
                NavigationLink(value: VitrinRoute.app(app)) {
                    AppRow(app: app, linked: model.linkedProject(for: app))
                }
            }
        } header: {
            header(L.t("vitrin.apps"), identifier: "vitrin.apps", action: L.t("newapp.title"), actionIdentifier: "vitrin.newApp") { showNewApp = true }
        }
    }

    // MARK: Projects

    private var projectsSection: some View {
        Section {
            if store.projects.isEmpty {
                Text(L.t("vitrin.noProjects")).foregroundStyle(.secondary)
            }
            ForEach(store.projects) { project in
                Group {
                    if project.exists {
                        NavigationLink(value: VitrinRoute.project(project)) { row(project) }
                    } else {
                        row(project)
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button(L.t("vitrin.removeProject"), role: .destructive) { Task { await remove(project) } }
                }
            }
            if let projectError {
                Text(projectError).font(.footnote).foregroundStyle(.red)
            }
        } header: {
            header(L.t("vitrin.projects"), identifier: "vitrin.projects", action: L.t("vitrin.addProject"), actionIdentifier: "vitrin.addProject") { showFolderPicker = true }
        }
    }

    private func row(_ project: VitrinProject) -> some View {
        HStack(spacing: 12) {
            VitrinBadge(symbol: project.exists ? "folder.fill" : "questionmark.folder.fill", colors: project.exists ? BadgeColors.warm : BadgeColors.gray, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(project.name).lineLimit(1)
                if project.exists {
                    Text(project.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                } else {
                    Text(L.t("vitrin.folderMissing")).font(.caption).foregroundStyle(.orange).lineLimit(1)
                }
            }
        }
        .accessibilityIdentifier("vitrin.project.\(project.id)")
    }

    private func add(_ path: String) async {
        do {
            projectError = nil
            try await store.addProject(path: path)
        } catch {
            projectError = error.localizedDescription
        }
    }

    private func remove(_ project: VitrinProject) async {
        do {
            projectError = nil
            try await store.removeProject(project)
        } catch {
            projectError = error.localizedDescription
        }
    }

    // MARK: Team

    private var teamSection: some View {
        Section {
            ForEach(TeamPage.allCases) { page in
                NavigationLink(value: VitrinRoute.team(page)) {
                    HStack(spacing: 12) {
                        VitrinBadge(symbol: page.symbol, colors: page.colors, size: 28)
                        Text(L.t(page.titleKey))
                    }
                }
                .accessibilityIdentifier("vitrin.team.\(page.rawValue)")
            }
        } header: {
            Text(L.t("vitrin.team"))
        }
    }

    private func header(_ title: String, identifier: String, action: String, actionIdentifier: String, perform: @escaping () -> Void) -> some View {
        HStack {
            Text(title).accessibilityIdentifier(identifier)
            Spacer()
            Button(action: perform) {
                Image(systemName: "plus.circle.fill").font(.title3).symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(action)
            .accessibilityIdentifier(actionIdentifier)
        }
    }
}
