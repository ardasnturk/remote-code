import Foundation
import Testing
@testable import RemoteCodeHost
@testable import RemoteCodeKit

@Suite struct VitrinPluginTests {
    private func home() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    private func install(_ version: String, finished: Bool = true, in home: URL) throws {
        let folder = home.appendingPathComponent(".local/share/vitrin/\(version)")
        let dist = folder.appendingPathComponent("node_modules/@ardasnturk/vitrin/dist")
        try FileManager.default.createDirectory(at: dist, withIntermediateDirectories: true)
        try Data().write(to: dist.appendingPathComponent("bin.js"))
        if finished { try Data().write(to: folder.appendingPathComponent(".vitrin-installed")) }
    }

    @Test func saysWhenVitrinIsNotOnTheMac() async throws {
        let plugin = VitrinPlugin(home: home())
        let response = try await plugin.send(PluginRequest(plugin: PluginID.vitrin, path: "/host/status"))
        let status = try JSONSerialization.jsonObject(with: response.body) as? [String: Any]
        #expect(status?["installed"] as? Bool == false)
        do {
            _ = try await plugin.send(PluginRequest(plugin: PluginID.vitrin, path: "/v1/projects"))
            Issue.record("a request went through with no Vitrin")
        } catch let error as ErrorPayload {
            #expect(error.code == .pluginUnavailable)
        }
    }

    @Test func picksTheNewestFinishedInstall() async throws {
        let root = home()
        try install("2.0.1", in: root)
        try install("2.1.0", in: root)
        try install("2.10.0", finished: false, in: root)
        #expect(await VitrinPlugin(home: root).installedCLI()?.version == "2.1.0")
    }

    @Test func forwardsOnlyTheAPI() async throws {
        let plugin = VitrinPlugin(home: home())
        for path in ["/etc/passwd", "/v1/projects/../../control.json"] {
            do {
                _ = try await plugin.send(PluginRequest(plugin: PluginID.vitrin, path: path))
                Issue.record("\(path) was forwarded")
            } catch let error as ErrorPayload {
                #expect(error.code == .invalidRequest)
            }
        }
    }
}
