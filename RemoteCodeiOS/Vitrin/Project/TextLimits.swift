// Ported from Vitrin for Mac (apps/VitrinMac/VitrinMac/Core/Limits.swift).
import Foundation

/// App Store Connect text limits (packages/schemas/src/limits.ts, Oct 2026). Keywords are measured in UTF-8 bytes.
enum TextLimits {
    struct Limit: Sendable {
        let max: Int
        let bytes: Bool
        let required: Bool
    }
    static let fields: [(key: String, limit: Limit)] = [
        ("name", Limit(max: 30, bytes: false, required: true)),
        ("subtitle", Limit(max: 30, bytes: false, required: false)),
        ("promotionalText", Limit(max: 170, bytes: false, required: false)),
        ("keywords", Limit(max: 100, bytes: true, required: true)),
        ("description", Limit(max: 4000, bytes: false, required: true)),
        ("whatsNew", Limit(max: 4000, bytes: false, required: false)),
    ]
    static func limit(_ key: String) -> Limit? { fields.first { $0.key == key }?.limit }
    /// The length App Store Connect counts: grapheme clusters, or UTF-8 bytes for the keyword field.
    static func length(_ text: String, _ limit: Limit) -> Int { limit.bytes ? text.utf8.count : text.count }
    static let maxScreenshots = 10
    static let maxPreviews = 3
}
