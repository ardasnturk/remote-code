import Foundation
import RemoteCodeKit

/// What the cleanup looks at (D-115). Every location holds files that apps
/// regenerate or that are disposable; nothing outside the home folder.
/// Adapted from Perch's `Cleaner` (MIT, see NOTICE).
struct CleanupDefinition: Sendable {
    let id: String
    let title: String
    let selectedByDefault: Bool
    let alwaysPermanent: Bool
    /// Candidate items below `home`; throws when macOS privacy settings block a folder.
    let discover: @Sendable (_ home: String) throws -> [URL]

    static let all: [CleanupDefinition] = [
        CleanupDefinition(
            id: CleanupCategory.Kind.caches, title: "App caches", selectedByDefault: true, alwaysPermanent: false
        ) { home in
            // Apple's own caches are left alone: some belong to system services.
            try children(home, "Library/Caches").filter { !$0.lastPathComponent.hasPrefix("com.apple.") && !protectedCaches.contains($0.lastPathComponent) }
        },
        CleanupDefinition(
            id: CleanupCategory.Kind.logs, title: "Logs and crash reports", selectedByDefault: true, alwaysPermanent: false
        ) { home in
            try children(home, "Library/Logs")
        },
        CleanupDefinition(
            id: CleanupCategory.Kind.xcode, title: "Xcode leftovers", selectedByDefault: true, alwaysPermanent: false
        ) { home in
            try children(home, "Library/Developer/Xcode/DerivedData")
                + children(home, "Library/Developer/Xcode/iOS DeviceSupport")
                + children(home, "Library/Developer/Xcode/watchOS DeviceSupport")
                + children(home, "Library/Developer/Xcode/UserData/Previews")
                + existing(home, ["Library/Developer/CoreSimulator/Caches"])
        },
        CleanupDefinition(
            id: CleanupCategory.Kind.developer, title: "Developer package caches", selectedByDefault: true, alwaysPermanent: false
        ) { home in
            existing(home, packageCaches)
        },
        CleanupDefinition(
            id: CleanupCategory.Kind.installers, title: "Downloaded installers", selectedByDefault: false, alwaysPermanent: false
        ) { home in
            try children(home, "Downloads").filter { ["dmg", "pkg", "mpkg", "xip"].contains($0.pathExtension.lowercased()) }
        },
        CleanupDefinition(
            id: CleanupCategory.Kind.trash, title: "Trash", selectedByDefault: false, alwaysPermanent: true
        ) { home in
            try children(home, ".Trash")
        },
    ]

    static let protectedCaches: Set<String> = ["CloudKit", "FamilyCircle", "Homebrew"]

    static let packageCaches = [
        ".npm/_cacache", ".npm/_npx", ".pnpm-store", "Library/pnpm/store", ".yarn/berry/cache", ".bun/install/cache",
        ".gradle/caches", ".gradle/wrapper/dists", ".cargo/registry/cache", ".cocoapods/repos", ".expo/native-modules-cache",
        ".m2/repository", ".cache/pip", ".cache/puppeteer", ".cache/ms-playwright", ".cache/node-gyp", ".cache/yarn",
        ".cache/typescript", ".cache/prisma", ".cache/turbo", "Library/Caches/Homebrew",
    ]

    /// Entries of `home/relative`; `[]` if it does not exist.
    static func children(_ home: String, _ relative: String) throws -> [URL] {
        let folder = URL(fileURLWithPath: home).appendingPathComponent(relative, isDirectory: true)
        do {
            return try FileManager.default.contentsOfDirectory(atPath: folder.path)
                .filter { $0 != ".DS_Store" && $0 != ".localized" }
                .map { folder.appendingPathComponent($0) }
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return []
        }
    }

    static func existing(_ home: String, _ relatives: [String]) -> [URL] {
        relatives.map { URL(fileURLWithPath: home).appendingPathComponent($0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }
}

enum DiskSize {
    /// Space actually used (allocated blocks), not the logical size. Symlinks are not followed.
    static func allocated(_ path: String) -> Int64 {
        var info = stat()
        guard lstat(path, &info) == 0 else { return 0 }
        guard (info.st_mode & S_IFMT) == S_IFDIR else { return Int64(info.st_blocks) * 512 }
        guard let cPath = strdup(path) else { return 0 }
        defer { free(cPath) }
        var arguments: [UnsafeMutablePointer<CChar>?] = [cPath, nil]
        guard let fts = fts_open(&arguments, FTS_PHYSICAL | FTS_NOCHDIR, nil) else { return 0 }
        defer { fts_close(fts) }
        var total: Int64 = 0
        while let entry = fts_read(fts) {
            let kind = Int32(entry.pointee.fts_info)
            if kind == FTS_F || kind == FTS_SL || kind == FTS_DEFAULT, let stat = entry.pointee.fts_statp {
                total += Int64(stat.pointee.st_blocks) * 512
            }
        }
        return total
    }
}

/// Free space of the volume that holds `path`.
public enum StorageProbe {
    /// Below this the Mac warns about low space.
    public static let lowSpaceThreshold: Int64 = 10 * 1_000_000_000

    public static func overview(path: String) -> StorageOverview {
        let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: [
            .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey,
        ])
        let total = Int64(values?.volumeTotalCapacity ?? 0)
        let important = values?.volumeAvailableCapacityForImportantUsage ?? 0
        let available = important > 0 ? important : Int64(values?.volumeAvailableCapacity ?? 0)
        return StorageOverview(totalBytes: total, availableBytes: available, lowSpaceThresholdBytes: lowSpaceThreshold)
    }
}
