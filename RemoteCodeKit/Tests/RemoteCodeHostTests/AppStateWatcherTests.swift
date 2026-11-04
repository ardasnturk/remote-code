import Foundation
import RemoteCodeKit
import Synchronization
import Testing
@testable import RemoteCodeHost

private func document(_ state: String, version: String = "1.0") -> String {
    """
    warning: a line before the JSON
    {"data":[{"id":"100","attributes":{"name":"Ritim"},"relationships":{"appStoreVersions":{"data":[{"id":"v0"},{"id":"v1"}]}}}],
     "included":[{"id":"v0","type":"appStoreVersions","attributes":{"platform":"IOS","versionString":"0.9","appVersionState":"READY_FOR_DISTRIBUTION"}},
                 {"id":"v1","type":"appStoreVersions","attributes":{"platform":"IOS","versionString":"\(version)","appVersionState":"\(state)"}}]}
    """
}

private final class FakeVitrin: HostPlugin, Sendable {
    let output = Mutex<String?>(nil)
    func send(_ request: PluginRequest) async throws -> PluginResponse {
        guard let stdout = output.withLock({ $0 }) else { throw ErrorPayload(code: .pluginUnavailable, message: "no Vitrin") }
        let body = try JSONSerialization.data(withJSONObject: ["code": 0, "stdout": stdout, "stderr": ""] as [String: Any])
        return PluginResponse(status: 200, body: body)
    }
    func events() -> AsyncStream<PluginEvent> { AsyncStream { $0.finish() } }
}

private final class Sink: AlertSink, Sendable {
    let alerts = Mutex<[HostAlert]>([])
    func deliver(_ alert: HostAlert, includeDetail: Bool) async throws { alerts.withLock { $0.append(alert) } }
}

private func watcher(_ plugin: FakeVitrin, _ sink: Sink, enabled: Bool = true) async -> (AppStateWatcher, URL) {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let file = folder.appendingPathComponent("asc-watch.json")
    let service = NotificationService(hub: NotificationHub()) { _, _ in AsyncStream { $0.finish() } }
    await service.configure(NotificationPreferences(enabled: enabled), sinks: [sink])
    return (AppStateWatcher(plugin: plugin, notifications: service, file: file), file)
}

@Suite struct AppStateWatcherTests {
    @Test func theFirstLookOnlyRecords() async {
        let plugin = FakeVitrin(), sink = Sink()
        plugin.output.withLock { $0 = document("WAITING_FOR_REVIEW") }
        let (watcher, file) = await watcher(plugin, sink)
        await watcher.check()
        #expect(sink.alerts.withLock { $0.isEmpty })
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func aChangeIsToldOnce() async throws {
        let plugin = FakeVitrin(), sink = Sink()
        plugin.output.withLock { $0 = document("WAITING_FOR_REVIEW") }
        let (watcher, _) = await watcher(plugin, sink)
        await watcher.check()
        plugin.output.withLock { $0 = document("IN_REVIEW") }
        await watcher.check()
        await watcher.check()
        let alerts = sink.alerts.withLock { $0 }
        #expect(alerts.count == 1)
        let alert = try #require(alerts.first)
        #expect(alert.kind == .appStateChanged)
        #expect(alert.sessionId == "100")
        #expect(alert.folderName == "Ritim")
        #expect(alert.detail == "inReview")
    }

    @Test func aFailedReadKeepsTheLastLook() async {
        let plugin = FakeVitrin(), sink = Sink()
        plugin.output.withLock { $0 = document("WAITING_FOR_REVIEW") }
        let (watcher, _) = await watcher(plugin, sink)
        await watcher.check()
        plugin.output.withLock { $0 = nil }
        await watcher.check()
        plugin.output.withLock { $0 = document("REJECTED") }
        await watcher.check()
        #expect(sink.alerts.withLock { $0.map(\.detail) } == ["rejected"])
    }

    @Test func nothingIsReadWhileTheNotificationIsOff() async {
        let plugin = FakeVitrin(), sink = Sink()
        plugin.output.withLock { $0 = document("IN_REVIEW") }
        let (watcher, file) = await watcher(plugin, sink, enabled: false)
        await watcher.check()
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func theNewestVersionOfAPlatformCounts() throws {
        let snapshot = try #require(AppStates.snapshot(from: document("IN_REVIEW", version: "1.10")))
        #expect(snapshot["100/IOS"]?.version == "1.10")
        #expect(snapshot["100/IOS"]?.state == "IN_REVIEW")
        #expect(AppStates.snapshot(from: "not json") == nil)
    }

    @Test func onlyNewStagesAreNews() {
        func version(_ state: String, _ number: String = "1.0") -> [String: WatchedVersion] {
            ["a": WatchedVersion(appId: "1", name: "A", platform: "IOS", version: number, state: state)]
        }
        // Your own steps, and states between stages, stay quiet.
        #expect(AppStates.changes(from: version("READY_FOR_SALE"), to: version("PREPARE_FOR_SUBMISSION", "1.1")).isEmpty)
        #expect(AppStates.changes(from: version("IN_REVIEW"), to: version("PROCESSING_FOR_DISTRIBUTION")).isEmpty)
        // One stage, two states.
        #expect(AppStates.changes(from: version("ACCEPTED"), to: version("PENDING_DEVELOPER_RELEASE")).isEmpty)
        #expect(AppStates.changes(from: [:], to: version("IN_REVIEW")).isEmpty)
        #expect(AppStates.changes(from: version("PREPARE_FOR_SUBMISSION"), to: version("WAITING_FOR_REVIEW")).map(\.1) == [.waitingForReview])
        // A new release reaching the stage the last one ended in is news.
        #expect(AppStates.changes(from: version("READY_FOR_SALE"), to: version("READY_FOR_DISTRIBUTION", "1.1")).map(\.1) == [.live])
    }

    @Test func vitrinLinksRoundTrip() throws {
        let link = VitrinAppLink(appId: "6826548628", macId: "abc")
        #expect(VitrinAppLink(url: link.url) == link)
        #expect(VitrinAppLink(url: try #require(URL(string: "pilothouse://vitrin/app/../x"))) == nil)
    }
}
