import Foundation
import Observation
import RemoteCodeKit

struct FunnelValue: Decodable, Identifiable, Hashable, Sendable {
    var date: Date
    var value: Double
    var id: Date { date }
}

struct FunnelStepInfo: Decodable, Identifiable, Hashable, Sendable {
    var event: String
    var count: Double
    var conversion: Double
    var id: String { event }
}

struct FunnelLeakInfo: Decodable, Hashable, Sendable {
    var fromEvent: String
    var toEvent: String
    var lost: Double
}

struct FunnelInfo: Decodable, Identifiable, Hashable, Sendable {
    var id: Int
    var name: String
    var steps: [FunnelStepInfo]
    var conversion: Double
    var previousConversion: Double?
    var leak: FunnelLeakInfo?
}

struct FunnelRetentionInfo: Decodable, Hashable, Sendable {
    var born: String
    var returning: String
    var d1: Double?
    var d7: Double?
    var d30: Double?
}

struct FunnelMover: Decodable, Identifiable, Hashable, Sendable {
    var event: String
    var thisWeek: Double
    var change: Double?
    var id: String { event }
}

struct FunnelInsights: Decodable, Hashable, Sendable {
    var activeUsers: Double?
    var activeChange: Double?
    var stickiness: Double?
}

struct FunnelProject: Decodable, Hashable, Sendable {
    var id: String
    var name: String
}

/// A report from FunnelRadar on the Mac; the list leaves out the long series.
struct FunnelProjectReport: Decodable, Identifiable, Hashable, Sendable {
    var project: FunnelProject
    var movers: [FunnelMover]
    var keyEvent: String?
    var dailyUsers: [FunnelValue]
    var funnels: [FunnelInfo]
    var retention: FunnelRetentionInfo?
    var insights: FunnelInsights
    var id: String { project.id }
}

struct FunnelPortfolio: Decodable, Hashable, Sendable {
    var reports: [FunnelProjectReport]
}

/// The FunnelRadar tab (the plugin `funnelradar`, D-120). Owned by `MacConnection`.
@MainActor
@Observable
final class FunnelStore {
    private struct HostStatus: Decodable {
        var installed: Bool
    }
    private struct HubStatus: Decodable {
        var state: String
    }

    private(set) var isAvailable = false
    /// `ready`, `setup`, `missingCLI` or `signedOut`.
    private(set) var state = "ready"
    private(set) var portfolio: FunnelPortfolio?
    private(set) var loadError: String?
    var path: [String] = []

    @ObservationIgnored private weak var connection: MacConnection?
    @ObservationIgnored private var subscribed = false

    func attach(_ connection: MacConnection) {
        self.connection = connection
    }

    func connected(capabilities: Set<String>) async {
        subscribed = false
        guard capabilities.contains(HostCapability.funnelradar),
              let status: HostStatus = try? await json("GET", "/host/status") else {
            isAvailable = false
            return
        }
        isAvailable = status.installed
        guard isAvailable else { return }
        await refresh()
        guard !subscribed, let client = connection?.client else { return }
        if (try? await client.request(.pluginSubscribe(PluginRef(plugin: PluginID.funnelradar)))) != nil { subscribed = true }
    }

    func disconnected() {
        subscribed = false
    }

    func refresh() async {
        do {
            let status: HubStatus = try await json("GET", "/v1/status")
            state = status.state
            portfolio = try await json("GET", "/v1/portfolio")
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    func report(_ id: String) async throws -> FunnelProjectReport {
        try await json("GET", "/v1/projects/\(id)")
    }

    func handle(_ event: PluginEvent) {
        guard event.plugin == PluginID.funnelradar else { return }
        Task { await self.refresh() }
    }

    private func json<T: Decodable>(_ method: String, _ path: String) async throws -> T {
        guard let client = connection?.client else { throw MacClientError.notConnected }
        let request = PluginRequest(plugin: PluginID.funnelradar, method: method, path: path, timeout: 60)
        guard case .pluginResponse(let result) = try await client.request(.plugin(request), timeout: 70) else {
            throw MacClientError.unexpectedResponse("plugin")
        }
        return try JSONDecoder().decode(T.self, from: result.body)
    }
}
