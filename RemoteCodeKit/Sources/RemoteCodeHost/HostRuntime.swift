import Foundation
import RemoteCodeKit

/// Supplies the Mac-specific parts of `MacStatus` (sleep, Tailscale, …).
public protocol MacStatusProviding: Sendable {
    func macStatus() async -> MacStatus
    /// Applies power settings from a phone (capability `power`).
    func setPower(_ request: SetPower) async throws -> MacStatus
    /// Memory, CPU and running apps (capability `activity`); needs AppKit, so the app supplies it.
    func activity() async throws -> ActivitySnapshot
    func quitApp(_ request: QuitApp) async throws
}

extension MacStatusProviding {
    public func setPower(_ request: SetPower) async throws -> MacStatus {
        throw ErrorPayload(code: .powerUnavailable, message: "This Mac cannot change its power settings remotely.")
    }

    public func activity() async throws -> ActivitySnapshot {
        throw ErrorPayload(code: .activityUnavailable, message: "This Mac cannot report its activity.")
    }

    public func quitApp(_ request: QuitApp) async throws {
        throw ErrorPayload(code: .activityUnavailable, message: "This Mac cannot quit apps remotely.")
    }
}

/// `HostService` backed by the real session manager and file system.
public struct MacHostService: HostService {
    let sessions: SessionManager
    let broker: PermissionBroker
    let hub: NotificationHub
    let notifications: NotificationService
    let insights: InsightsService
    let fileBrowser: FileBrowser
    let macId: String
    let serverVersion: String
    let status: any MacStatusProviding
    let promoStudioBridge = PromoStudioBridge()
    /// Tools on this Mac the phone can drive (D-117).
    let plugins: [String: any HostPlugin] = [
        PluginID.vitrin: VitrinPlugin(), PluginID.mrradar: Self.mrradar, PluginID.funnelradar: Self.funnelradar,
        PluginID.extensions: Self.extensions,
    ]
    static let funnelradar = LocalHubPlugin(.init(id: PluginID.funnelradar, name: "FunnelRadar", bundle: "FunnelRadar.app", tool: "funnelradar-hub", support: "FunnelRadar"))
    /// Settings → Extensions (D-120).
    public static let extensions = ExtensionsPlugin()
    static let mrradar = LocalHubPlugin(.init(id: PluginID.mrradar, name: "MRRadar", bundle: "MRRadar.app", tool: "mrradar-hub", support: "MRRadar"))
    let cleanup: CleanupService

    public func weeklySummary(_ request: GetWeeklySummary) async throws -> WeeklySummary {
        await insights.weeklySummary(request)
    }

    public func usageLimits() async -> [UsageLimits] {
        await insights.usageLimits()
    }

    public func listCommands(sessionId: String) async throws -> [CommandInfo] {
        try await sessions.commandCatalog(sessionId)
    }

    public func helloAck(for client: ClientContext) async -> HelloAck {
        HelloAck(
            macName: await status.macStatus().macName,
            macId: macId,
            serverVersion: serverVersion,
            pendingPermissions: await broker.pendingRequests,
            capabilities: HostCapability.all + [HostCapability.promoStudio] + plugins.keys.map(HostCapability.plugin)
        )
    }

    public func promoStudio(_ request: PromoStudioRequest) async throws -> PromoStudioResponse {
        try await promoStudioBridge.send(request)
    }

    public func promoStudioEvents() async throws -> AsyncStream<PromoStudioEvent> {
        promoStudioBridge.events()
    }

    public func plugin(_ request: PluginRequest) async throws -> PluginResponse {
        guard let plugin = plugins[request.plugin] else {
            throw ErrorPayload(code: .pluginUnavailable, message: "This Mac has no plugin named \(request.plugin).")
        }
        return try await plugin.send(request)
    }

    public func pluginEvents(_ plugin: String) async throws -> AsyncStream<PluginEvent> {
        guard let plugin = plugins[plugin] else {
            throw ErrorPayload(code: .pluginUnavailable, message: "This Mac has no such plugin.")
        }
        return plugin.events()
    }

    public func macStatus() async -> MacStatus {
        await status.macStatus()
    }

    public func setPower(_ request: SetPower) async throws -> MacStatus {
        try await status.setPower(request)
    }

    public func storageOverview() async throws -> StorageOverview {
        await cleanup.storageOverview()
    }

    public func scanCleanup() async throws -> CleanupScan {
        await cleanup.scan()
    }

    public func runCleanup(_ request: RunCleanup) async throws -> CleanupResult {
        try await cleanup.run(request)
    }

    public func activity() async throws -> ActivitySnapshot {
        try await status.activity()
    }

    public func quitApp(_ request: QuitApp) async throws {
        try await status.quitApp(request)
    }

