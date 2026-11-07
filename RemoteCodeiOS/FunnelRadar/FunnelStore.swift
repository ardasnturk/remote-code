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
    var step: Int
    var fromEvent: String
    var toEvent: String
    var kept: Double
    var lost: Double
}

struct FunnelInfo: Decodable, Identifiable, Hashable, Sendable {
    var id: Int
    var name: String
    var steps: [FunnelStepInfo]
    var conversion: Double
    var previousConversion: Double?
    var entered: Double
    var leak: FunnelLeakInfo?
    var from: String
    var to: String

    var change: Double? {
        previousConversion.flatMap { $0 > 0 ? (conversion - $0) / $0 : nil }
    }
}

struct FunnelRetentionRow: Decodable, Identifiable, Hashable, Sendable {
    var week: Date
    var size: Double
    var cells: [Double?]
    var id: Date { week }
}

struct FunnelCurvePoint: Decodable, Identifiable, Hashable, Sendable {
    var day: Int
    var value: Double
    var id: Int { day }
}

struct FunnelRetentionInfo: Decodable, Hashable, Sendable {
    var born: String
    var returning: String
    var d1: Double?
    var d7: Double?
    var d30: Double?
    var days: [Int]
    var rows: [FunnelRetentionRow]
    var curve: [FunnelCurvePoint]
}

struct FunnelMover: Decodable, Identifiable, Hashable, Sendable {
    var event: String
    var thisWeek: Double
    var change: Double?
    var id: String { event }
}

struct FunnelTopEvent: Decodable, Identifiable, Hashable, Sendable {
    var event: String
    var count: Double
    var id: String { event }
}

struct FunnelAnomaly: Decodable, Identifiable, Hashable, Sendable {
    var date: Date
    var value: Double
    var expected: Double
    var id: Date { date }
}

struct FunnelInsights: Decodable, Hashable, Sendable {
    var activeUsers: Double?
    var activeChange: Double?
    var stickiness: Double?
    var stickinessMonth: Date?
    var stickinessByMonth: [FunnelValue]
    var weekdayIndex: [Double]
    var bestWeekday: Int?
    var trend: [FunnelValue]
}

struct FunnelProject: Decodable, Hashable, Sendable {
    var id: String
    var name: String
}

/// A report from FunnelRadar on the Mac; the list leaves out the long series.
struct FunnelProjectReport: Decodable, Identifiable, Hashable, Sendable {
    var project: FunnelProject
    var updatedAt: Date?
    var deepKey: String?
    var topEvents: [FunnelTopEvent]
    var movers: [FunnelMover]
    var keyEvent: String?
    var keyEventIsGuess: Bool
    var dailyUsers: [FunnelValue]
    var funnels: [FunnelInfo]
    var funnelCount: Int
    var retention: FunnelRetentionInfo?
    var anomalies: [FunnelAnomaly]
    var insights: FunnelInsights
    var id: String { project.id }
}

struct FunnelPortfolioMover: Decodable, Identifiable, Hashable, Sendable {
    var projectID: String
    var projectName: String
    var mover: FunnelMover
    var id: String { "\(projectID).\(mover.event)" }
}

struct FunnelPortfolioLeak: Decodable, Identifiable, Hashable, Sendable {
    var projectID: String
    var projectName: String
    var funnel: FunnelInfo
    var id: String { "\(projectID).\(funnel.id)" }
}

struct FunnelPortfolio: Decodable, Hashable, Sendable {
    var reports: [FunnelProjectReport]
    var movers: [FunnelPortfolioMover]
    var leaks: [FunnelPortfolioLeak]
    var updatedAt: Date?
}

struct FunnelAlertItem: Decodable, Identifiable, Hashable, Sendable {
    var id: String
    var kind: String
    var projectID: String
    var projectName: String
    var date: Date
    var subject: String
    var value: Double
    var baseline: Double
}

/// One project's daily users as an index, 100 = its own start.
struct FunnelIndexedSeries: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var points: [FunnelValue]

    /// A 7-day average over the last 90 days, as the Mac draws it. Nil under two weeks of data.
    static func make(_ report: FunnelProjectReport) -> FunnelIndexedSeries? {
        let days = Array(report.dailyUsers.suffix(96))
        guard days.count >= 14 else { return nil }
        let smooth = (6..<days.count).map { index in
            FunnelValue(date: days[index].date, value: days[(index - 6)...index].reduce(0) { $0 + $1.value } / 7)
        }
        guard let base = smooth.first?.value, base > 0 else { return nil }
        return FunnelIndexedSeries(
            id: report.id, name: report.project.name,
            points: smooth.map { FunnelValue(date: $0.date, value: $0.value / base * 100) }
        )
    }
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
    private(set) var alerts: [FunnelAlertItem] = []
    /// Full reports, which the comparison across projects needs.
    private(set) var reports: [String: FunnelProjectReport] = [:]
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
            let portfolio: FunnelPortfolio = try await json("GET", "/v1/portfolio")
            self.portfolio = portfolio
            alerts = try await json("GET", "/v1/alerts")
            for report in portfolio.reports {
                reports[report.id] = try? await self.report(report.id)
            }
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
