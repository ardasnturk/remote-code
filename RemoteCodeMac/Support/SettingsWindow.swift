import AppKit
import SwiftUI

/// Opens the Settings window in front of other apps. Remote Code is a menu bar
/// app (`LSUIElement`) and is not active when its menu is used, so
/// `SettingsLink` alone opens Settings behind the frontmost app.
@MainActor
enum SettingsWindow {
    static func show(using openSettings: OpenSettingsAction) {
        NSApp.activate()
        openSettings()
        // The window exists only after this run-loop turn.
        DispatchQueue.main.async {
            let window = NSApp.windows.first { $0.identifier?.rawValue == "com_apple_SwiftUI_Settings_window" }
                ?? NSApp.windows.first { $0.isVisible && $0.styleMask.contains(.titled) && !($0 is NSPanel) }
            window?.makeKeyAndOrderFront(nil)
            window?.orderFrontRegardless()
            NSApp.activate()
        }
    }
}
