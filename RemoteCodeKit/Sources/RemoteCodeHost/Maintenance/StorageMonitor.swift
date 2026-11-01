import Foundation
import RemoteCodeKit

/// Warns once when the startup volume runs low on space (D-115).
///
/// Checks every few minutes (one `statfs`, no scan). After a warning it stays
/// quiet until the free space has recovered to 1.5 × the threshold, so a Mac
/// hovering around the limit does not notify again and again.
actor StorageMonitor {
    private let home: String
    private let notifications: NotificationService
    private let macName: @Sendable () -> String
    private let interval: Duration
    private var warned = false
    private var task: Task<Void, Never>?

    init(home: String, notifications: NotificationService, macName: @escaping @Sendable () -> String, interval: Duration = .seconds(300)) {
        self.home = home
        self.notifications = notifications
        self.macName = macName
        self.interval = interval
    }

    func start() {
        guard task == nil else { return }
        // The first check waits a minute, so the app has configured the notifications by then.
        task = Task { [weak self, interval] in
            try? await Task.sleep(for: .seconds(60))
            while !Task.isCancelled {
                await self?.check()
                try? await Task.sleep(for: interval)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    func check() async {
        let overview = StorageProbe.overview(path: home)
        guard overview.totalBytes > 0, shouldWarn(overview) else { return }
        await notifications.post(HostAlert(
            kind: .lowDiskSpace,
            sessionId: "",
            folderName: ByteCountFormatter.string(fromByteCount: overview.availableBytes, countStyle: .file),
            detail: macName()
        ))
    }

    /// `true` once per dip below the threshold.
    func shouldWarn(_ overview: StorageOverview) -> Bool {
        if overview.isLow {
            guard !warned else { return false }
            warned = true
            return true
        }
        if overview.availableBytes >= overview.lowSpaceThresholdBytes * 3 / 2 { warned = false }
        return false
    }
}
