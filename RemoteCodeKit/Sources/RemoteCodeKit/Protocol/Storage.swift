import Foundation

// Storage and cleanup (capability `storage`, D-115).
//
// The Mac finds files that are safe to delete (caches, logs, build artefacts,
// package caches, …) and the phone chooses what goes. The phone never sends a
// path: it only names items and categories of the Mac's latest scan.

/// Free and total space of the Mac's startup volume.
public struct StorageOverview: Sendable, Hashable, Codable {
    public var totalBytes: Int64
    /// Space available for important files (what Finder shows, purgeable space included).
    public var availableBytes: Int64
    /// The Mac warns about low space below this.
    public var lowSpaceThresholdBytes: Int64

    public init(totalBytes: Int64, availableBytes: Int64, lowSpaceThresholdBytes: Int64) {
        self.totalBytes = totalBytes
        self.availableBytes = availableBytes
        self.lowSpaceThresholdBytes = lowSpaceThresholdBytes
    }

    public var usedBytes: Int64 { max(0, totalBytes - availableBytes) }
    public var isLow: Bool { availableBytes < lowSpaceThresholdBytes }
}

/// One file or folder that can be deleted.
public struct CleanupItem: Sendable, Hashable, Codable, Identifiable {
    /// Opaque, valid for the scan that produced it.
    public var id: String
    public var name: String
    /// Folder shown under the name, `~`-relative.
    public var location: String
    public var sizeBytes: Int64

    public init(id: String, name: String, location: String, sizeBytes: Int64) {
        self.id = id
        self.name = name
        self.location = location
        self.sizeBytes = sizeBytes
    }
}

/// A group of items, e.g. "App caches".
public struct CleanupCategory: Sendable, Hashable, Codable, Identifiable {
    /// Well-known ids: see `CleanupCategory.Kind`; unknown ids show `title`.
    public var id: String
    /// English fallback for clients that do not know `id`.
    public var title: String
    /// The largest items (at most `maximumItems`).
    public var items: [CleanupItem]
    /// Number of all items, also those not listed.
    public var itemCount: Int
    public var totalBytes: Int64
    public var selectedByDefault: Bool
    /// Items are always deleted for good (the Trash itself).
    public var alwaysPermanent: Bool
    /// Why the category could not be scanned (e.g. macOS privacy settings).
    public var unavailableReason: String?

    public init(
        id: String, title: String, items: [CleanupItem], itemCount: Int, totalBytes: Int64, selectedByDefault: Bool,
        alwaysPermanent: Bool = false, unavailableReason: String? = nil
    ) {
        self.id = id
        self.title = title
        self.items = items
        self.itemCount = itemCount
        self.totalBytes = totalBytes
        self.selectedByDefault = selectedByDefault
        self.alwaysPermanent = alwaysPermanent
        self.unavailableReason = unavailableReason
    }

    public static let maximumItems = 50

    public enum Kind {
        public static let caches = "caches"
        public static let logs = "logs"
        public static let xcode = "xcode"
        public static let developer = "developer"
        public static let installers = "installers"
        public static let trash = "trash"
    }
}

/// Mac → phone: response to `scanCleanup`.
public struct CleanupScan: Sendable, Hashable, Codable {
    public var scanId: String
    public var scannedAt: Date
    public var categories: [CleanupCategory]
    public var storage: StorageOverview

    public init(scanId: String, scannedAt: Date, categories: [CleanupCategory], storage: StorageOverview) {
        self.scanId = scanId
        self.scannedAt = scannedAt
        self.categories = categories
        self.storage = storage
    }
}

/// Phone → Mac: deletes items of scan `scanId`.
public struct RunCleanup: Sendable, Hashable, Codable {
    public var scanId: String
    public var itemIds: [String]
    /// Every item of these categories, also those the scan did not list.
    public var categoryIds: [String]
    /// Delete for good instead of moving to the Trash.
    public var permanently: Bool

    public init(scanId: String, itemIds: [String] = [], categoryIds: [String] = [], permanently: Bool = false) {
        self.scanId = scanId
        self.itemIds = itemIds
        self.categoryIds = categoryIds
        self.permanently = permanently
    }
}

/// Mac → phone: response to `runCleanup`.
public struct CleanupResult: Sendable, Hashable, Codable {
    public var freedBytes: Int64
    public var removedCount: Int
    /// Items in use, protected or already gone.
    public var failedCount: Int
    public var movedToTrash: Bool
    public var storage: StorageOverview

    public init(freedBytes: Int64, removedCount: Int, failedCount: Int, movedToTrash: Bool, storage: StorageOverview) {
        self.freedBytes = freedBytes
        self.removedCount = removedCount
        self.failedCount = failedCount
        self.movedToTrash = movedToTrash
        self.storage = storage
    }
}

extension ErrorCode {
    /// `runCleanup` names a scan the Mac no longer has; scan again.
    public static let scanExpired = ErrorCode("scanExpired")
    /// The host has no storage tools (e.g. a test host).
    public static let storageUnavailable = ErrorCode("storageUnavailable")
}
