import Foundation
import Observation

/// A screen on the Vitrin tab's navigation stack.
enum VitrinRoute: Hashable {
    case app(ASCApp)
    case project(VitrinProject)
    case team(TeamPage)
    case account
}

/// What the panel's views read: the phone's counterpart of the Mac's `AppModel` for App Store Connect. Owned by
/// `VitrinStore`, provided through `.environment`.
@MainActor @Observable final class VitrinPanelModel {
    /// The team's apps from App Store Connect.
    let ascApps = ASCAppList()
    /// Who App Store Connect requests run as (Vitrin's key, asc's own login, or nobody).
    let connection = AscConnection()
    let icons = AppIconStore()
    let credentials = ASCCredentials()
    /// The Vitrin tab's navigation stack.
    var path: [VitrinRoute] = []
    /// The tool being installed on the Mac.
    private(set) var installingTool: String?
    var installingAsc: Bool { installingTool == "asc" }
    private(set) var installError: String?

    @ObservationIgnored private(set) weak var store: VitrinStore?

    func attach(_ store: VitrinStore) {
        self.store = store
        credentials.store = store
        AscCLI.store = store
    }

    /// `AscCLI` talks to one Mac: the one whose tab is showing.
    func activate() {
        AscCLI.store = store
    }

    /// After the store read the hub: who runs App Store Connect now, and with that the app list.
    func refresh() async {
        connection.apply(store?.hub?.connection)
        await credentials.refresh()
        await ascApps.refresh(connection: connection)
        Task { await icons.load(apps: ascApps.apps) }
    }

    /// Reads the connection and the team's apps again.
    func refreshApps() async {
        await store?.refresh()
        await refresh()
    }

    /// The project on the Mac whose `vitrin.config.yaml` names the app's bundle id.
    func linkedProject(for app: ASCApp) -> VitrinProject? {
        store?.projects.first { $0.bundleId == app.bundleId }
    }

    func open(_ project: VitrinProject) {
        path.append(.project(project))
    }

    func select(app: ASCApp) {
        path.append(.app(app))
    }

    /// `/v1/tools/install`: the hub installs asc with Homebrew, which takes minutes on a fresh Mac.
    func installAsc() async {
        await install(tool: "asc")
    }

    func install(tool: String) async {
        guard let store, installingTool == nil else { return }
        installingTool = tool
        installError = nil
        defer { installingTool = nil }
        do {
            let body = try JSONSerialization.data(withJSONObject: ["tool": tool])
            try await store.call("POST", "/v1/tools/install", body: String(decoding: body, as: UTF8.self), timeout: 900)
            await refreshApps()
        } catch {
            installError = error.localizedDescription
        }
    }
}
