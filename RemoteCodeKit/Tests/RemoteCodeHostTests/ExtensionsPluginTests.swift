import Foundation
import RemoteCodeKit
import Testing
@testable import RemoteCodeHost

@Suite struct ExtensionsPluginTests {
    private func home() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func aSwitchSurvivesARestart() async throws {
        let folder = try home()
        await ExtensionsPlugin(home: folder).setEnabled(PluginID.mrradar, false)
        let again = ExtensionsPlugin(home: folder)
        #expect(await again.isEnabled(PluginID.mrradar) == false)
        #expect(await again.isEnabled(PluginID.vitrin))
    }

    @Test func catalogNamesEveryExtensionOnce() {
        let ids = ExtensionsPlugin.catalog.map(\.id)
        #expect(Set(ids).count == 4)
        #expect(ExtensionsPlugin.catalog.allSatisfy { $0.website.hasPrefix("https://") })
    }

    @Test func refusesAnUnknownExtension() async throws {
        await #expect(throws: ErrorPayload.self) {
            try await ExtensionsPlugin(home: try home()).install("nothing")
        }
    }

    @Test func aNewerReleaseCountsAsAnUpdate() {
        var info = ExtensionInfo(id: "a", name: "A", website: "", installed: true, version: "0.9.0", latestVersion: "0.10.0", enabled: true, installing: false)
        #expect(info.hasUpdate)
        info.version = "0.10.0"
        #expect(!info.hasUpdate)
        info.installed = false
        info.version = nil
        #expect(!info.hasUpdate)
    }
}
