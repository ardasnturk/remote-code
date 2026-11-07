import Foundation
import RemoteCodeKit

/// An alert from MRRadar or FunnelRadar, carried in `HostAlert.detail` as JSON (D-119).
public struct RevenueAlert: Codable, Sendable, Hashable {
    public var kind: String
    public var projectID: String
    public var projectName: String
    public var value: Double
    public var fraction: Double?
    public var currency: String?
    /// False while the MRRadar app runs and shows its own notification on this Mac.
    public var showOnMac: Bool?
    /// The plugin it came from.
    public var source: String?

    public static func decode(_ detail: String?) -> RevenueAlert? {
        detail.flatMap { try? JSONDecoder().decode(RevenueAlert.self, from: Data($0.utf8)) }
    }
}

/// Passes an extension's alerts on to the user's notifications, so they reach the phone.
actor RevenueAlertWatcher {
    private let plugin: LocalHubPlugin
    private let notifications: NotificationService
    private var task: Task<Void, Never>?

    init(plugin: LocalHubPlugin, notifications: NotificationService) {
        self.plugin = plugin
        self.notifications = notifications
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self, plugin] in
            for await event in plugin.events() where event.event == "alert" {
                await self?.handle(event.data)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    func handle(_ data: String) async {
        guard await notifications.wants(.revenueChanged), var alert = RevenueAlert.decode(data) else { return }
        let source = plugin.configuration.id
        guard await MacHostService.extensions.isEnabled(source) else { return }
        alert.source = source
        alert.showOnMac = await !plugin.isRunByApp()
        guard let encoded = try? JSONEncoder().encode(alert) else { return }
        await notifications.post(HostAlert(
            kind: .revenueChanged, sessionId: alert.projectID, folderName: alert.projectName,
            detail: String(decoding: encoded, as: UTF8.self)
        ))
    }
}
