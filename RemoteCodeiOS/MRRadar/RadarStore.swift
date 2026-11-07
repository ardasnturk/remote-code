import Foundation
import Observation
import RemoteCodeKit

struct RadarValue: Decodable, Identifiable, Hashable, Sendable {
    var date: Date
    var value: Double
    var id: Date { date }
}

struct RadarShare: Decodable, Identifiable, Hashable, Sendable {
    var name: String
    var fraction: Double
    var id: String { name }
}

struct RadarWeek: Decodable, Identifiable, Hashable, Sendable {
    var date: Date
    var gained: Double
    var lost: Double
    var id: Date { date }
}

struct RadarRetention: Decodable, Identifiable, Hashable, Sendable {
    var cohort: Date
    var size: Double
    var cells: [Double?]
    var id: Date { cohort }
}

struct RadarProject: Decodable, Hashable, Sendable {
    var id: String
    var name: String
    var iconURL: String?
    enum CodingKeys: String, CodingKey {
        case id, name
        case iconURL = "icon_url"
    }
}

struct RadarOverview: Decodable, Hashable, Sendable {
    var currency: String
    var mrr: Double
    var revenue28: Double
    var activeSubscriptions: Double
    var activeTrials: Double
    var newCustomers28: Double
}

struct RadarInsights: Decodable, Hashable, Sendable {
    var arr: Double
    var mrrChange30: Double?
    var quickRatio: Double?
    var arpu: Double?
    var monthlyChurn: Double?
    var impliedLTV: Double?
    var monthEndPace: Double?
    var lastMonth: Double?
    var trialConversion: Double?
    var trialPipelineMRR: Double?
    var forecast: [RadarValue]
}

/// A report from MRRadar on the Mac; the list leaves out the long series.
struct RadarReport: Decodable, Identifiable, Hashable, Sendable {
    var project: RadarProject
    var overview: RadarOverview
    var chartsUpdatedAt: Date?
    var revenueDaily: [RadarValue]
    var mrrDaily: [RadarValue]
    var movement: [RadarWeek]
    var retention: [RadarRetention]
    var countries: [RadarShare]
    var insights: RadarInsights
    var id: String { project.id }
}

struct RadarTotal: Decodable, Identifiable, Hashable, Sendable {
    var currency: String
    var mrr: Double
    var revenue28: Double
    var activeSubscriptions: Double
    var activeTrials: Double
    var mrrChange30: Double?
    var id: String { currency }
}

struct RadarPortfolio: Decodable, Hashable, Sendable {
    var totals: [RadarTotal]
    var reports: [RadarReport]
}

struct RadarAlertItem: Decodable, Identifiable, Hashable, Sendable {
    var id: String
    var kind: String
    var projectID: String
    var projectName: String
    var date: Date
}

/// The MRRadar tab (the plugin `mrradar`, D-119). The Mac holds the sign-in and does the
/// reading; the phone gets finished reports. Owned by `MacConnection`.
@MainActor
@Observable
final class RadarStore {
    private struct HostStatus: Decodable {
        var installed: Bool
    }
    private struct HubStatus: Decodable {
        var state: String
    }

    private(set) var isAvailable = false
    /// `ready`, `setup`, `missingCLI` or `signedOut`.
    private(set) var state = "ready"
    private(set) var portfolio: RadarPortfolio?
    private(set) var alerts: [RadarAlertItem] = []
    private(set) var loadError: String?
    var path: [String] = []

    @ObservationIgnored private weak var connection: MacConnection?
    @ObservationIgnored private var subscribed = false

    func attach(_ connection: MacConnection) {
        self.connection = connection
    }

    func connected(capabilities: Set<String>) async {
        subscribed = false
        guard capabilities.contains(HostCapability.mrradar),
              let status: HostStatus = try? await json("GET", "/host/status") else {
            isAvailable = false
            return
        }
        isAvailable = status.installed
        guard isAvailable else { return }
        await refresh()
        guard !subscribed, let client = connection?.client else { return }
        if (try? await client.request(.pluginSubscribe(PluginRef(plugin: PluginID.mrradar)))) != nil { subscribed = true }
    }

    func disconnected() {
        subscribed = false
    }

    func refresh() async {
        do {
            let status: HubStatus = try await json("GET", "/v1/status")
            state = status.state
            portfolio = try await json("GET", "/v1/portfolio")
            alerts = try await json("GET", "/v1/alerts")
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    func readAgain() async {
        _ = try? await call("POST", "/v1/refresh", body: "{}")
    }

    func report(_ id: String) async throws -> RadarReport {
        try await json("GET", "/v1/projects/\(id)")
    }

    func handle(_ event: PluginEvent) {
        guard event.plugin == PluginID.mrradar else { return }
        Task { await self.refresh() }
    }

    private func call(_ method: String, _ path: String, body: String? = nil) async throws -> PluginResponse {
        guard let client = connection?.client else { throw MacClientError.notConnected }
        let request = PluginRequest(plugin: PluginID.mrradar, method: method, path: path, body: body, timeout: 60)
        guard case .pluginResponse(let result) = try await client.request(.plugin(request), timeout: 70) else {
            throw MacClientError.unexpectedResponse("plugin")
        }
        return result
    }

    private func json<T: Decodable>(_ method: String, _ path: String) async throws -> T {
        try JSONDecoder().decode(T.self, from: try await call(method, path).body)
    }
}
