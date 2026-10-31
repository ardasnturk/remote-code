import Foundation
import Testing
@testable import RemoteCodeHost
@testable import RemoteCodeKit

@Suite struct AutomatBridgeTests {
    @Test func reportsUnavailableWithoutControlFile() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let bridge = AutomatBridge(home: home)
        await #expect(throws: ErrorPayload.self) {
            _ = try await bridge.send(AutomatRequest(path: "/v1/state"))
        }
    }

    @Test func rejectsPathsOutsideTheAPI() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let dir = home.appendingPathComponent("Library/Application Support/Automat")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(#"{"version":1,"port":1,"token":"t"}"#.utf8).write(to: dir.appendingPathComponent("control.json"))
        let bridge = AutomatBridge(home: home)
        for path in ["/etc/passwd", "/v1/media/../../control.json"] {
            do {
                _ = try await bridge.send(AutomatRequest(path: path))
                Issue.record("\(path) was forwarded")
            } catch let error as ErrorPayload {
                #expect(error.code == .invalidRequest)
            }
        }
    }
}
