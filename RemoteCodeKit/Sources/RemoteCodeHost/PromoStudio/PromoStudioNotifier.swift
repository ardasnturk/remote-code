import Foundation
import RemoteCodeKit

/// Turns Promo Studio's `finished` events into notifications (D-113), so a video
/// started from the phone is announced even when the phone app is closed.
///
/// Listens to Promo Studio's event stream for as long as Remote Code runs; the
/// bridge reconnects by itself when Promo Studio starts or restarts.
public actor PromoStudioNotifier {
    private let bridge: PromoStudioBridge
    private let notifications: NotificationService
    private var listener: Task<Void, Never>?

    public init(bridge: PromoStudioBridge, notifications: NotificationService) {
        self.bridge = bridge
        self.notifications = notifications
    }

    public func start() {
        guard listener == nil else { return }
        let stream = bridge.events()
        listener = Task { [weak self] in
            for await event in stream {
                guard let alert = Self.alert(for: event) else { continue }
                await self?.notifications.post(alert)
            }
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }

    /// The alert for a `finished` event with a `notice`; `nil` for anything else.
    static func alert(for event: PromoStudioEvent) -> HostAlert? {
        guard event.event == "finished",
              let object = (try? JSONSerialization.jsonObject(with: Data(event.data.utf8))) as? [String: Any],
              let notice = object["notice"] as? String
        else { return nil }
        let kind: HostAlert.Kind
        switch notice {
        case "videoReady": kind = .promoVideoReady
        case "storyboardReady": kind = .promoStoryboardReady
        case "failed": kind = .promoFailed
        case "published": kind = .promoPublished
        default: return nil
        }
        let id = object["postId"] as? String ?? object["id"] as? String ?? ""
        let title = (object["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Promo Studio"
        return HostAlert(kind: kind, sessionId: id, folderName: title, detail: object["error"] as? String)
    }
}
