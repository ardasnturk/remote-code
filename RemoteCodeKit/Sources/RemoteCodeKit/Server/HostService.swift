import Foundation

/// The authenticated phone on the other end of a connection.
public struct ClientContext: Sendable, Hashable {
    public var deviceId: String
    public var deviceName: String
    public var platform: String
    public var appVersion: String

    public init(deviceId: String, deviceName: String, platform: String, appVersion: String) {
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.platform = platform
        self.appVersion = appVersion
    }
}

/// Server-initiated messages fanned out to every connected client.
public enum HostNotification: Sendable {
    case sessionStarted(SessionSummary)
    case sessionUpdated(SessionSummary)
    case sessionDeleted(String)
    case sessionEnded(SessionEnded)
    case permissionRequest(PermissionRequest)
    case permissionResolved(PermissionResolved)
    case macStatus(MacStatus)
    /// Drop the connection(s) of a device, e.g. after it was revoked.
    case disconnectDevice(deviceId: String, reason: ErrorPayload)
}

/// Everything a connected phone can ask the Mac to do.
///
/// Implemented by the real Mac host (`RemoteCodeHost`) and by `DemoHostService`.
/// Methods throw `ErrorPayload` for user-presentable failures.
public protocol HostService: Sendable {
    func helloAck(for client: ClientContext) async -> HelloAck
    func macStatus() async -> MacStatus
    func listDirectory(_ request: ListDirectory) async throws -> DirectoryListing
    /// Creates a folder and returns the listing of its parent.
    func createDirectory(_ request: CreateDirectory) async throws -> DirectoryListing
    func weeklySummary(_ request: GetWeeklySummary) async throws -> WeeklySummary
    func usageLimits() async -> [UsageLimits]
    /// Skills and slash commands of a session's agent, with descriptions.
    func listCommands(sessionId: String) async throws -> [CommandInfo]
    func listSessions() async -> [SessionSummary]
    func startSession(_ request: StartSession, from client: ClientContext) async throws -> SessionSummary
    func resumeSession(id: String) async throws -> SessionSummary
    /// Changes a chat's model and/or effort; returns the updated summary.
    func updateSessionSettings(_ request: UpdateSessionSettings) async throws -> SessionSummary
    func sendMessage(_ request: SendMessage, from client: ClientContext) async throws
    func interrupt(sessionId: String) async throws
    func closeSession(id: String) async throws
    func deleteSession(id: String) async throws
    /// Persisted events with `seq >= fromSeq`, then live events (including
    /// ephemeral ones) until the stream is cancelled.
    func subscribe(sessionId: String, fromSeq: Int) async throws -> AsyncStream<SequencedEvent>
    func respondToPermission(_ response: PermissionResponse, from client: ClientContext) async throws
    /// A fresh stream of notifications for one connection.
    func notifications() async -> AsyncStream<HostNotification>
    /// Forwards a request to the Promo Studio app's local API (capability `promoStudio`).
    func promoStudio(_ request: PromoStudioRequest) async throws -> PromoStudioResponse
    /// Promo Studio's server-sent events until the stream is cancelled.
    func promoStudioEvents() async throws -> AsyncStream<PromoStudioEvent>
    /// Changes power settings and returns the new status (capability `power`).
    func setPower(_ request: SetPower) async throws -> MacStatus
}

extension HostService {
    public func promoStudio(_ request: PromoStudioRequest) async throws -> PromoStudioResponse {
        throw ErrorPayload(code: .promoStudioUnavailable, message: "Promo Studio is not available on this Mac.")
    }

    public func promoStudioEvents() async throws -> AsyncStream<PromoStudioEvent> {
        throw ErrorPayload(code: .promoStudioUnavailable, message: "Promo Studio is not available on this Mac.")
    }

    public func setPower(_ request: SetPower) async throws -> MacStatus {
        throw ErrorPayload(code: .powerUnavailable, message: "This Mac cannot change its power settings remotely.")
    }
}

/// Decides whether a handshake may proceed and records successful connections.
public protocol PeerAuthorizer: Sendable {
    func authorize(publicKey: Data, hello: ClientHandshakePayload) async -> HandshakeDecision
    func peerConnected(deviceId: String, hello: ClientHandshakePayload) async
    func peerDisconnected(deviceId: String) async
}
