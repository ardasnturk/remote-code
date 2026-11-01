import AppKit
import CoreGraphics
import IOKit

/// Darkens the built-in display while the lid is closed in lid-closed mode (D-114).
///
/// With `pmset disablesleep 1` the built-in panel stays lit behind a closed
/// lid, which drains the battery and warms the Mac. While the lid is closed
/// the panel's brightness is held at 0; the saved value is put back when the
/// lid opens. The saved value is persisted, so a crash while closed cannot
/// leave the screen dark after the next launch.
///
/// Brightness can be raised behind our back (auto-brightness, an external
/// keyboard's brightness keys, display wake), so while closed it is checked
/// every second. Adapted from Perch's `LidDimmer` (MIT, see NOTICE).
@MainActor
final class ClosedLidDimmer {
    /// Called when the lid opens or closes.
    var onLidChange: (() -> Void)?

    private var enabled = false
    private var lastLidClosed: Bool?
    private var notifyPort: IONotificationPortRef?
    private var notifier: io_object_t = 0
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var timer: Timer?
    private var timerInterval: TimeInterval = 0
    private let defaults: UserDefaults

    private static let savedBrightnessKey = "lidSavedBrightness"
    /// `kIOPMMessageClamshellStateChange`
    private static let clamshellStateChange: UInt32 = 0xE003_4100

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// `nil` on Macs without a lid.
    var isLidClosed: Bool? { Self.readLidClosed() }

    /// Starts following the lid; restores a brightness saved before a crash.
    func start() {
        guard notifyPort == nil else { return }
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return }
        defer { IOObjectRelease(root) }
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        IONotificationPortSetDispatchQueue(port, .main)
        let result = IOServiceAddInterestNotification(
            port, root, kIOGeneralInterest,
            { refcon, _, type, _ in
                guard type == ClosedLidDimmer.clamshellStateChange, let refcon else { return }
                MainActor.assumeIsolated {
                    Unmanaged<ClosedLidDimmer>.fromOpaque(refcon).takeUnretainedValue().sync()
                }
            },
            Unmanaged.passUnretained(self).toOpaque(),
            &notifier
        )
        guard result == KERN_SUCCESS else {
            IONotificationPortDestroy(port)
            return
        }
        notifyPort = port

        // Display wake and reconfiguration can reset the panel's brightness.
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append((workspace, workspace.addObserver(
            forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.sync() }
        }))
        observers.append((NotificationCenter.default, NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.sync() }
        }))
        sync()
    }

    /// Stops following the lid and puts the saved brightness back.
    func stop() {
        setTimer(0)
        for (center, observer) in observers { center.removeObserver(observer) }
        observers.removeAll()
        if notifier != 0 {
            IOObjectRelease(notifier)
            notifier = 0
        }
        if let notifyPort {
            IONotificationPortDestroy(notifyPort)
            self.notifyPort = nil
        }
        restore()
    }

    /// Dims only while `enabled` (lid-closed mode active and dimming turned on).
    func setEnabled(_ enabled: Bool) {
        guard enabled != self.enabled else { return }
        self.enabled = enabled
        sync()
    }

    /// Idempotent: reads the real lid state and brings the brightness in line with it.
    private func sync() {
        let closed = Self.readLidClosed() ?? false
        if let last = lastLidClosed, last != closed {
            lastLidClosed = closed
            onLidChange?()
        } else {
            lastLidClosed = closed
        }
        if closed && enabled {
            holdDark()
            setTimer(1)
        } else {
            if !closed { restore() }
            // A slow poll catches a missed lid notification.
            setTimer(enabled ? 10 : 0)
        }
    }

    private func holdDark() {
        guard let display = Self.builtInDisplay() else { return }
        let current = Brightness.get(display)
        if defaults.object(forKey: Self.savedBrightnessKey) == nil, let current, current > 0.001 {
            defaults.set(Double(current), forKey: Self.savedBrightnessKey)
        }
        if current.map({ $0 > 0.001 }) ?? true {
            Brightness.set(display, 0)
        }
    }

    private func restore() {
        guard defaults.object(forKey: Self.savedBrightnessKey) != nil else { return }
        let value = Float(defaults.double(forKey: Self.savedBrightnessKey))
        defaults.removeObject(forKey: Self.savedBrightnessKey)
        guard let display = Self.builtInDisplay() else { return }
        Brightness.set(display, value)
        // The panel may still be powering up right after the lid opens; apply once more.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            guard Self.readLidClosed() != true else { return }
            Brightness.set(display, value)
        }
    }

    private func setTimer(_ interval: TimeInterval) {
        guard interval != timerInterval else { return }
        timer?.invalidate()
        timer = nil
        timerInterval = interval
        guard interval > 0 else { return }
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sync() }
        }
        timer.tolerance = interval * 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    nonisolated static func readLidClosed() -> Bool? {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return nil }
        defer { IOObjectRelease(root) }
        let value = IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
        return value as? Bool
    }

    private static func builtInDisplay() -> CGDirectDisplayID? {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &ids, &count) == .success else { return nil }
        return ids.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }
}

/// Built-in display brightness via the private DisplayServices framework,
/// loaded lazily. Every call fails softly when the symbols are missing.
private enum Brightness {
    private typealias GetFunction = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFunction = @convention(c) (CGDirectDisplayID, Float) -> Int32

    nonisolated(unsafe) private static let handle = dlopen(
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY
    )
    private static let getFunction: GetFunction? = handle.flatMap { dlsym($0, "DisplayServicesGetBrightness") }
        .map { unsafeBitCast($0, to: GetFunction.self) }
    private static let setFunction: SetFunction? = handle.flatMap { dlsym($0, "DisplayServicesSetBrightness") }
        .map { unsafeBitCast($0, to: SetFunction.self) }

    static func get(_ display: CGDirectDisplayID) -> Float? {
        var value: Float = 0
        guard let getFunction, getFunction(display, &value) == 0 else { return nil }
        return value
    }

    @discardableResult
    static func set(_ display: CGDirectDisplayID, _ value: Float) -> Bool {
        guard let setFunction else { return false }
        return setFunction(display, max(0, min(1, value))) == 0
    }
}
