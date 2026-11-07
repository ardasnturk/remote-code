import RemoteCodeKit
import SwiftUI

private enum ExtensionText {
    static func summary(_ id: String) -> LocalizedStringKey {
        switch id {
        case PluginID.mrradar: "Subscription analytics, forecasts and alerts for your RevenueCat apps."
        case PluginID.funnelradar: "Funnel leaks, retention and alerts for your Mixpanel projects."
        case PluginID.vitrin: "App Store listings, screenshots and App Store Connect."
        default: "Short videos and posts, written and rendered with Claude Code."
        }
    }

    static func symbol(_ id: String) -> String {
        switch id {
        case PluginID.mrradar: "chart.line.uptrend.xyaxis"
        case PluginID.funnelradar: "line.3.horizontal.decrease.circle"
        case PluginID.vitrin: "storefront"
        default: "sparkles.tv"
        }
    }
}

struct ExtensionsView: View {
    let store: ExtensionsStore
    @State private var installing: Set<String> = []

    var body: some View {
        List {
            Section {
                if store.items.isEmpty, store.error == nil { ProgressView() }
                ForEach(store.items) { item in
                    row(item)
                }
            } footer: {
                Text("Extensions run on your Mac. Installing checks the download's checksum, its developer signature and Gatekeeper first. Turning one off hides its tab and stops its alerts.")
            }
            if let error = store.error {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
        }
        .navigationTitle("Extensions")
        .refreshable { await store.refresh() }
        .task { await store.refresh() }
    }

    @ViewBuilder private func row(_ item: ExtensionInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: ExtensionText.symbol(item.id))
                    .foregroundStyle(.tint)
                    .frame(width: 26)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(verbatim: item.name).fontWeight(.semibold)
                        if let version = item.version {
                            Text(verbatim: version).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text(ExtensionText.summary(item.id)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if item.installed {
                    Toggle("Enabled", isOn: Binding(get: { item.enabled }, set: { value in Task { await store.setEnabled(item.id, value) } }))
                        .labelsHidden()
                }
            }
            HStack(spacing: 14) {
                if item.installing || installing.contains(item.id) {
                    ProgressView()
                    Text("Installing on your Mac…").font(.caption).foregroundStyle(.secondary)
                } else if !item.installed {
                    Button("Install on Mac") { install(item) }.buttonStyle(.borderedProminent).controlSize(.small)
                } else if item.hasUpdate, let latest = item.latestVersion {
                    Button("Update to \(latest)") { install(item) }.buttonStyle(.bordered).controlSize(.small)
                }
                if let url = URL(string: item.website) {
                    Link("Website", destination: url).font(.caption)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func install(_ item: ExtensionInfo) {
        installing.insert(item.id)
        Task {
            await store.install(item.id)
            installing.remove(item.id)
        }
    }
}
