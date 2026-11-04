// Ported from Vitrin for Mac (apps/VitrinMac/VitrinMac/Core/AscCache.swift).
import CryptoKit
import Foundation
import Observation

/// What App Store Connect answered, kept on disk per account: pages open from here at once instead of waiting for
/// `asc`, and most of them need no request at all, because this data changes slowly.
///
/// A result younger than its lifetime is used as it is. An older one shows at once and is read again behind it. A
/// read that fails leaves what is showing. A change made through the app marks everything old, so the next read of
/// anything goes to App Store Connect, while the page still opens with what it had.
@MainActor @Observable final class AscCache {
    static let shared = AscCache()

    struct Entry: Codable, Sendable {
        /// When the request started: a result that left before a change never counts as newer than the change.
        var fetchedAt: Date
        var doc: VitrinJSON
    }

    private final class Box {
        let entry: Entry
        init(_ entry: Entry) { self.entry = entry }
    }

    /// The App Store Connect key the results belong to. Without one nothing is kept: another team's data never shows.
    var account: String? {
        didSet { if account != oldValue, oldValue != nil { reloadVisible() } }
    }
    /// Pages read again when this changes.
    private(set) var revision = 0
    private var running: [String: Task<Entry, Error>] = [:]
    /// A read is on its way.
    var isFetching: Bool { !running.isEmpty }

    @ObservationIgnored private let memory = NSCache<NSString, Box>()
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private var staleBefore: Date

    init(directory: URL = AscCache.defaultDirectory) {
        self.directory = directory
        staleBefore = (try? Data(contentsOf: directory.appendingPathComponent(Self.markerName)))
            .flatMap { Double(String(decoding: $0, as: UTF8.self)) }
            .map(Date.init(timeIntervalSince1970:)) ?? .distantPast
        Task.detached(priority: .background) { Self.trim(directory) }
    }

