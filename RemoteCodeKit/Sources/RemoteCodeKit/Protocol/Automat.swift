import Foundation

// Automat bridge (capability `automat`, D-112).
//
// Automat is a separate macOS app that makes social-media videos. It exposes a
// token-protected HTTP API on 127.0.0.1 (see Automat's docs/CONTROL_API.md).
// The Mac forwards these requests verbatim, so the phone can drive Automat over
// the encrypted channel without the protocol knowing Automat's endpoints.

/// Phone → Mac: one HTTP request to Automat's local control API.
public struct AutomatRequest: Sendable, Hashable, Codable {
    /// "GET" or "POST"
    public var method: String
    /// Path below the API root, e.g. "/v1/state" or "/v1/actions/produce".
    public var path: String
    /// JSON request body (text), for POST.
    public var body: String?
    /// HTTP `Range` header value, e.g. "bytes=0-4194303", for chunked media downloads.
    public var range: String?

    public init(method: String = "GET", path: String, body: String? = nil, range: String? = nil) {
        self.method = method
        self.path = path
        self.body = body
        self.range = range
    }

    /// Largest media chunk the phone should request; keeps each message well
    /// below `MessageTransport.maximumMessageSize` after base64.
    public static let maxChunkBytes = 4 * 1024 * 1024
}

/// Mac → phone: Automat's HTTP response.
public struct AutomatResponse: Sendable, Hashable, Codable {
    public var status: Int
    public var contentType: String?
    /// `Content-Range` for partial (206) media responses.
    public var contentRange: String?
    public var body: Data

    public init(status: Int, contentType: String? = nil, contentRange: String? = nil, body: Data = Data()) {
        self.status = status
        self.contentType = contentType
        self.contentRange = contentRange
        self.body = body
    }

    /// Total size from a `Content-Range: bytes a-b/total` header.
    public var totalSize: Int? {
        contentRange.flatMap { $0.split(separator: "/").last.flatMap { Int($0) } }
    }
}

/// Mac → phone push: one server-sent event from Automat (`changed`, `job`, `jobEnded`, `alert`, `ping`).
public struct AutomatEvent: Sendable, Hashable, Codable {
    public var event: String
    /// The event's JSON data, as text.
    public var data: String

    public init(event: String, data: String) {
        self.event = event
        self.data = data
    }
}

extension ErrorCode {
    /// Automat is not installed or not running on the Mac.
    public static let automatUnavailable = ErrorCode("automatUnavailable")
}
