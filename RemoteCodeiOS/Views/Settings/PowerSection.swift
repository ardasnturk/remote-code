import RemoteCodeKit
import SwiftUI

/// The Mac's display and lid-closed settings (capability `power`, D-114).
struct PowerSection: View {
    let connection: MacConnection
    let power: PowerStatus
    @AppStorage("displayOnDuration") private var displayOnDuration: Double = 3_600
    @State private var isBusy = false
    @State private var errorMessage: String?

    var body: some View {
        Section {
            Toggle("Keep the display on", isOn: Binding(
                get: { power.keepsDisplayOn },
                set: { on in send(SetPower(keepDisplayOn: on, displayOnDuration: displayOnDuration)) }
            ))
            .accessibilityIdentifier("keepDisplayOnToggle")
            Picker("Duration", selection: Binding(
                get: { displayOnDuration },
                set: { duration in
                    displayOnDuration = duration
                    if power.keepsDisplayOn { send(SetPower(keepDisplayOn: true, displayOnDuration: duration)) }
                }
            )) {
                ForEach(SetPower.displayOnDurations, id: \.self) { duration in
                    Text(Self.durationName(duration)).tag(duration)
                }
            }
            if power.keepsDisplayOn, let until = power.displayOnUntil {
                LabeledContent("Turns off at") { Text(until, style: .time) }
            }

            Toggle("Stay awake with the lid closed", isOn: Binding(
                get: { power.lidClosedModeEnabled },
                set: { on in send(SetPower(lidClosedMode: on)) }
            ))
            .accessibilityIdentifier("lidClosedToggle")
            if power.lidClosedModeEnabled {
                lidStatus
                Toggle("Pause while on battery", isOn: Binding(
                    get: { power.pauseLidModeOnBattery },
                    set: { on in send(SetPower(pauseLidModeOnBattery: on)) }
                ))
                Toggle("Darken the built-in screen while the lid is closed", isOn: Binding(
                    get: { power.dimsDisplayWhenLidClosed },
                    set: { on in send(SetPower(dimDisplayWhenLidClosed: on)) }
                ))
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Power")
        } footer: {
            Text("Your Mac always stays awake while Remote Code runs; the display may still turn off. A closed MacBook that stays awake can get warm and drain its battery.")
        }
        .disabled(isBusy)
    }

    @ViewBuilder private var lidStatus: some View {
        switch power.lidMode {
        case .off:
            EmptyView()
        case .active:
            Group {
                if power.lidClosed == true {
                    Label("On · the lid is closed", systemImage: "checkmark.circle")
                } else {
                    Label("On", systemImage: "checkmark.circle")
                }
            }
            .font(.footnote)
            .foregroundStyle(.green)
        case .pausedOnBattery:
            Label("Paused while on battery. It resumes on power.", systemImage: "battery.50percent")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .needsApproval:
            Label("Allow the Remote Code helper on your Mac: System Settings → General → Login Items.", systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.orange)
        case .failed:
            Label(power.lidError ?? String(localized: "Lid-closed mode could not be turned on."), systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.red)
        }
    }

    private func send(_ request: SetPower) {
        isBusy = true
        errorMessage = nil
        Task {
            do {
                try await connection.setPower(request)
            } catch {
                errorMessage = (error as? ErrorPayload)?.message ?? error.localizedDescription
            }
            isBusy = false
        }
    }

    static func durationName(_ seconds: TimeInterval) -> String {
        guard seconds > 0 else { return String(localized: "Until turned off") }
        return Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .wide))
    }
}
