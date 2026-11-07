import Foundation
import RemoteCodeHost
import UserNotifications

/// Localised notification text (docs/DECISIONS.md D-095).
enum AlertText {
    /// The one-line headline and the optional detail line.
    static func parts(of alert: HostAlert, includeDetail: Bool) -> (headline: String, detail: String?) {
        let folder = alert.folderName
        let headline = switch alert.kind {
        case .turnFinished: String(localized: "Task finished · \(folder)")
        case .permissionRequested: String(localized: "Approval needed · \(folder)")
        case .sessionFailed: String(localized: "Session failed · \(folder)")
        case .subagentFinished: String(localized: "Sub-agent finished · \(folder)")
        case .promoVideoReady: String(localized: "Video ready · \(folder)")
        case .promoImageReady: String(localized: "Image ready · \(folder)")
        case .promoStoryboardReady: String(localized: "Storyboard ready · \(folder)")
        case .promoFailed: String(localized: "Video failed · \(folder)")
        case .promoPublished: String(localized: "Posted to Instagram · \(folder)")
        case .lowDiskSpace: String(localized: "Low disk space · \(folder) free")
        case .memoryPressure: String(localized: "Memory almost full · \(folder)")
        case .appStateChanged: reviewHeadline(alert)
        case .revenueChanged: revenueHeadline(alert)
        }
        // For these kinds `detail` isn't text for the reader.
        guard includeDetail, alert.kind != .appStateChanged, alert.kind != .revenueChanged, let detail = alert.detail else { return (headline, nil) }
        if alert.kind == .permissionRequested {
            return (headline, String(localized: "Claude wants to use \(detail)"))
        }
        return (headline, detail)
    }

    private static func reviewHeadline(_ alert: HostAlert) -> String {
        let app = alert.folderName
        return switch AppReviewStage(rawValue: alert.detail ?? "") {
        case .waitingForReview: String(localized: "Waiting for review · \(app)")
        case .inReview: String(localized: "In review · \(app)")
        case .approved: String(localized: "Approved · \(app)")
        case .live: String(localized: "On the App Store · \(app)")
        case .rejected: String(localized: "Rejected by App Review · \(app)")
        case nil: app
        }
    }

    private static func revenueHeadline(_ alert: HostAlert) -> String {
        let app = alert.folderName
        guard let revenue = RevenueAlert.decode(alert.detail) else { return app }
        return switch revenue.kind {
        case "newSubscribers": String(localized: "New subscribers · \(app)")
        case "mrrDrop": String(localized: "MRR is falling · \(app)")
        case "mrrMilestone": String(localized: "MRR milestone · \(app)")
        case "revenueSpike": String(localized: "Unusually good day · \(app)")
        case "revenueDip": String(localized: "Unusually quiet day · \(app)")
        case "refundSpike": String(localized: "Refunds are high · \(app)")
        case "churnSpike": String(localized: "Churn is up · \(app)")
        case "conversionDrop": String(localized: "Conversion is falling · \(app)")
        case "retentionDrop": String(localized: "Retention is falling · \(app)")
        case "eventSpike": String(localized: "Unusually busy day · \(app)")
        case "eventDip": String(localized: "Unusually quiet day · \(app)")
        default: app
        }
    }

    /// ntfy: the app name as title, the headline (and detail) as message.
    @Sendable static func ntfyContent(for alert: HostAlert, includeDetail: Bool) -> AlertContent {
        let (headline, detail) = parts(of: alert, includeDetail: includeDetail)
        return AlertContent(title: "Remote Code", body: AlertContent.body(headline, detail: detail))
    }
}

/// Native notifications through `UNUserNotificationCenter`.
struct MacNotificationSink: AlertSink {
    func deliver(_ alert: HostAlert, includeDetail: Bool) async throws {
        // The MRRadar app shows its own, on this Mac.
        if alert.kind == .revenueChanged, RevenueAlert.decode(alert.detail)?.showOnMac == false { return }
        let (headline, detail) = AlertText.parts(of: alert, includeDetail: includeDetail)
        let content = UNMutableNotificationContent()
        content.title = headline
        if let detail = detail.flatMap(AlertContent.shortened) {
            content.body = detail
        }
        content.sound = .default
        content.threadIdentifier = alert.sessionId
        content.userInfo = ["sessionId": alert.sessionId]
        try await deliver(content)
    }

    func deliver(_ content: UNNotificationContent) async throws {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        try await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    /// Asks once; later calls return the stored answer.
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }
}

/// Shows banners even while Remote Code is the active app (e.g. Settings is open).
final class NotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
