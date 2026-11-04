// Ported from Vitrin for Mac (apps/VitrinMac/VitrinMac/Core/AppleWebSession.swift).
import Foundation
import Observation

/// The Apple Account session behind `asc web`: what the public App Store Connect API cannot do (create an app, create
/// an API key, read the Analytics dashboards) goes through it. Nothing keeps the password: the hub hands it to asc for
/// one run, and asc stores it in the Mac's keychain after a successful sign-in.
///
/// A run outlives any one request, so the phone starts it (`POST /v1/asc/web`), reads its state and answers the
/// two-factor question (`POST /v1/asc/web/code`). The hub holds the waiting script the Mac app keeps itself.
@MainActor @Observable final class AppleWebSession {
    static let shared = AppleWebSession()

    private(set) var authenticated = false
    private(set) var appleID = ""
    /// asc holds the password in the keychain, so only the code may be needed.
    private(set) var passwordStored = false
    /// Apple sent a code and asc is waiting for it.
    private(set) var needsCode = false

    private struct RunState: Decodable {
        struct Output: Decodable {
            var code: Int
            var stdout: String
            var stderr: String
        }
        var running: Bool
        var needsCode: Bool
        var result: Output?
    }

    func refresh() async {
        guard let o = (try? await AscCLI.json(["web", "auth", "status"]))?.objectValue else { return }
        apply(status: o)
    }

    func apply(status o: [String: VitrinJSON]) {
        authenticated = o["authenticated"]?.boolValue ?? false
        appleID = o["appleId"]?.stringValue ?? appleID
        passwordStored = o["passwordStored"]?.boolValue ?? false
    }

    /// The form's code, for the run that is waiting.
    func submit(code: String) {
        let digits = code.filter(\.isNumber)
        guard !digits.isEmpty else { return }
        needsCode = false
        Task {
            guard let body = try? JSONSerialization.data(withJSONObject: ["code": digits]) else { return }
            _ = try? await AscCLI.store?.call("POST", "/v1/asc/web/code", body: String(decoding: body, as: UTF8.self))
        }
    }

    func signIn(appleID: String, password: String) async throws {
        let r = try await run(["web", "auth", "login", "--apple-id", appleID, "--output", "json"], password: password)
        guard r.ok else { throw AscCLI.Failure(message: r.errorLine.replacingOccurrences(of: "Error: ", with: "")) }
        await refresh()
    }

    /// One `asc web` run that may have to sign in again on the way; asc's own run ends after five minutes.
    func run(_ args: [String], password: String = "") async throws -> AscCLI.Result {
        guard let store = AscCLI.store else { throw VitrinError.notConnected }
        var request: [String: Any] = ["args": args]
        if !password.isEmpty { request["password"] = password }
        let body = try JSONSerialization.data(withJSONObject: request)
        let _: RunState = try await store.json("POST", "/v1/asc/web", body: String(decoding: body, as: UTF8.self))
        defer { needsCode = false }
        let deadline = Date.now.addingTimeInterval(330)
        var misses = 0
        while Date.now < deadline {
            try await Task.sleep(for: .milliseconds(700))
            let state: RunState
            do {
                state = try await store.json("GET", "/v1/asc/web", timeout: 20)
            } catch {
                // A dropped connection comes back; the run keeps going on the Mac meanwhile.
                misses += 1
                if misses >= 20 { throw error }
                continue
            }
            misses = 0
            needsCode = state.needsCode
            guard !state.running else { continue }
            guard let output = state.result else { throw AscCLI.Failure(message: L.t("web.failed")) }
            if output.code == 0 { AscCache.shared.markStale() }
            return AscCLI.Result(code: Int32(output.code), stdout: output.stdout, stderr: output.stderr)
        }
        throw AscCLI.Failure(message: L.t("web.failed"))
    }
}
