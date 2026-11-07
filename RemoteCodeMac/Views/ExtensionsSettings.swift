import AppKit
import RemoteCodeHost
import RemoteCodeKit
import SwiftUI

/// What each extension is for, in the reader's language.
enum ExtensionText {
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
        case PluginID.funnelradar: "line.3.horizontal.decrease.circle.fill"
        case PluginID.vitrin: "storefront.fill"
        default: "sparkles.tv.fill"
        }
    }

    static func colors(_ id: String) -> [Color] {
        switch id {
        case PluginID.mrradar: [.green, Brand.teal]
        case PluginID.funnelradar: [Brand.indigo, Brand.violet]
        case PluginID.vitrin: [.orange, .pink]
        default: [Brand.violet, .pink]
        }
    }
}

struct ExtensionsSettings: View {
    @State private var items: [ExtensionInfo] = []
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                if items.isEmpty { ProgressView() }
                ForEach(items) { item in
                    ExtensionRow(item: item) { await install(item) } onToggle: { value in
                        await MacHostService.extensions.setEnabled(item.id, value)
                        await reload()
                    }
                }
            } footer: {
                Text("Installing checks the download's checksum, its developer signature and Gatekeeper first. Turning one off hides its tab on your iPhone and stops its alerts.")
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
        }
        .formStyle(.grouped)
        .task { await reload() }
    }

    private func reload() async {
        items = await MacHostService.extensions.list()
    }

    private func install(_ item: ExtensionInfo) async {
        error = nil
        let task = Task { try await MacHostService.extensions.install(item.id) }
        try? await Task.sleep(for: .milliseconds(100))
        await reload()
        do {
            try await task.value
        } catch {
            self.error = (error as? ErrorPayload)?.message ?? error.localizedDescription
        }
        await reload()
    }
}

private struct ExtensionRow: View {
    let item: ExtensionInfo
    let onInstall: () async -> Void
    let onToggle: (Bool) async -> Void

    init(item: ExtensionInfo, onInstall: @escaping () async -> Void, onToggle: @escaping (Bool) async -> Void) {
        self.item = item
        self.onInstall = onInstall
        self.onToggle = onToggle
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IconBadge(symbol: ExtensionText.symbol(item.id), colors: ExtensionText.colors(item.id), size: 34)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(verbatim: item.name).fontWeight(.semibold)
                    if let version = item.version {
                        Text(verbatim: version).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(ExtensionText.summary(item.id)).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    if item.installing {
                        ProgressView().controlSize(.small)
                        Text("Installing…").font(.caption).foregroundStyle(.secondary)
                    } else if !item.installed {
                        Button("Install") { Task { await onInstall() } }
                    } else {
                        Button("Open") { open() }
                        if item.hasUpdate, let latest = item.latestVersion {
                            Button("Update to \(latest)") { Task { await onInstall() } }
                        }
                    }
                    if let url = URL(string: item.website) {
                        Link("Website", destination: url).font(.caption)
                    }
                }
                .padding(.top, 3)
            }
            Spacer()
            if item.installed {
                Toggle("Enabled", isOn: Binding(get: { item.enabled }, set: { value in Task { await onToggle(value) } }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 3)
    }

    private func open() {
        let bundle = item.name + ".app"
        let folders = ["/Applications", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path]
        if let path = folders.map({ "\($0)/\(bundle)" }).first(where: { FileManager.default.fileExists(atPath: $0) }) {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        }
    }
}
