import Foundation
import RemoteCodeKit
import Synchronization
import Testing
@testable import RemoteCodeHost

@Suite struct CleanupTests {
    /// Records "trashed" items instead of touching the user's Trash.
    final class TrashRecorder: Sendable {
        let urls = Mutex<[URL]>([])
        func trash(_ url: URL) throws {
            urls.withLock { $0.append(url) }
            try FileManager.default.removeItem(at: url)
        }
    }

    func makeHome() throws -> TemporaryHome {
        let home = try TemporaryHome()
        try home.write("Library/Caches/com.example.big/blob", String(repeating: "x", count: 200_000))
        try home.write("Library/Caches/com.example.small/blob", "x")
        try home.write("Library/Caches/com.apple.Safari/blob", "x")
        try home.write("Library/Logs/app.log", "log")
        try home.write(".Trash/old.txt", "old")
        try home.write("Documents/keep.txt", "keep")
        return home
    }

    @Test func scanFindsSafeItemsAndSkipsAppleCaches() async throws {
        let home = try makeHome()
        defer { home.remove() }
        let service = CleanupService(homeDirectory: home.path)
        let scan = await service.scan()
        let caches = try #require(scan.categories.first { $0.id == CleanupCategory.Kind.caches })
        #expect(caches.items.map(\.name) == ["com.example.big", "com.example.small"])
        #expect(caches.items.first?.location == "~/Library/Caches")
        #expect(caches.totalBytes >= 200_000)
        #expect(scan.categories.first { $0.id == CleanupCategory.Kind.trash }?.alwaysPermanent == true)
        #expect(scan.categories.first { $0.id == CleanupCategory.Kind.xcode }?.items.isEmpty == true)
        #expect(!scan.categories.flatMap(\.items).contains { $0.name == "keep.txt" })
    }

    @Test func cleanupTrashesChosenItemsAndDeletesTrashForGood() async throws {
        let home = try makeHome()
        defer { home.remove() }
        let recorder = TrashRecorder()
        let service = CleanupService(homeDirectory: home.path) { try recorder.trash($0) }
        let scan = await service.scan()
        let small = try #require(scan.categories.flatMap(\.items).first { $0.name == "com.example.small" })
        let result = try await service.run(RunCleanup(
            scanId: scan.scanId, itemIds: [small.id], categoryIds: [CleanupCategory.Kind.logs, CleanupCategory.Kind.trash]
        ))
        #expect(result.removedCount == 3)
        #expect(result.failedCount == 0)
        #expect(result.movedToTrash)
        let fm = FileManager.default
        #expect(!fm.fileExists(atPath: home.path + "/Library/Caches/com.example.small"))
        #expect(fm.fileExists(atPath: home.path + "/Library/Caches/com.example.big"))
        #expect(!fm.fileExists(atPath: home.path + "/.Trash/old.txt"))
        #expect(fm.fileExists(atPath: home.path + "/Documents/keep.txt"))
        // The Trash itself is never moved to the Trash again.
        #expect(recorder.urls.withLock { $0.map(\.lastPathComponent).sorted() } == ["app.log", "com.example.small"])
    }

    @Test func aScanIsUsedOnlyOnce() async throws {
        let home = try makeHome()
        defer { home.remove() }
        let service = CleanupService(homeDirectory: home.path) { _ in }
        let scan = await service.scan()
        _ = try await service.run(RunCleanup(scanId: scan.scanId))
        await #expect(throws: ErrorPayload.self) {
            try await service.run(RunCleanup(scanId: scan.scanId, categoryIds: [CleanupCategory.Kind.caches]))
        }
        await #expect(throws: ErrorPayload.self) {
            try await service.run(RunCleanup(scanId: "made-up"))
        }
    }

    @Test func onlyPathsInsideHomeAreDeletable() throws {
        let home = try makeHome()
        defer { home.remove() }
        #expect(CleanupService.isDeletable(URL(fileURLWithPath: home.path + "/Library/Logs/app.log"), home: home.path))
        #expect(!CleanupService.isDeletable(URL(fileURLWithPath: home.path), home: home.path))
        #expect(!CleanupService.isDeletable(URL(fileURLWithPath: home.path + "/Library/Logs/../../../etc"), home: home.path))
        #expect(!CleanupService.isDeletable(URL(fileURLWithPath: "/etc/hosts"), home: home.path))
        #expect(!CleanupService.isDeletable(URL(fileURLWithPath: home.path + "/missing"), home: home.path))
    }

    @Test func lowSpaceWarnsOncePerDip() async {
        let hub = NotificationHub()
        let monitor = StorageMonitor(
            home: NSTemporaryDirectory(), notifications: NotificationService(hub: hub) { _, _ in AsyncStream { $0.finish() } },
            macName: { "Mac" }
        )
        func overview(_ free: Int64) -> StorageOverview {
            StorageOverview(totalBytes: 500_000_000_000, availableBytes: free, lowSpaceThresholdBytes: 10_000_000_000)
        }
        #expect(await monitor.shouldWarn(overview(50_000_000_000)) == false)
        #expect(await monitor.shouldWarn(overview(9_000_000_000)) == true)
        #expect(await monitor.shouldWarn(overview(8_000_000_000)) == false)
        #expect(await monitor.shouldWarn(overview(12_000_000_000)) == false)
        #expect(await monitor.shouldWarn(overview(9_000_000_000)) == false)
        #expect(await monitor.shouldWarn(overview(16_000_000_000)) == false)
        #expect(await monitor.shouldWarn(overview(9_000_000_000)) == true)
    }
}
