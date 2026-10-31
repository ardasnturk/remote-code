import Foundation
import RemoteCodeKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Forwards phone requests to the Promo Studio app's local control API (D-112).
///
/// Promo Studio writes `~/Library/Application Support/Promo Studio/control.json`
/// (`{version, port, token, pid}`, mode 0600) while it runs and serves a
/// token-protected HTTP API on 127.0.0.1. This bridge reads that file for every
/// request, so it follows Promo Studio restarts without any setup.
public actor PromoStudioBridge {
    struct ControlInfo: Decodable {
        var version: Int
        var port: Int
        var token: String
    }

    private let infoURL: URL
    private let session: URLSession

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        infoURL = home.appendingPathComponent("Library/Application Support/Promo Studio/control.json")
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.connectionProxyDictionary = [:]
        session = URLSession(configuration: config)
    }

    private func info() throws -> ControlInfo {
        guard let data = try? Data(contentsOf: infoURL), let info = try? JSONDecoder().decode(ControlInfo.self, from: data) else {
            throw Self.unavailable
        }
        return info
    }

    static let unavailable = ErrorPayload(code: .promoStudioUnavailable, message: "Promo Studio is not running on this Mac.")

    private func urlRequest(_ path: String, info: ControlInfo) throws -> URLRequest {
        guard path.hasPrefix("/v1/"), !path.contains(".."), let url = URL(string: "http://127.0.0.1:\(info.port)\(path)") else {
            throw ErrorPayload(code: .invalidRequest, message: "Invalid Promo Studio path.")
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(info.token)", forHTTPHeaderField: "Authorization")
        return request
    }

    public func send(_ request: PromoStudioRequest) async throws -> PromoStudioResponse {
        let info = try info()
        var req = try urlRequest(request.path, info: info)
        req.httpMethod = request.method == "POST" ? "POST" : "GET"
        if let body = request.body {
            req.httpBody = Data(body.utf8)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        // Media always travels in chunks so a response fits in one message.
        if let range = request.range {
            req.setValue(range, forHTTPHeaderField: "Range")
        } else if request.path.hasPrefix("/v1/media/") {
            req.setValue("bytes=0-\(PromoStudioRequest.maxChunkBytes - 1)", forHTTPHeaderField: "Range")
        }
        do {
            let (data, response) = try await session.data(for: req)
            let http = response as? HTTPURLResponse
            return PromoStudioResponse(
                status: http?.statusCode ?? 0,
                contentType: http?.value(forHTTPHeaderField: "Content-Type"),
                contentRange: http?.value(forHTTPHeaderField: "Content-Range"),
                body: data
            )
        } catch {
            throw Self.unavailable
        }
    }

    /// Promo Studio's server-sent events; reconnects (also across Promo Studio restarts)
    /// until the returned stream is cancelled.
    public nonisolated func events() -> AsyncStream<PromoStudioEvent> {
        AsyncStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    await self.readEvents { continuation.yield($0) }
                    try? await Task.sleep(for: .seconds(3))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func readEvents(_ yield: @Sendable (PromoStudioEvent) -> Void) async {
        #if canImport(FoundationNetworking)
        // URLSession.bytes is unavailable on Linux; the bridge only runs on macOS.
        return
        #else
        guard let info = try? info(), var req = try? urlRequest("/v1/events", info: info) else { return }
        req.timeoutInterval = 120
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        guard let (bytes, response) = try? await session.bytes(for: req),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return }
        var event = "message"
        var data = ""
        do {
            for try await line in bytes.lines {
                if line.hasPrefix("event:") {
                    event = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
                } else if line.hasPrefix("data:") {
                    data += line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                }
                // `lines` drops the blank separator, so an event ends with its data line.
                if line.hasPrefix("data:") {
                    yield(PromoStudioEvent(event: event, data: data))
                    event = "message"
                    data = ""
                }
            }
        } catch {}
        #endif
    }
}
