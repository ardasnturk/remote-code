import Foundation

// Memory and CPU (capability `activity`, D-116).
//
// A plain answer to "why is my Mac slow?": memory pressure, CPU load and the
// apps behind them, with helper processes grouped into their app. The phone
// can quit an app of the latest snapshot.

/// The kernel's memory pressure level. Open-ended so newer Macs can add levels.
public struct MemoryPressure: RawRepresentable, Sendable, Hashable, Codable, CustomStringConvertible {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public var description: String { rawValue }

    public static let normal = MemoryPressure("normal")
    /// macOS starts compressing and swapping memory.
    public static let warning = MemoryPressure("warning")
    /// Memory is almost full; apps slow down or get killed.
    public static let critical = MemoryPressure("critical")
}

/// One app (with its helper processes) or the "system and background" rest.
public struct AppActivity: Sendable, Hashable, Codable, Identifiable {
    /// Opaque; valid for `quitApp` while the app runs.
    public var id: String
    public var name: String
    public var bundleIdentifier: String?
    /// Share of the whole Mac's CPU, 0–100 (all cores together).
    public var cpuPercent: Double
    /// Physical memory footprint of all its processes.
    public var memoryBytes: Int64
    public var processCount: Int
    /// The phone may offer "Quit" (not Remote Code itself, not the background rest).
    public var canQuit: Bool

    public init(
        id: String, name: String, bundleIdentifier: String? = nil, cpuPercent: Double, memoryBytes: Int64, processCount: Int,
        canQuit: Bool
    ) {
        self.id = id
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
        self.processCount = processCount
        self.canQuit = canQuit
    }
}

/// Mac → phone: response to `getActivity`.
public struct ActivitySnapshot: Sendable, Hashable, Codable {
    public var sampledAt: Date
    /// Whole Mac, 0–100.
    public var cpuPercent: Double
    /// Like Activity Monitor's "Memory Used": app + wired + compressed.
    public var memoryUsedBytes: Int64
    public var memoryTotalBytes: Int64
    public var pressure: MemoryPressure
    /// Apps with a Dock icon, largest memory first (at most `maximumApps`).
    public var apps: [AppActivity]
    /// Everything else together (`canQuit == false`).
    public var background: AppActivity?

    public init(
        sampledAt: Date, cpuPercent: Double, memoryUsedBytes: Int64, memoryTotalBytes: Int64, pressure: MemoryPressure,
        apps: [AppActivity], background: AppActivity?
    ) {
        self.sampledAt = sampledAt
        self.cpuPercent = cpuPercent
        self.memoryUsedBytes = memoryUsedBytes
        self.memoryTotalBytes = memoryTotalBytes
        self.pressure = pressure
        self.apps = apps
        self.background = background
    }

    public static let maximumApps = 20
}

/// Phone → Mac: quits an app of the latest snapshot; answered with `ok`.
public struct QuitApp: Sendable, Hashable, Codable {
    public var appId: String
    /// Force quit instead of asking the app to quit (unsaved changes are lost).
    public var force: Bool

    public init(appId: String, force: Bool = false) {
        self.appId = appId
        self.force = force
    }
}

extension ErrorCode {
    /// The host cannot report activity (e.g. a test host).
    public static let activityUnavailable = ErrorCode("activityUnavailable")
}

/// A Mac screen of the phone opened by a notification (D-115, D-116):
/// `pilothouse://storage?mac=<fingerprint>` or `pilothouse://activity?mac=…`.
public struct MacScreenLink: Sendable, Hashable {
    public enum Screen: String, Sendable, Hashable, CaseIterable, Identifiable {
        case storage
        case activity

        public var id: String { rawValue }
    }

    public var screen: Screen
    public var macId: String?

    public init(_ screen: Screen, macId: String? = nil) {
        self.screen = screen
        self.macId = macId
    }

    public init?(url: URL) {
        guard url.scheme?.lowercased() == PairingPayload.scheme,
              let screen = url.host.flatMap({ Screen(rawValue: $0.lowercased()) })
        else { return nil }
        self.screen = screen
        macId = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "mac" })?.value
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    public var url: URL {
        var components = URLComponents()
        components.scheme = PairingPayload.scheme
        components.host = screen.rawValue
        if let macId { components.queryItems = [URLQueryItem(name: "mac", value: macId)] }
        return components.url ?? URL(string: "\(PairingPayload.scheme)://\(screen.rawValue)")!
    }
}