    public func listDirectory(_ request: ListDirectory) async throws -> DirectoryListing {
        try fileBrowser.list(request)
    }

    public func createDirectory(_ request: CreateDirectory) async throws -> DirectoryListing {
        try fileBrowser.createDirectory(request)
    }

    public func listSessions() async -> [SessionSummary] {
        await sessions.summaries()
    }

    public func startSession(_ request: StartSession, from client: ClientContext) async throws -> SessionSummary {
        let summary = try await sessions.start(request)
        if request.firstMessage?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            await notifications.noteTurnFromPhone(summary.id)
        }
        return summary
    }

    public func resumeSession(id: String) async throws -> SessionSummary {
        try await sessions.resume(id)
    }

    public func updateSessionSettings(_ request: UpdateSessionSettings) async throws -> SessionSummary {
        try await sessions.updateSettings(request)
    }

    public func sendMessage(_ request: SendMessage, from client: ClientContext) async throws {
        await notifications.noteTurnFromPhone(request.sessionId)
        try await sessions.send(request)
    }

    public func interrupt(sessionId: String) async throws {
        try await sessions.interrupt(sessionId)
    }

    public func closeSession(id: String) async throws {
        try await sessions.close(id)
    }

    public func deleteSession(id: String) async throws {
        try await sessions.delete(id)
    }

    public func subscribe(sessionId: String, fromSeq: Int) async throws -> AsyncStream<SequencedEvent> {
        try await sessions.subscribe(sessionId, fromSeq: fromSeq)
    }

    public func respondToPermission(_ response: PermissionResponse, from client: ClientContext) async throws {
        try await broker.respond(response)
    }

    public func notifications() async -> AsyncStream<HostNotification> {
        await hub.stream()
    }
}

/// Composition root of the Mac host: wires sessions, permissions, pairing,
/// the local MCP permission server and the connection endpoint together.
///
/// The WebSocket listener (Network.framework) lives in the Mac app and hands
/// accepted transports to `endpoint.accept(_:)`.
public final class HostRuntime: Sendable {
    public let identity: IdentityKeyPair
    public let hub: NotificationHub
    public let broker: PermissionBroker
    public let sessions: SessionManager
    public let pairing: PairingManager
    public let devices: DeviceRegistry
    public let endpoint: ServerEndpoint
    public let fileBrowser: FileBrowser
    /// Native and ntfy notifications; configured by the app (D-095).
    public let notifications: NotificationService
    /// Announces finished Promo Studio videos through `notifications` (D-113).
    let promoStudioNotifier: PromoStudioNotifier
    /// Weekly summaries and usage limits (D-096, D-097); configured by the app.
    public let insights: InsightsService
    /// Safe-to-delete files (D-115).
    public let cleanup: CleanupService
    /// Warns when the startup volume runs low on space (D-115).
    let storageMonitor: StorageMonitor
    /// Tells when an app moves through App Review (D-118).
    let appStateWatcher: AppStateWatcher?
    let revenueAlertWatcher: RevenueAlertWatcher
    let funnelAlertWatcher: RevenueAlertWatcher
    #if canImport(Darwin)
    /// Warns when memory is almost full (D-116).
    let memoryMonitor: MemoryMonitor
    #endif
    private let mcpServer: LoopbackHTTPServer

    public convenience init(
        configuration: HostConfiguration,
        identity: IdentityKeyPair,
        serverVersion: String,
        status: any MacStatusProviding,
        macName: @escaping @Sendable () -> String,
        permissionTimeout: Duration = .seconds(600),
        launcher: @escaping @Sendable () async throws -> any ClaudeLauncher
    ) throws {
        try self.init(
            configuration: configuration, identity: identity, serverVersion: serverVersion, status: status,
            macName: macName, permissionTimeout: permissionTimeout,
            agentLauncher: { kind in
                guard kind == .claude else {
                    throw ErrorPayload(code: .agentNotInstalled, message: "\(kind.displayName) is not available on this Mac.")
                }
                return try await launcher()
            }
        )
    }

