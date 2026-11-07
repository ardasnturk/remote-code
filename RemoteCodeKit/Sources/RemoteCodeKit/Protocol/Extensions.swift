import Foundation

/// One tool in Settings → Extensions (D-120), as the Mac sees it right now.
public struct ExtensionInfo: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var website: String
    public var installed: Bool
    public var version: String?
    /// The newest release on GitHub, once the Mac has looked.
    public var latestVersion: String?
    public var enabled: Bool
    /// True while the Mac is installing it.
    public var installing: Bool

    public init(id: String, name: String, website: String, installed: Bool, version: String?, latestVersion: String?, enabled: Bool, installing: Bool) {
        self.id = id
        self.name = name
        self.website = website
        self.installed = installed
        self.version = version
        self.latestVersion = latestVersion
        self.enabled = enabled
        self.installing = installing
    }

    /// True when GitHub has a newer version than the Mac.
    public var hasUpdate: Bool {
        guard installed, let version, let latestVersion else { return false }
        return version.compare(latestVersion, options: .numeric) == .orderedAscending
    }
}

extension PluginID {
    public static let funnelradar = "funnelradar"
    /// Not a tool: the list of tools, through the same messages.
    public static let extensions = "extensions"
    public static let promoStudio = "promoStudio"
}

extension HostCapability {
    public static let funnelradar = plugin(PluginID.funnelradar)
    public static let extensions = plugin(PluginID.extensions)
}
