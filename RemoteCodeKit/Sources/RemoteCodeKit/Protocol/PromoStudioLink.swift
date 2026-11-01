import Foundation

/// `pilothouse://promostudio/post/<id>?mac=<fingerprint>`: opens a Promo Studio
/// post in the phone's Promo Studio tab (a tapped notification, D-113).
public struct PromoStudioLink: Sendable, Hashable {
    public static let host = "promostudio"

    public var postId: String
    public var macId: String?

    public init(postId: String, macId: String? = nil) {
        self.postId = postId
        self.macId = macId
    }

    /// Parses a `pilothouse://promostudio/post/<id>` link; `nil` for anything else.
    public init?(url: URL) {
        guard url.scheme?.lowercased() == PairingPayload.scheme, url.host?.lowercased() == Self.host else { return nil }
        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count == 2, components[0] == "post", SessionLink.isValidSessionId(components[1]) else { return nil }
        postId = components[1]
        macId = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "mac" })?.value
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    public var url: URL {
        var components = URLComponents()
        components.scheme = PairingPayload.scheme
        components.host = Self.host
        components.path = "/post/" + postId
        if let macId { components.queryItems = [URLQueryItem(name: "mac", value: macId)] }
        return components.url ?? URL(string: "\(PairingPayload.scheme)://\(Self.host)")!
    }
}
