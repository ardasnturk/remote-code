// Ported from Vitrin for Mac (apps/VitrinMac/VitrinMac/Core/Credentials.swift).
import Foundation
import Observation

/// The App Store Connect API key the Mac holds once for every project. The phone keeps none of it: the .p8 goes to the
/// hub (`/v1/asc/key`), which stores it where Vitrin for Mac does, and only the ids come back.
@MainActor @Observable final class ASCCredentials {
    struct Key: Codable, Equatable, Sendable {
        var keyId: String
        var issuerId: String
    }

    struct SaveError: LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }

    private(set) var key: Key?
    @ObservationIgnored weak var store: VitrinStore?

    var isSet: Bool { key != nil }

    func refresh() async {
        guard let store else { return }
        do {
            // The hub answers `null` when no key is stored.
            let found: Key? = try await store.json("GET", "/v1/asc/key")
            key = found
        } catch {
            return
        }
    }

    /// Sends the ids and the text of a .p8 to the Mac.
    func save(keyId: String, issuerId: String, p8: String) async throws {
        let id = keyId.trimmingCharacters(in: .whitespacesAndNewlines)
        let issuer = issuerId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !issuer.isEmpty else { throw SaveError(message: L.t("settings.keyInvalid")) }
        guard p8.contains("PRIVATE KEY-----") else { throw SaveError(message: L.t("settings.keyNotP8")) }
        guard let store else { throw VitrinError.notConnected }
        let body = try JSONSerialization.data(withJSONObject: ["keyId": id, "issuerId": issuer, "p8": p8])
        key = try await store.json("POST", "/v1/asc/key", body: String(decoding: body, as: UTF8.self))
    }

    /// Forgets the key and deletes the stored .p8 on the Mac.
    func clear() async throws {
        guard let store else { throw VitrinError.notConnected }
        try await store.call("DELETE", "/v1/asc/key")
        key = nil
    }
}
