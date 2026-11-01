import Foundation
import RemoteCodeKit

/// Scans for files that are safe to delete and deletes what the phone picks
/// (capability `storage`, D-115).
///
/// The phone only ever names items of the latest scan; their paths stay on
/// the Mac and are checked again (inside the home folder, still there) right
/// before they are moved to the Trash or deleted.
public actor CleanupService {
    /// Moves an item to the Trash; replaceable in tests.
    public typealias Trash = @Sendable (URL) throws -> Void

    private struct Entry {
        let url: URL
        let categoryId: String
        let size: Int64
    }

    private struct Scan {
        let id: String
        let entries: [String: Entry]
        let permanentCategories: Set<String>
    }

    private let home: String
    private let definitions: [CleanupDefinition]
    private let trash: Trash
    private var latest: Scan?
    private var running: Task<CleanupScan, Never>?

    public init(homeDirectory: String, trash: @escaping Trash = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) {
        self.init(homeDirectory: homeDirectory, definitions: CleanupDefinition.all, trash: trash)
    }

    init(homeDirectory: String, definitions: [CleanupDefinition], trash: @escaping Trash) {
        home = URL(fileURLWithPath: homeDirectory).standardizedFileURL.path
        self.definitions = definitions
        self.trash = trash
    }

    public func storageOverview() -> StorageOverview {
        StorageProbe.overview(path: home)
    }

    /// Scans every category; a scan already running is joined instead of started twice.
    public func scan() async -> CleanupScan {
        if let running { return await running.value }
        let home = home
        let definitions = definitions
        let task = Task.detached(priority: .utility) { () -> (CleanupScan, Scan) in
            let scanId = UUID().uuidString
            var entries: [String: Entry] = [:]
            var categories: [CleanupCategory] = []
            await withTaskGroup(of: (Int, CleanupCategory, [String: Entry]).self) { group in
                for (index, definition) in definitions.enumerated() {
                    group.addTask {
                        let (category, entries) = Self.scan(definition, home: home)
                        return (index, category, entries)
                    }
                }
                var results: [(Int, CleanupCategory)] = []
                for await (index, category, found) in group {
                    results.append((index, category))
                    entries.merge(found) { first, _ in first }
                }
                categories = results.sorted { $0.0 < $1.0 }.map(\.1)
            }
            let permanent = Set(definitions.filter(\.alwaysPermanent).map(\.id))
            let result = CleanupScan(scanId: scanId, scannedAt: Date(), categories: categories, storage: StorageProbe.overview(path: home))
            return (result, Scan(id: scanId, entries: entries, permanentCategories: permanent))
        }
        running = Task { await task.value.0 }
        let (result, scan) = await task.value
        latest = scan
        running = nil
        return result
    }

    /// Deletes the chosen items; the scan is used up afterwards (sizes changed).
    public func run(_ request: RunCleanup) async throws -> CleanupResult {
        guard let scan = latest, scan.id == request.scanId else {
            throw ErrorPayload(code: .scanExpired, message: "The list is out of date. Scan again.")
        }
        latest = nil
        let categories = Set(request.categoryIds)
        var chosen = request.itemIds.compactMap { scan.entries[$0] }
        chosen += scan.entries.values.filter { categories.contains($0.categoryId) }
        var seen = Set<String>()
        chosen = chosen.filter { seen.insert($0.url.path).inserted }

        let home = home
        let trash = trash
        let permanently = request.permanently
        let (freed, removed, failed) = await Task.detached(priority: .userInitiated) { () -> (Int64, Int, Int) in
            var freed: Int64 = 0
            var removed = 0
            var failed = 0
            for entry in chosen {
                guard Self.isDeletable(entry.url, home: home) else {
                    failed += 1
                    continue
                }
                do {
                    if permanently || scan.permanentCategories.contains(entry.categoryId) {
                        try FileManager.default.removeItem(at: entry.url)
                    } else {
                        try trash(entry.url)
                    }
                    freed += entry.size
                    removed += 1
                } catch {
                    failed += 1
                }
            }
            return (freed, removed, failed)
        }.value
        return CleanupResult(
            freedBytes: freed, removedCount: removed, failedCount: failed, movedToTrash: !permanently,
            storage: StorageProbe.overview(path: home)
        )
    }

    private static func scan(_ definition: CleanupDefinition, home: String) -> (CleanupCategory, [String: Entry]) {
        let urls: [URL]
        var unavailable: String?
        do {
            urls = try definition.discover(home)
        } catch {
            urls = []
            unavailable = "macOS blocked access to this folder. On your Mac open System Settings → Privacy & Security → Full Disk Access and turn on Remote Code."
        }
        let sized = urls.map { ($0, DiskSize.allocated($0.path)) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
        var entries: [String: Entry] = [:]
        var items: [CleanupItem] = []
        for (url, size) in sized {
            let id = UUID().uuidString
            entries[id] = Entry(url: url, categoryId: definition.id, size: size)
            if items.count < CleanupCategory.maximumItems {
                items.append(CleanupItem(
                    id: id, name: url.lastPathComponent, location: displayPath(url.deletingLastPathComponent(), home: home), sizeBytes: size
                ))
            }
        }
        let category = CleanupCategory(
            id: definition.id, title: definition.title, items: items, itemCount: sized.count,
            totalBytes: sized.reduce(0) { $0 + $1.1 }, selectedByDefault: definition.selectedByDefault,
            alwaysPermanent: definition.alwaysPermanent, unavailableReason: unavailable
        )
        return (category, entries)
    }

    /// Strictly inside the home folder (never the home folder itself) and still there.
    static func isDeletable(_ url: URL, home: String) -> Bool {
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(home + "/"), !path.contains("/../") else { return false }
        var info = stat()
        return lstat(path, &info) == 0
    }

    static func displayPath(_ url: URL, home: String) -> String {
        let path = url.standardizedFileURL.path
        if path == home { return "~" }
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}
