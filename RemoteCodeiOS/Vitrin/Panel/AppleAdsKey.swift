// Ported from Vitrin for Mac (apps/VitrinMac/VitrinMac/Core/AppleAdsKey.swift).
import Foundation

/// The Apple Ads API key pair lives on the Mac (the hub's `/v1/ads/keypair`); this reads what Apple shows afterwards.
enum AppleAdsKey {
    /// Where Vitrin keeps its keys on the Mac, under the home folder.
    static func keysFolder(home: String) -> String { home + "/Library/Application Support/Vitrin/keys" }

    /// Apple shows the three values as one block (`clientId SEARCHADS.…`, `teamId SEARCHADS.…`, `keyId …`): pasted
    /// whole into any of the fields, it fills all three.
    static func parse(block: String) -> (clientId: String, teamId: String, keyId: String)? {
        func value(_ name: String) -> String? {
            let pattern = "(?i)\(name)[\"'\\s:=]+([A-Za-z0-9._-]+)"
            guard let r = block.range(of: pattern, options: .regularExpression) else { return nil }
            return String(block[r]).replacingOccurrences(of: "(?i)^\(name)[\"'\\s:=]+", with: "", options: .regularExpression)
        }
        guard let c = value("clientId"), let t = value("teamId"), let k = value("keyId") else { return nil }
        return (c, t, k)
    }
}
