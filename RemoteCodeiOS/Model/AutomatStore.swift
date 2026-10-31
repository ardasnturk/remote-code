import CryptoKit
import Foundation
import Observation
import RemoteCodeKit

/// The Automat tab's live state: forwards requests to the Automat app on the
/// Mac (capability `automat`) and follows its events. Owned by `MacConnection`.
@MainActor
@Observable
final class AutomatStore {
    /// Automat answered on the connected Mac; the tab is shown only then.
    private(set) var isAvailable = false
    private(set) var state: AutomatState?
    /// Live job progress by post or project id (from events, newer than `state.jobs`).
    private(set) var jobs: [String: AutomatJob] = [:]
    /// Latest alert Automat showed on the Mac.
    var alert: (title: String, message: String)?
    private(set) var lastError: String?

    @ObservationIgnored private weak var connection: MacConnection?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var subscribed = false
    /// While connected but Automat is not running, checks again every 10 s so the tab appears when it starts.
    @ObservationIgnored private var availabilityTask: Task<Void, Never>?

    init() {}

    func attach(_ connection: MacConnection) {
        self.connection = connection
    }

    // MARK: Lifecycle (called by MacConnection)

    func connected(capabilities: Set<String>) async {
        subscribed = false
        availabilityTask?.cancel()
        guard capabilities.contains(HostCapability.automat) else {
            isAvailable = false
            return
        }
        await refresh()
        await subscribe()
        availabilityTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard let self, !Task.isCancelled else { return }
                if !self.isAvailable || !self.subscribed { await self.retry() }
            }
        }
    }

    func disconnected() {
        subscribed = false
        availabilityTask?.cancel()
        availabilityTask = nil
    }

    /// Tries again (e.g. after Automat was started on the Mac).
    func retry() async {
        await refresh()
        await subscribe()
    }

    private func subscribe() async {
        guard isAvailable, !subscribed, let client = connection?.client else { return }
        if (try? await client.request(.automatSubscribe)) != nil { subscribed = true }
    }

    func handle(_ event: AutomatEvent) {
        let object = (try? JSONSerialization.jsonObject(with: Data(event.data.utf8))) as? [String: Any] ?? [:]
        switch event.event {
        case "changed":
            scheduleRefresh()
        case "job":
            guard let id = object["id"] as? String else { return }
            jobs[id] = AutomatJob(message: object["message"] as? String ?? "", progress: object["progress"] as? Double)
        case "jobEnded":
            if let id = object["id"] as? String { jobs[id] = nil }
            scheduleRefresh()
        case "alert":
            alert = (object["title"] as? String ?? "Automat", object["message"] as? String ?? "")
        default:
            break
        }
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    func refresh() async {
        do {
            let data = try await call("GET", "/v1/state")
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decoded = try decoder.decode(AutomatState.self, from: data)
            state = decoded
            jobs = decoded.jobs
            isAvailable = true
            lastError = nil
        } catch let error as ErrorPayload where error.code == .automatUnavailable {
            isAvailable = false
            state = nil
            subscribed = false
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: Lookups

    func project(_ id: String) -> AutomatProject? { state?.projects.first { $0.id == id } }
    func post(_ id: String) -> AutomatPost? { state?.posts.first { $0.id == id } }
    func posts(for projectId: String) -> [AutomatPost] { state?.posts.filter { $0.projectId == projectId } ?? [] }
    func account(_ id: String?) -> AutomatAccount? { state?.accounts.first { $0.userId == id } }
    func job(_ id: String) -> AutomatJob? { jobs[id] }

    // MARK: Requests

    /// Sends one request to Automat's API; non-2xx responses throw Automat's message.
    @discardableResult
    func call(_ method: String, _ path: String, body: [String: Any]? = nil, range: String? = nil, timeout: TimeInterval = 60) async throws -> Data {
        guard let client = connection?.client else { throw AutomatStoreError.notConnected }
        let text = try body.map { String(decoding: try JSONSerialization.data(withJSONObject: $0), as: UTF8.self) }
        let response = try await client.request(.automat(AutomatRequest(method: method, path: path, body: text, range: range)), timeout: timeout)
        guard case .automatResponse(let result) = response else {
            throw MacClientError.unexpectedResponse(response.typeName)
        }
        guard (200..<300).contains(result.status) else {
            let message = ((try? JSONSerialization.jsonObject(with: result.body)) as? [String: Any])?["error"] as? String
            throw AutomatStoreError.failed(message ?? "HTTP \(result.status)")
        }
        return result.body
    }

    /// Runs an action (`POST /v1/actions/<name>`) and returns its JSON result.
    @discardableResult
    func action(_ name: String, _ body: [String: Any] = [:]) async throws -> [String: Any] {
        let data = try await call("POST", "/v1/actions/\(name)", body: body)
        let result = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        scheduleRefresh()
        return result
    }

    // MARK: Media

    /// Downloads a media file (video in 4 MB chunks) into the cache and returns
    /// its local URL. The cache key includes the file size, so a re-rendered
    /// video is fetched again.
    func mediaFile(_ path: String, progress: (@MainActor (Double) -> Void)? = nil) async throws -> URL {
        let chunk = AutomatRequest.maxChunkBytes
        guard let client = connection?.client else { throw AutomatStoreError.notConnected }
        func fetch(_ from: Int) async throws -> AutomatResponse {
            let response = try await client.request(.automat(AutomatRequest(path: path, range: "bytes=\(from)-\(from + chunk - 1)")), timeout: 90)
            guard case .automatResponse(let result) = response, (200..<300).contains(result.status) else {
                throw AutomatStoreError.failed(String(localized: "The file could not be loaded."))
            }
            return result
        }
        let first = try await fetch(0)
        let total = first.totalSize ?? first.body.count
        let name = SHA256.hash(data: Data("\(path)#\(total)".utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
        let ext = (path as NSString).pathExtension
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Automat", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(name).\(ext)")
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size == total { return url }

        var data = first.body
        progress?(Double(data.count) / Double(max(total, 1)))
        while data.count < total {
            let next = try await fetch(data.count)
            guard !next.body.isEmpty else { break }
            data.append(next.body)
            progress?(Double(data.count) / Double(max(total, 1)))
        }
        try data.write(to: url, options: .atomic)
        return url
    }
}

enum AutomatStoreError: LocalizedError {
    case notConnected
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .notConnected: String(localized: "Not connected to your Mac.")
        case .failed(let message): message
        }
    }
}
