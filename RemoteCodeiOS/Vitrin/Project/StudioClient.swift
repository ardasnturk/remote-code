// Ported from Vitrin for Mac (apps/VitrinMac/VitrinMac/Core/StudioClient.swift): the same API, through the Mac.
import Foundation
import RemoteCodeKit

/// Errors the Studio API answers with (`{ error, code?, issues?, params? }`).
struct StudioAPIError: LocalizedError, Sendable {
    var status: Int
    var message: String
    var code: String?
    var issues: [String]
    var errorDescription: String? { issues.isEmpty ? message : message + "\n" + issues.joined(separator: "\n") }
}

/// One server-sent event from the project's Studio, as the hub passes it on.
struct StudioEvent: Sendable {
    var name: String
    var data: Data
    func decode<T: Decodable>(_ type: T.Type) -> T? { try? JSONDecoder().decode(T.self, from: data) }
}

/// The Studio's HTTP API (packages/cli/src/studio/server.ts), one project of the hub's: the phone can't reach the
/// Mac's 127.0.0.1, so each request travels as a plugin request. The hub adds the session token.
@MainActor
struct StudioClient {
    let project: String
    let store: VitrinStore

    private func route(_ path: String, query: [String: String] = [:]) -> String {
        var components = URLComponents()
        components.queryItems = query.isEmpty ? nil : query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return "/v1/projects/\(project)/studio\(path)\(components.percentEncodedQuery.map { "?\($0)" } ?? "")"
    }

    private struct ErrorBody: Decodable {
        var error: String
        var code: String?
        var issues: [String]?
    }

    private struct AnyEncodable: Encodable {
        let value: any Encodable
        init(_ value: any Encodable) { self.value = value }
        func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
    }

    struct OK: Decodable, Sendable { var ok: Bool? }
    private struct Empty: Decodable {}

    private func request<T: Decodable>(_ method: String, _ path: String, query: [String: String] = [:], body: (any Encodable)? = nil, as type: T.Type) async throws -> T {
        var text: String?
        if method != "GET" {
            text = String(decoding: try JSONEncoder().encode(AnyEncodable(body ?? [String: String]())), as: UTF8.self)
        }
        let response = try await store.call(method, route(path, query: query), body: text, timeout: 120, checked: false)
        guard (200..<300).contains(response.status) else {
            let e = try? JSONDecoder().decode(ErrorBody.self, from: response.body)
            throw StudioAPIError(status: response.status, message: e?.error ?? "HTTP \(response.status)", code: e?.code, issues: e?.issues ?? [])
        }
        return try JSONDecoder().decode(T.self, from: response.body)
    }

    func overview() async throws -> Overview { try await request("GET", "/api/overview", as: Overview.self) }
    func jobs() async throws -> [JobSummary] { try await request("GET", "/api/jobs", as: [JobSummary].self) }
    func job(_ id: String) async throws -> Job { try await request("GET", "/api/jobs/\(id)", as: Job.self) }
    func run(_ command: String, args: [String: VitrinJSON] = [:], force: Bool = false) async throws -> JobSummary {
        struct Body: Encodable { var command: String; var args: [String: VitrinJSON]; var force: Bool }
        return try await request("POST", "/api/jobs", body: Body(command: command, args: args, force: force), as: JobSummary.self)
    }
    func file(_ path: String) async throws -> EditableFile { try await request("GET", "/api/file", query: ["path": path], as: EditableFile.self) }
    func save(_ path: String, text: String) async throws {
        struct Body: Encodable { var path: String; var text: String }
        _ = try await request("PUT", "/api/file", body: Body(path: path, text: text), as: OK.self)
    }
    func claude() async throws -> ClaudeInfo { try await request("GET", "/api/claude", as: ClaudeInfo.self) }
    func askClaude(prompt: String? = nil, stage: String? = nil, extra: String? = nil, fresh: Bool? = nil, model: String? = nil) async throws {
        struct Body: Encodable { var prompt: String?; var stage: String?; var extra: String?; var fresh: Bool?; var model: String? }
        struct Started: Decodable { var id: String }
        _ = try await request("POST", "/api/claude", body: Body(prompt: prompt, stage: stage, extra: extra, fresh: fresh, model: model), as: Started.self)
    }
    func cancelClaude() async throws { _ = try await request("POST", "/api/claude/cancel", body: [String: String](), as: Empty.self) }
    func resetClaude() async throws { _ = try await request("POST", "/api/claude/reset", body: [String: String](), as: OK.self) }
    func answer(question id: String, answer: String, model: String? = nil) async throws {
        struct Body: Encodable { var id: String; var answer: String; var model: String? }
        struct Started: Decodable { var id: String }
        _ = try await request("POST", "/api/questions/answer", body: Body(id: id, answer: answer, model: model), as: Started.self)
    }
    func review() async throws -> ReviewState { try await request("GET", "/api/review", as: ReviewState.self) }
    func approve(overallHash: String) async throws {
        struct Body: Encodable { var overallHash: String }
        _ = try await request("POST", "/api/approve", body: Body(overallHash: overallHash), as: OK.self)
    }
    struct Rejection: Encodable, Sendable { var item: String; var comment: String }
    func reject(overallHash: String, rejections: [Rejection]) async throws -> Int {
        struct Body: Encodable { var overallHash: String; var rejections: [Rejection] }
        struct Result: Decodable { var rejected: Int }
        return try await request("POST", "/api/reject", body: Body(overallHash: overallHash, rejections: rejections), as: Result.self).rejected
    }
    func open(_ path: String, reveal: Bool = false) async throws {
        struct Body: Encodable { var path: String; var reveal: Bool }
        _ = try await request("POST", "/api/open", body: Body(path: path, reveal: reveal), as: OK.self)
    }
    func startRemotion(locale: String?) async throws {
        struct Body: Encodable { var locale: String? }
        _ = try await request("POST", "/api/remotion", body: Body(locale: locale), as: Empty.self)
    }
    func stopRemotion() async throws { _ = try await request("DELETE", "/api/remotion", as: Empty.self) }

    // MARK: Files

    /// A path under the app root (`metadata/…`), as the Studio serves it.
    func filePath(_ rel: String, bust: String? = nil) -> String {
        let encoded = rel.split(separator: "/").map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }.joined(separator: "/")
        return "/v1/projects/\(project)/studio/files/\(encoded)\(bust.map { "?v=\($0)" } ?? "")"
    }

    /// A file of any size: one message carries `PluginRequest.maxChunkBytes`, so a large one arrives in pieces, handed
    /// to `receive` as they come. `total` is nil until the first piece told it.
    func readFile(_ rel: String, bust: String? = nil, receive: (_ piece: Data, _ total: Int?) throws -> Void) async throws {
        let path = filePath(rel, bust: bust)
        let chunk = PluginRequest.maxChunkBytes
        var offset = 0
        while true {
            let reply = try await store.call("GET", path, range: "bytes=\(offset)-\(offset + chunk - 1)", timeout: 120, checked: false)
            try Task.checkCancellation()
            guard (200..<300).contains(reply.status) else { throw StudioAPIError(status: reply.status, message: "HTTP \(reply.status)", code: nil, issues: []) }
            try receive(reply.body, reply.totalSize ?? reply.body.count)
            offset += reply.body.count
            guard reply.status == 206, let total = reply.totalSize, offset < total, !reply.body.isEmpty else { return }
        }
    }

    func fileData(_ rel: String, bust: String? = nil) async throws -> Data {
        var data = Data()
        try await readFile(rel, bust: bust) { piece, _ in data.append(piece) }
        return data
    }
}
