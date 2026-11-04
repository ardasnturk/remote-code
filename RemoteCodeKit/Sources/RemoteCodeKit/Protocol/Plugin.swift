import Foundation

// Plugins (D-117): a tool on the Mac that the phone drives through a local API.
//
// The messages carry a plugin's id and know nothing else about it, so a new plugin
// needs a `HostPlugin` on the Mac and a tab on the phone, and no change to the
// protocol. The Mac forwards each request to the plugin and pushes its events.
// A plugin is announced as the capability `plugin.<id>`.

/// Phone → Mac: one request to a plugin's API.
public struct PluginRequest: Sendable, Hashable, Codable {
    public var plugin: String
    /// "GET", "POST", "PUT" or "DELETE"
    public var method: String
    /// Path of the plugin's API, e.g. "/v1/projects".
    public var path: String
    /// Request body as text, for POST and PUT.
    public var body: String?
    /// HTTP `Range` header value, for files fetched in chunks.
    public var range: String?
    /// Seconds the Mac waits for the plugin; a long-running step sets more than the default.
    public var timeout: Int?

    public init(plugin: String, method: String = "GET", path: String, body: String? = nil, range: String? = nil, timeout: Int? = nil) {
        self.plugin = plugin
        self.method = method
        self.path = path
        self.body = body
        self.range = range
        self.timeout = timeout
    }

    /// Largest chunk the phone asks for; keeps a message well below
    /// `maximumMessageSize` after base64.
    public static let maxChunkBytes = 4 * 1024 * 1024
}

/// Mac → phone: the plugin's answer.
public struct PluginResponse: Sendable, Hashable, Codable {
    public var status: Int
    public var contentType: String?
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

/// Mac → phone push: one event from a plugin.
public struct PluginEvent: Sendable, Hashable, Codable {
    public var plugin: String
    public var event: String
    /// The event's data, as text.
    public var data: String

    public init(plugin: String, event: String, data: String) {
        self.plugin = plugin
        self.event = event
        self.data = data
    }
}

/// Phone → Mac: follow or stop following a plugin's events.
public struct PluginRef: Sendable, Hashable, Codable {
    public var plugin: String

    public init(plugin: String) {
        self.plugin = plugin
    }
}

extension HostCapability {
    /// The capability a host announces for a plugin.
    public static func plugin(_ id: String) -> String { "plugin.\(id)" }
    public static let vitrin = plugin(PluginID.vitrin)
}

public enum PluginID {
    public static let vitrin = "vitrin"
}

extension ErrorCode {
    /// The plugin is not on this Mac, or could not be reached.
    public static let pluginUnavailable = ErrorCode("pluginUnavailable")
}
