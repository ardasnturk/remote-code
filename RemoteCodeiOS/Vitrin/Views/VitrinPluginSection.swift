import SwiftUI

/// Settings → Plugins: Vitrin on the Mac, and the way to add it.
struct VitrinPluginSection: View {
    let store: VitrinStore
    @State private var error: String?

    var body: some View {
        Section {
            if store.isAvailable {
                LabeledContent("Vitrin", value: store.installedVersion ?? "")
            } else if store.isInstalling {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Installing Vitrin on your Mac…")
                }
            } else {
                Button("Install Vitrin on your Mac") {
                    Task {
                        do {
                            error = nil
                            try await store.install()
                        } catch {
                            self.error = error.localizedDescription
                        }
                    }
                }
                .accessibilityIdentifier("vitrinInstall")
            }
            if let error {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
        } header: {
            Text("Plugins")
        } footer: {
            Text("Vitrin builds your App Store listing and runs App Store Connect from a tab here. It downloads about 450 MB to your Mac once.")
        }
    }
}