    public init(
        configuration: HostConfiguration,
        identity: IdentityKeyPair,
        serverVersion: String,
        status: any MacStatusProviding,
        macName: @escaping @Sendable () -> String,
        permissionTimeout: Duration = .seconds(600),
        agentLauncher: @escaping @Sendable (AgentKind) async throws -> any AgentLauncher
    ) throws {
        self.identity = identity
        let hub = NotificationHub()
        let broker = PermissionBroker(hub: hub, timeout: permissionTimeout)
        let sessions = SessionManager(configuration: configuration, broker: broker, hub: hub, agentLauncher: agentLauncher)
        let pairing = PairingManager()
        let devices = DeviceRegistry(
            url: configuration.dataDirectory.appendingPathComponent("devices.json"),
            pairing: pairing,
            hub: hub
        )
        let fileBrowser = FileBrowser(sandbox: PathSandbox(homeDirectory: configuration.homeDirectory))
        let notifications = NotificationService(hub: hub) { id, fromSeq in
            try await sessions.subscribe(id, fromSeq: fromSeq)
        }
        let insights = InsightsService(sessions: sessions, dataDirectory: configuration.dataDirectory)
        let cleanup = CleanupService(homeDirectory: configuration.homeDirectory)
        let service = MacHostService(
            sessions: sessions, broker: broker, hub: hub, notifications: notifications, insights: insights, fileBrowser: fileBrowser,
            macId: identity.fingerprint, serverVersion: serverVersion, status: status, cleanup: cleanup
        )
        let mcpEndpoint = MCPPermissionEndpoint(
            serverVersion: serverVersion,
            resolveToken: { token in await sessions.sessionId(forToken: token) },
            decide: { sessionId, tool, input, toolUseId in
                await sessions.decidePermission(sessionId: sessionId, tool: tool, input: input, toolUseId: toolUseId)
            },
            delegationAgents: { sessionId in await sessions.delegationAgents(for: sessionId) },
            delegate: { sessionId, arguments in
                let result = await sessions.delegate(sessionId: sessionId, arguments: arguments)
                let agent = AgentKind(arguments["agent"]?.stringValue ?? "")
                await notifications.post(HostAlert(
                    kind: result.isError ? .sessionFailed : .subagentFinished,
                    sessionId: sessionId,
                    folderName: await sessions.summary(sessionId)?.folderName ?? "~",
                    detail: "\(agent.displayName): \(result.text)"
                ))
                return result
            }
        )
        mcpServer = try LoopbackHTTPServer { request in await mcpEndpoint.handle(request) }
        self.hub = hub
        self.broker = broker
        self.sessions = sessions
        self.pairing = pairing
        self.devices = devices
        self.fileBrowser = fileBrowser
        self.notifications = notifications
        promoStudioNotifier = PromoStudioNotifier(bridge: PromoStudioBridge(), notifications: notifications)
        self.insights = insights
        self.cleanup = cleanup
        storageMonitor = StorageMonitor(home: configuration.homeDirectory, notifications: notifications, macName: macName)
        appStateWatcher = service.plugins[PluginID.vitrin].map {
            AppStateWatcher(plugin: $0, notifications: notifications, file: AppStateWatcher.defaultFile(home: URL(fileURLWithPath: configuration.homeDirectory)))
        }
        revenueAlertWatcher = RevenueAlertWatcher(plugin: MacHostService.mrradar, notifications: notifications)
        funnelAlertWatcher = RevenueAlertWatcher(plugin: MacHostService.funnelradar, notifications: notifications)
        #if canImport(Darwin)
        memoryMonitor = MemoryMonitor(notifications: notifications, macName: macName)
        #endif
        endpoint = ServerEndpoint(identity: identity, macName: macName, authorizer: devices, service: service)
    }

    /// Port of the local permission server (127.0.0.1).
    public var permissionServerPort: Int { mcpServer.port }

    /// Loads sessions and enables permission forwarding.
    public func start() async {
        let limitStore = insights.limits
        await sessions.setUsageSink { limits in await limitStore.update(limits) }
        await notifications.start()
        await promoStudioNotifier.start()
        await storageMonitor.start()
        await appStateWatcher?.start()
        await revenueAlertWatcher.start()
        await funnelAlertWatcher.start()
        #if canImport(Darwin)
        await memoryMonitor.start()
        #endif
        await sessions.setPermissionServerPort(mcpServer.port)
        await sessions.bootstrap()
    }

    /// Stops every CLI and closes all connections.
    public func shutdown() async {
        await endpoint.disconnectAll(reason: ErrorPayload(code: .internalError, message: "Remote Code on the Mac is quitting."))
        await sessions.shutdown()
        await notifications.stop()
        await promoStudioNotifier.stop()
        await storageMonitor.stop()
        await appStateWatcher?.stop()
        await revenueAlertWatcher.stop()
        await funnelAlertWatcher.stop()
        #if canImport(Darwin)
        await memoryMonitor.stop()
        #endif
        mcpServer.stop()
    }

    /// Builds the QR payload for a new pairing.
    public func makePairingPayload(macName: String, localAddresses: [String], tailscale: TailscaleStatus, port: Int) async -> PairingPayload {
        let (token, expiresAt) = await pairing.createToken()
        return PairingPayload(
            name: macName,
            publicKey: identity.publicKey,
            localAddresses: localAddresses,
            tailscaleAddresses: [tailscale.ipv4].compactMap { $0 },
            magicDNSName: tailscale.magicDNSName,
            port: port,
            token: token,
            expiresAt: expiresAt
        )
    }
}
