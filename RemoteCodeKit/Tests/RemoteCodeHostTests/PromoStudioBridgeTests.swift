import Foundation
import Testing
@testable import RemoteCodeHost
@testable import RemoteCodeKit

@Suite struct PromoStudioBridgeTests {
    @Test func reportsUnavailableWithoutControlFile() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let bridge = PromoStudioBridge(home: home)
        await #expect(throws: ErrorPayload.self) {
            _ = try await bridge.send(PromoStudioRequest(path: "/v1/state"))
        }
    }

    @Test func rejectsPathsOutsideTheAPI() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let dir = home.appendingPathComponent("Library/Application Support/Promo Studio")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(#"{"version":1,"port":1,"token":"t"}"#.utf8).write(to: dir.appendingPathComponent("control.json"))
        let bridge = PromoStudioBridge(home: home)
        for path in ["/etc/passwd", "/v1/media/../../control.json"] {
            do {
                _ = try await bridge.send(PromoStudioRequest(path: path))
                Issue.record("\(path) was forwarded")
            } catch let error as ErrorPayload {
                #expect(error.code == .invalidRequest)
            }
        }
    }
}

@Suite struct PromoStudioNotifierTests {
    @Test func turnsFinishedNoticesIntoAlerts() throws {
        let event = PromoStudioEvent(event: "finished", data: #"{"id":"P1","postId":"AB-12","kind":"produce","notice":"videoReady","title":"Launch film"}"#)
        let alert = try #require(PromoStudioNotifier.alert(for: event))
        #expect(alert.kind == .promoVideoReady)
        #expect(alert.sessionId == "AB-12")
        #expect(alert.folderName == "Launch film")
        #expect(AlertContent.english(for: alert, includeDetail: false).body == "Video ready · Launch film")
    }

    @Test func carriesTheErrorOfAFailedJob() throws {
        let event = PromoStudioEvent(event: "finished", data: #"{"id":"P1","notice":"failed","title":"","error":"Gemini quota is used up"}"#)
        let alert = try #require(PromoStudioNotifier.alert(for: event))
        #expect(alert.kind == .promoFailed)
        #expect(alert.folderName == "Promo Studio")
        #expect(alert.detail == "Gemini quota is used up")
    }

    @Test func ignoresJobsWithoutANoticeAndOtherEvents() {
        #expect(PromoStudioNotifier.alert(for: PromoStudioEvent(event: "finished", data: #"{"id":"P1","kind":"caption","title":"x"}"#)) == nil)
        #expect(PromoStudioNotifier.alert(for: PromoStudioEvent(event: "job", data: #"{"id":"P1","notice":"videoReady"}"#)) == nil)
        #expect(PromoStudioNotifier.alert(for: PromoStudioEvent(event: "finished", data: "not json")) == nil)
    }

    @Test func ntfyOpensThePostInThePromoStudioTab() {
        let publisher = NtfyPublisher(configuration: NtfyConfiguration(server: URL(string: "https://ntfy.sh")!, topic: "topic"), macId: "mac1")
        let message = publisher.message(for: HostAlert(kind: .promoStoryboardReady, sessionId: "AB-12", folderName: "Launch film"), includeDetail: false)
        let link = message.click.flatMap(URL.init(string:)).flatMap(PromoStudioLink.init(url:))
        #expect(link == PromoStudioLink(postId: "AB-12", macId: "mac1"))
        #expect(message.tags == ["memo"])
    }
}

@Suite struct PromoStudioLinkTests {
    @Test func roundTrips() throws {
        let link = PromoStudioLink(postId: "1F2E3D4C-0000-4000-8000-ABCDEF012345", macId: "abc")
        #expect(PromoStudioLink(url: link.url) == link)
        #expect(SessionLink(url: link.url) == nil)
    }

    @Test func rejectsOtherLinks() {
        #expect(PromoStudioLink(url: URL(string: "pilothouse://session/abc")!) == nil)
        #expect(PromoStudioLink(url: URL(string: "pilothouse://promostudio/post")!) == nil)
        #expect(PromoStudioLink(url: URL(string: "https://promostudio/post/abc")!) == nil)
    }
}
