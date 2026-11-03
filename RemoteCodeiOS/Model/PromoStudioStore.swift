import CryptoKit
import Foundation
import ImageIO
import Observation
import RemoteCodeKit

/// The Promo Studio tab's live state: forwards requests to the Promo Studio app on the
/// Mac (capability `promoStudio`) and follows its events. Owned by `MacConnection`.
@MainActor
@Observable
final class PromoStudioStore {
    /// Promo Studio answered on the connected Mac; the tab is shown only then.
    private(set) var isAvailable = false
    private(set) var state: PromoStudioState?
    /// Live job progress by post or project id (from events, newer than `state.jobs`).
    private(set) var jobs: [String: PromoStudioJob] = [:]
    /// Latest alert Promo Studio showed on the Mac; `problem` when it is a failure Promo Studio explained.
    var alert: (title: String, message: String, problem: PromoStudioProblem?)?
    /// A fix asked for the accounts screen (reconnect an Instagram account); the home view opens it.
    var accountsRequested = false
    private(set) var lastError: String?

    @ObservationIgnored private weak var connection: MacConnection?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var subscribed = false
    /// While connected but Promo Studio is not running, checks again every 10 s so the tab appears when it starts.
    @ObservationIgnored private var availabilityTask: Task<Void, Never>?

    init() {}

    func attach(_ connection: MacConnection) {
        self.connection = connection
    }

    // MARK: Lifecycle (called by MacConnection)

