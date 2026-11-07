import Foundation
import RemoteCodeKit
import Testing
@testable import RemoteCodeHost

@Suite struct LocalHubPluginTests {
    private func plugin(home: URL) -> LocalHubPlugin {
        LocalHubPlugin(.init(id: "radar", name: "Radar", bundle: "Radar.app", tool: "radar-hub", support: "Radar"), home: home)
    }

    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func statusWorksWithNoAppOnTheMac() async throws {
        let response = try await plugin(home: try folder()).send(PluginRequest(plugin: "radar", path: "/host/status"))
        #expect(response.status == 200)
        #expect(String(decoding: response.body, as: UTF8.self).contains("false"))
    }

    @Test func refusesPathsOutsideTheAPI() async throws {
        await #expect(throws: ErrorPayload.self) {
            try await plugin(home: try folder()).send(PluginRequest(plugin: "radar", path: "/v1/../secret"))
        }
    }

    @Test func aMissingAppIsReported() async throws {
        await #expect(throws: ErrorPayload.self) {
            try await plugin(home: try folder()).send(PluginRequest(plugin: "radar", path: "/v1/status"))
        }
    }

    @Test func findsTheToolInTheUsersApplicationsFolder() async throws {
        let home = try folder()
        let tool = home.appendingPathComponent("Applications/Radar.app/Contents/MacOS")
        try FileManager.default.createDirectory(at: tool, withIntermediateDirectories: true)
        let path = tool.appendingPathComponent("radar-hub").path
        FileManager.default.createFile(atPath: path, contents: Data(), attributes: [.posixPermissions: 0o755])
        #expect(await plugin(home: home).installedTool()?.hasSuffix("Radar.app/Contents/MacOS/radar-hub") == true)
    }

    @Test func readsAnAlertFromTheHub() {
        let alert = RevenueAlert.decode(#"{"id":"x","kind":"mrrDrop","projectID":"p","projectName":"Pulse","date":0,"value":12.5,"fraction":0.1,"currency":"USD"}"#)
        #expect(alert?.kind == "mrrDrop")
        #expect(alert?.projectName == "Pulse")
        #expect(alert?.showOnMac == nil)
    }

    @Test func radarLinkRoundTrips() {
        let link = RadarLink(project: "proj1", macId: "m")
        #expect(RadarLink(url: link.url) == link)
    }
}
