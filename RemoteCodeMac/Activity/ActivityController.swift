import AppKit
import Foundation
import RemoteCodeHost
import RemoteCodeKit

/// Memory, CPU and the apps behind them for the phone (capability `activity`, D-116).
///
/// Apps with a Dock icon are listed one by one (helpers rolled into their
/// app); everything else becomes one "system and background" row. Nothing is
/// sampled until a phone asks.
@MainActor
final class ActivityController {
    private let sampler = ProcessSampler()
    /// App ids of the latest snapshot → bundle path.
    private var quittable: [String: String] = [:]
    private let cores = Double(max(1, ProcessInfo.processInfo.activeProcessorCount))
    /// Apps that are never offered for quitting.
    private static let protectedBundleIdentifiers: Set<String> = ["com.apple.finder", "com.apple.loginwindow", "com.apple.dock"]

    func snapshot() async -> ActivitySnapshot {
        let sampler = sampler
        // CPU needs two samples; take a short first one when the last is stale.
        let stale = DispatchTime.now().uptimeNanoseconds - sampler.lastSampleTime > 10_000_000_000
        if sampler.lastSampleTime == 0 || stale {
            _ = await Task.detached(priority: .utility) { sampler.sample() }.value
            try? await Task.sleep(for: .seconds(1))
        }
        let (groups, system) = await Task.detached(priority: .utility) { sampler.sample() }.value

        let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        var visible: [String: NSRunningApplication] = [:]
        for app in running {
            if let path = app.bundleURL?.path { visible[path] = app }
        }
        let ownBundle = Bundle.main.bundlePath

        var apps: [AppActivity] = []
        var background = AppActivity(
            id: "background", name: String(localized: "System and background"), cpuPercent: 0, memoryBytes: 0, processCount: 0, canQuit: false
        )
        var ids: [String: String] = [:]
        for group in groups {
            let cpu = group.cpu / cores
            guard let path = group.bundlePath, let app = visible[path] else {
                background.cpuPercent += cpu
                background.memoryBytes += group.memory
                background.processCount += group.pids.count
                continue
            }
            let identifier = app.bundleIdentifier
            let id = identifier ?? path
            let canQuit = path != ownBundle && !Self.protectedBundleIdentifiers.contains(identifier ?? "")
            if canQuit { ids[id] = path }
            apps.append(AppActivity(
                id: id, name: app.localizedName ?? group.name, bundleIdentifier: identifier, cpuPercent: cpu,
                memoryBytes: group.memory, processCount: group.pids.count, canQuit: canQuit
            ))
        }
        quittable = ids
        apps.sort { $0.memoryBytes > $1.memoryBytes }
        return ActivitySnapshot(
            sampledAt: Date(), cpuPercent: system.cpu, memoryUsedBytes: system.memoryUsed, memoryTotalBytes: system.memoryTotal,
            pressure: system.pressure, apps: Array(apps.prefix(ActivitySnapshot.maximumApps)), background: background
        )
    }

    /// Asks the app to quit (or force quits it); only apps of the latest snapshot.
    func quit(_ request: QuitApp) throws {
        guard let path = quittable[request.appId] else {
            throw ErrorPayload(code: .notFound, message: String(localized: "This app can't be quit from your iPhone. Refresh the list and try again."))
        }
        let running = NSWorkspace.shared.runningApplications.filter { $0.bundleURL?.path == path }
        guard !running.isEmpty else {
            throw ErrorPayload(code: .notFound, message: String(localized: "The app is no longer running."))
        }
        for app in running {
            if request.force { app.forceTerminate() } else { app.terminate() }
        }
    }
}
