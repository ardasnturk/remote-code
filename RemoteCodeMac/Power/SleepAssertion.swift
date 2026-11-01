import Foundation
import IOKit.pwr_mgt
import Synchronization

/// Keeps the Mac from idle-sleeping while Remote Code runs (prompt §4.3).
///
/// `.system` uses `kIOPMAssertionTypePreventUserIdleSystemSleep`: the display
/// may still turn off; only *system* sleep is prevented. `.display` also keeps
/// the display on ("Keep display on", D-114). The assertion is released in
/// `release()`, in `deinit`, and by the kernel when the process exits.
final class SleepAssertion: Sendable {
    enum Kind: Sendable {
        case system
        case display
    }

    private let kind: Kind
    private let assertion = Mutex<IOPMAssertionID?>(nil)

    init(_ kind: Kind = .system) {
        self.kind = kind
    }

    var isActive: Bool {
        assertion.withLock { $0 != nil }
    }

    @discardableResult
    func acquire() -> Bool {
        assertion.withLock { current in
            if current != nil { return true }
            var identifier = IOPMAssertionID(0)
            let reason: CFString = switch kind {
            case .system: "Remote Code keeps this Mac awake so your Claude Code sessions stay reachable from your phone." as CFString
            case .display: "Remote Code keeps the display on because you asked it to." as CFString
            }
            let type: CFString = switch kind {
            case .system: kIOPMAssertionTypePreventUserIdleSystemSleep as CFString
            case .display: kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString
            }
            let result = IOPMAssertionCreateWithName(
                type,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason,
                &identifier
            )
            guard result == kIOReturnSuccess else { return false }
            current = identifier
            return true
        }
    }

    func release() {
        assertion.withLock { current in
            if let identifier = current {
                IOPMAssertionRelease(identifier)
            }
            current = nil
        }
    }

    deinit {
        release()
    }
}
