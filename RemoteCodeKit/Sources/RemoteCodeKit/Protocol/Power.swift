import Foundation

// Power controls (capability `power`, D-114).
//
// The Mac always prevents idle system sleep while Remote Code runs. On top of
// that the phone can keep the display on, switch lid-closed mode and darken
// the built-in screen behind a closed lid.

/// The Mac's power settings and their effective state, in `MacStatus.power`.
public struct PowerStatus: Sendable, Hashable, Codable {
    /// Effective state of lid-closed mode.
    public enum LidMode: String, Sendable, Hashable, Codable {
        case off
        /// The helper must be allowed in System Settings → Login Items on the Mac.
        case needsApproval
        case active
        case pausedOnBattery
        case failed
    }

    /// The display is kept on (not only the system).
    public var keepsDisplayOn: Bool
    /// When "keep display on" turns itself off; `nil` = until turned off.
    public var displayOnUntil: Date?
    /// The lid-closed setting as chosen by the user.
    public var lidClosedModeEnabled: Bool
    public var lidMode: LidMode
    /// Why lid-closed mode failed (`lidMode == .failed`).
    public var lidError: String?
    public var pauseLidModeOnBattery: Bool
    /// Darken the built-in display while the lid is closed in lid-closed mode.
    public var dimsDisplayWhenLidClosed: Bool
    public var onBattery: Bool
    /// `nil` on Macs without a lid.
    public var lidClosed: Bool?

    public init(
        keepsDisplayOn: Bool, displayOnUntil: Date? = nil, lidClosedModeEnabled: Bool, lidMode: LidMode, lidError: String? = nil,
        pauseLidModeOnBattery: Bool, dimsDisplayWhenLidClosed: Bool, onBattery: Bool, lidClosed: Bool? = nil
    ) {
        self.keepsDisplayOn = keepsDisplayOn
        self.displayOnUntil = displayOnUntil
        self.lidClosedModeEnabled = lidClosedModeEnabled
        self.lidMode = lidMode
        self.lidError = lidError
        self.pauseLidModeOnBattery = pauseLidModeOnBattery
        self.dimsDisplayWhenLidClosed = dimsDisplayWhenLidClosed
        self.onBattery = onBattery
        self.lidClosed = lidClosed
    }
}

/// Phone → Mac: changes power settings; fields left `nil` stay as they are.
/// Answered with the new `macStatus`, which is also sent to every other phone.
public struct SetPower: Sendable, Hashable, Codable {
    public var keepDisplayOn: Bool?
    /// With `keepDisplayOn == true`: seconds until it turns itself off; `nil` or 0 = until turned off.
    public var displayOnDuration: TimeInterval?
    public var lidClosedMode: Bool?
    public var pauseLidModeOnBattery: Bool?
    public var dimDisplayWhenLidClosed: Bool?

    public init(
        keepDisplayOn: Bool? = nil, displayOnDuration: TimeInterval? = nil, lidClosedMode: Bool? = nil,
        pauseLidModeOnBattery: Bool? = nil, dimDisplayWhenLidClosed: Bool? = nil
    ) {
        self.keepDisplayOn = keepDisplayOn
        self.displayOnDuration = displayOnDuration
        self.lidClosedMode = lidClosedMode
        self.pauseLidModeOnBattery = pauseLidModeOnBattery
        self.dimDisplayWhenLidClosed = dimDisplayWhenLidClosed
    }

    /// Durations offered for "keep display on" (0 = until turned off).
    public static let displayOnDurations: [TimeInterval] = [0, 15 * 60, 3_600, 2 * 3_600, 4 * 3_600, 8 * 3_600]
}

extension ErrorCode {
    /// The Mac cannot change power settings (e.g. a test host).
    public static let powerUnavailable = ErrorCode("powerUnavailable")
}
