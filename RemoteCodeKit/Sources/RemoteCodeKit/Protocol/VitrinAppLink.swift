import Foundation

/// `pilothouse://vitrin/app/<id>?mac=<fingerprint>`: opens an App Store Connect app
/// in the phone's Vitrin tab (a tapped notification, D-118).
public struct VitrinAppLink: Sendable, Hashable {
    public static let host = "vitrin"

    public var appId: String
    public var macId: String?

    public init(appId: String, macId: String? = nil) {
        self.appId = appId
        self.macId = macId
    }

    /// Parses a `pilothouse://vitrin/app/<id>` link; `nil` for anything else.
    public init?(url: URL) {
        guard url.scheme?.lowercased() == PairingPayload.scheme, url.host?.lowercased() == Self.host else { return nil }
        let components = url.pathComponents.filter { $0 != "/" }
        // App Store Connect's app IDs are numbers.
        guard components.count == 2, components[0] == "app", !components[1].isEmpty, components[1].allSatisfy(\.isNumber) else { return nil }
        appId = components[1]
        macId = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "mac" })?.value
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    public var url: URL {
        var components = URLComponents()
        components.scheme = PairingPayload.scheme
        components.host = Self.host
        components.path = "/app/" + appId
        if let macId { components.queryItems = [URLQueryItem(name: "mac", value: macId)] }
        return components.url ?? URL(string: "\(PairingPayload.scheme)://\(Self.host)")!
    }
}
