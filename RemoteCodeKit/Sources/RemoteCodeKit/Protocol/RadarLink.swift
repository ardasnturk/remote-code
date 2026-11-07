import Foundation

/// `pilothouse://mrradar/<project>?mac=<macId>` or `pilothouse://funnelradar/…`: opens a
/// project in that tab (a tapped notification, D-119).
public struct RadarLink: Sendable, Hashable {
    public var app: String
    public var project: String
    public var macId: String?

    public init(app: String = PluginID.mrradar, project: String, macId: String? = nil) {
        self.app = app
        self.project = project
        self.macId = macId
    }

    public init?(url: URL) {
        guard url.scheme == PairingPayload.scheme, let host = url.host,
              host == PluginID.mrradar || host == PluginID.funnelradar else { return nil }
        let id = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !id.isEmpty else { return nil }
        app = host
        project = id
        macId = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "mac" }?.value
    }

    public var url: URL {
        var components = URLComponents()
        components.scheme = PairingPayload.scheme
        components.host = app
        components.path = "/\(project)"
        if let macId { components.queryItems = [URLQueryItem(name: "mac", value: macId)] }
        return components.url!
    }
}
