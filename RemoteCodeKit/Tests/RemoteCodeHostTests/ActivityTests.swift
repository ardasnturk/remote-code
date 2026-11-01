#if canImport(Darwin)
import Foundation
import RemoteCodeKit
import Testing
@testable import RemoteCodeHost

@Suite struct ActivityTests {
    @Test func samplerSeesThisProcessAndTheWholeMac() throws {
        let sampler = ProcessSampler()
        _ = sampler.sample()
        // Burn a little CPU so the second sample has something to measure.
        var x = 0.0
        for i in 0..<2_000_000 { x += sqrt(Double(i)) }
        #expect(x > 0)
        let (groups, system) = sampler.sample()
        let me = try #require(groups.first { $0.pids.contains(getpid()) })
        #expect(me.memory > 0)
        #expect(system.memoryTotal > 0)
        #expect(system.memoryUsed > 0 && system.memoryUsed <= system.memoryTotal)
        #expect((0...100).contains(system.cpu))
        // Every process is counted once.
        let pids = groups.flatMap(\.pids)
        #expect(Set(pids).count == pids.count)
    }

    @Test func memoryWarnsOncePerCriticalSpell() async {
        let monitor = MemoryMonitor(
            notifications: NotificationService(hub: NotificationHub()) { _, _ in AsyncStream { $0.finish() } },
            macName: { "Mac" }
        )
        #expect(await monitor.shouldWarn(.normal) == false)
        #expect(await monitor.shouldWarn(.critical) == true)
        #expect(await monitor.shouldWarn(.critical) == false)
        #expect(await monitor.shouldWarn(.warning) == false)
        #expect(await monitor.shouldWarn(.critical) == false)
        #expect(await monitor.shouldWarn(.normal) == false)
        #expect(await monitor.shouldWarn(.critical) == true)
    }
}
#endif