    func connected(capabilities: Set<String>) async {
        subscribed = false
        availabilityTask?.cancel()
        guard capabilities.contains(HostCapability.promoStudio) else {
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

    /// Tries again (e.g. after Promo Studio was started on the Mac).
    func retry() async {
        await refresh()
        await subscribe()
    }

    private func subscribe() async {
        guard isAvailable, !subscribed, let client = connection?.client else { return }
        if (try? await client.request(.promoStudioSubscribe)) != nil { subscribed = true }
    }

    func handle(_ event: PromoStudioEvent) {
        let object = (try? JSONSerialization.jsonObject(with: Data(event.data.utf8))) as? [String: Any] ?? [:]
        switch event.event {
        case "changed":
            scheduleRefresh()
        case "job":
            guard let id = object["id"] as? String else { return }
            jobs[id] = PromoStudioJob(
                message: object["message"] as? String ?? "",
                progress: object["progress"] as? Double,
                estimatedEnd: (object["estimatedEnd"] as? String).flatMap { try? Date($0, strategy: .iso8601) }
            )
        case "jobEnded":
            if let id = object["id"] as? String { jobs[id] = nil }
            scheduleRefresh()
        case "finished":
            if let id = object["id"] as? String { jobs[id] = nil }
            scheduleRefresh()
        case "alert":
            let problem = (object["problem"] as? [String: Any]).flatMap { try? JSONSerialization.data(withJSONObject: $0) }
                .flatMap { try? JSONDecoder().decode(PromoStudioProblem.self, from: $0) }
            alert = (object["title"] as? String ?? "Promo Studio", object["message"] as? String ?? "", problem)
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
            let decoded = try decoder.decode(PromoStudioState.self, from: data)
            state = decoded
            jobs = decoded.jobs
            isAvailable = true
            lastError = nil
        } catch let error as ErrorPayload where error.code == .promoStudioUnavailable {
            lastError = String(localized: "Promo Studio isn’t open on your Mac. Open it there and try again.")
            isAvailable = false
            state = nil
            subscribed = false
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: Lookups

    func project(_ id: String?) -> PromoStudioProject? { id.flatMap { id in state?.projects.first { $0.id == id } } }
    func library(_ id: String) -> PromoStudioLibrary? { state?.libraries?.first { $0.id == id } }
    func post(_ id: String) -> PromoStudioPost? { state?.posts.first { $0.id == id } }
    func posts(for projectId: String) -> [PromoStudioPost] { state?.posts.filter { $0.projectId == projectId } ?? [] }
    func account(_ id: String?) -> PromoStudioAccount? { id.flatMap { id in state?.accounts.first { $0.userId == id } } }
    /// The account a post goes to: its own, else its project's
    func account(for post: PromoStudioPost) -> PromoStudioAccount? { account(post.accountId) ?? account(project(post.projectId)?.accountId) }
    func job(_ id: String) -> PromoStudioJob? { jobs[id] }

    // MARK: Requests

    /// Sends one request to Promo Studio's API; non-2xx responses throw Promo Studio's message.
    @discardableResult
    func call(_ method: String, _ path: String, body: [String: Any]? = nil, range: String? = nil, timeout: TimeInterval = 60) async throws -> Data {
        guard let client = connection?.client else { throw PromoStudioStoreError.notConnected }
        let text = try body.map { String(decoding: try JSONSerialization.data(withJSONObject: $0), as: UTF8.self) }
        let response = try await client.request(.promoStudio(PromoStudioRequest(method: method, path: path, body: text, range: range)), timeout: timeout)
        guard case .promoStudioResponse(let result) = response else {
            throw MacClientError.unexpectedResponse(response.typeName)
        }
        guard (200..<300).contains(result.status) else {
            let message = ((try? JSONSerialization.jsonObject(with: result.body)) as? [String: Any])?["error"] as? String
            // An older Promo Studio doesn't know the newer actions the phone sends
            if result.status == 400, message?.hasPrefix("Unknown action") == true || message?.hasPrefix("Bilinmeyen") == true {
                throw PromoStudioStoreError.outdated
            }
            throw PromoStudioStoreError.failed(message ?? "HTTP \(result.status)")
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

    /// Runs a problem's fix that Promo Studio does on the Mac (retry, repair, without voiceover).
    func fix(_ fix: PromoStudioProblem.Fix, postId: String) async throws {
        try await action("fix", ["postId": postId, "fix": fix.rawValue])
    }

    /// Sends an image for a new post ahead of it; returns the ID createDirectedPost takes in `uploads`.
    /// The image is made upright, at most 2048 px and JPEG, so one request stays under the relay's 4 MB message.
    func uploadImage(_ data: Data) async throws -> String {
        guard let jpeg = Self.prepared(data) else { throw PromoStudioStoreError.failed(String(localized: "This image can’t be read.")) }
        let result = try await action("uploadImage", ["data": jpeg.base64EncodedString()])
        guard let id = result["uploadId"] as? String else { throw PromoStudioStoreError.outdated }
        return id
    }

    nonisolated static func prepared(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        for side in [2048, 1600, 1200] {
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: side,
            ] as CFDictionary) else { return nil }
            let out = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(out, "public.jpeg" as CFString, 1, nil) else { return nil }
            CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
            guard CGImageDestinationFinalize(dest) else { return nil }
            // Base64 grows it by a third
            if out.length < 2_800_000 { return out as Data }
        }
        return nil
    }

    // MARK: Media

    /// Downloads a media file (video in 4 MB chunks) into the cache and returns
    /// its local URL. The cache key includes the file size, so a re-rendered
    /// video is fetched again.
    func mediaFile(_ path: String, progress: (@MainActor (Double) -> Void)? = nil) async throws -> URL {
        let chunk = PromoStudioRequest.maxChunkBytes
        guard let client = connection?.client else { throw PromoStudioStoreError.notConnected }
        func fetch(_ from: Int) async throws -> PromoStudioResponse {
            let response = try await client.request(.promoStudio(PromoStudioRequest(path: path, range: "bytes=\(from)-\(from + chunk - 1)")), timeout: 90)
            guard case .promoStudioResponse(let result) = response, (200..<300).contains(result.status) else {
                throw PromoStudioStoreError.failed(String(localized: "The file could not be loaded."))
            }
            return result
        }
        let first = try await fetch(0)
        let total = first.totalSize ?? first.body.count
        let name = SHA256.hash(data: Data("\(path)#\(total)".utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
        let ext = (path as NSString).pathExtension
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Promo Studio", isDirectory: true)
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

enum PromoStudioStoreError: LocalizedError {
    case notConnected
    case outdated
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .notConnected: String(localized: "Not connected to your Mac.")
        case .outdated: String(localized: "Promo Studio on your Mac is too old for this. Update it to the latest version and try again.")
        case .failed(let message): message
        }
    }
}