    /// Caches stays out of the phone's backups, and the system may empty it when it needs the room.
    nonisolated static var defaultDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Vitrin/asc")
    }

    // MARK: lifetimes

    private nonisolated static let minute: TimeInterval = 60
    /// Moves while a release is under way: states, builds, TestFlight, and anything not named here.
    nonisolated static let short = 15 * minute
    /// Changes when someone changes it: store text, reviews, products.
    nonisolated static let medium = 60 * minute
    /// Rarely changes, or Apple updates it about daily: people, signing, reports.
    nonisolated static let long = 6 * 60 * minute

    /// How long a result stays good; nil when it must always be read: who is signed in, and numbers an upload relies on.
    nonisolated static func lifetime(_ args: [String]) -> TimeInterval? {
        let first = args.first ?? "", second = args.dropFirst().first ?? ""
        switch first {
        case "auth": return nil
        case "web": return second == "analytics" ? long : nil
        case "ads": return second == "auth" ? nil : medium
        case "builds": return second == "next-build-number" ? nil : short
        case "api": return args.contains("/v1/builds") ? long : short
        case "users", "devices", "certificates", "profiles", "bundle-ids", "merchant-ids", "pass-type-ids", "finance",
             "analytics", "insights", "performance", "pricing", "age-rating", "eula":
            return long
        case "apps": return second == "content-rights" ? long : short
        case "reviews", "localizations", "iap", "subscriptions", "video-previews", "screenshots", "product-pages", "app-events":
            return medium
        default: return short
        }
    }

    func isFresh(_ entry: Entry, lifetime: TimeInterval, now: Date = .now) -> Bool {
        entry.fetchedAt >= staleBefore && now.timeIntervalSince(entry.fetchedAt) < lifetime
    }

    // MARK: reading

    /// What is already in memory, for the first frame of a page.
    func peek(_ args: [String]) -> Entry? {
        id(args).flatMap { memory.object(forKey: $0 as NSString)?.entry }
    }

    /// One read, cache first. `deliver` gets the stored result, if any, then the new one when it had to be read.
    /// `force` skips the stored result. It throws only when there is nothing to show (or a forced read fails).
    func read(_ args: [String], force: Bool = false, fetch: @escaping @MainActor () async throws -> VitrinJSON, deliver: (Entry) -> Void) async throws {
        guard let lifetime = Self.lifetime(args), let id = id(args) else {
            let doc = try await fetch()
            if !Task.isCancelled { deliver(Entry(fetchedAt: .now, doc: doc)) }
            return
        }
        var shown = false
        if !force, let entry = await stored(id) {
            guard !Task.isCancelled else { return }
            deliver(entry)
            shown = true
            if isFresh(entry, lifetime: lifetime) { return }
        }
        do {
            let entry = try await fetched(id, fetch)
            if !Task.isCancelled { deliver(entry) }
        } catch {
            if !shown { throw error }
        }
    }

    /// The result of a read, for the code that wants one answer rather than a page that updates.
    func value(_ args: [String], fetch: @escaping @MainActor () async throws -> VitrinJSON) async throws -> VitrinJSON {
        var latest: VitrinJSON?
        try await read(args, fetch: fetch) { latest = $0.doc }
        guard let latest else { throw CancellationError() }
        return latest
    }

    /// Two pages asking for the same thing share one request, and leaving a page doesn't waste one that is under way.
    private func fetched(_ id: String, _ fetch: @escaping @MainActor () async throws -> VitrinJSON) async throws -> Entry {
        if let task = running[id] { return try await task.value }
        let started = Date.now
        let task = Task { Entry(fetchedAt: started, doc: try await fetch()) }
        running[id] = task
        let result = await task.result
        if running[id] == task { running[id] = nil }
        let entry = try result.get()
        await store(entry, id: id)
        return entry
    }

    private func stored(_ id: String) async -> Entry? {
        if let box = memory.object(forKey: id as NSString) { return box.entry }
        let url = file(id)
        let entry = await Task.detached(priority: .userInitiated) { () -> Entry? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(Entry.self, from: data)
        }.value
        if let entry { memory.setObject(Box(entry), forKey: id as NSString) }
        return entry
    }

    private func store(_ entry: Entry, id: String) async {
        // A slow read that started before a newer one doesn't replace it.
        if let current = memory.object(forKey: id as NSString)?.entry, current.fetchedAt > entry.fetchedAt { return }
        memory.setObject(Box(entry), forKey: id as NSString)
        let url = file(id)
        await Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(entry) else { return }
            Self.write(data, to: url)
        }.value
    }

    /// Stores a result as if it had just been read.
    func save(_ entry: Entry, for args: [String]) async {
        if let id = id(args) { await store(entry, id: id) }
    }

    // MARK: changes

    /// The account's data changed: nothing stored counts as fresh any more, and reads under way don't either.
    func markStale() {
        staleBefore = .now
        running.removeAll()
        let at = String(staleBefore.timeIntervalSince1970), url = directory.appendingPathComponent(Self.markerName)
        Task.detached(priority: .utility) { Self.write(Data(at.utf8), to: url) }
    }

    /// The pages on screen read again, skipping what is stored.
    func reloadVisible() {
        revision += 1
    }

    /// The key is gone: so is everything read with it.
    func removeAll() {
        memory.removeAllObjects()
        running.removeAll()
        staleBefore = .distantPast
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: disk

    private nonisolated static let markerName = "stale-before"

    private func id(_ args: [String]) -> String? {
        account.map { "\(Self.hash($0))/\(Self.hash(args.joined(separator: "\u{1F}")))" }
    }

    private func file(_ id: String) -> URL { directory.appendingPathComponent(id + ".json") }

    private nonisolated static func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    /// Results name testers and customers, so they stay encrypted until the phone is first unlocked.
    private nonisolated static func write(_ data: Data, to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// Nothing older than a month, and at most 100 MB, newest kept.
    private nonisolated static func trim(_ directory: URL) {
        let manager = FileManager.default
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        guard let walker = manager.enumerator(at: directory, includingPropertiesForKeys: keys) else { return }
        let oldest = Date.now.addingTimeInterval(-30 * 24 * 3600)
        var files: [(url: URL, date: Date, size: Int)] = []
        for case let url as URL in walker where url.pathExtension == "json" {
            guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { continue }
            files.append((url, v.contentModificationDate ?? .distantPast, v.fileSize ?? 0))
        }
        var total = 0
        for f in files.sorted(by: { $0.date > $1.date }) {
            total += f.size
            if f.date < oldest || total > 100_000_000 { try? manager.removeItem(at: f.url) }
        }
    }
}
