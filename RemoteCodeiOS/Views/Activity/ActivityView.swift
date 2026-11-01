import RemoteCodeKit
import SwiftUI

/// "Why is my Mac slow?": memory pressure, CPU and the apps behind them, with
/// a Quit button (capability `activity`, D-116). Refreshes every few seconds
/// while it is on screen; the Mac samples only when asked.
struct ActivityView: View {
    enum Sort: Hashable { case memory, cpu }

    let connection: MacConnection
    @State private var snapshot: ActivitySnapshot?
    @State private var sort: Sort = .memory
    @State private var appToQuit: AppActivity?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            if let snapshot {
                verdictSection(snapshot)
                Section {
                    Picker(selection: $sort) {
                        Text("Memory").tag(Sort.memory)
                        Text("CPU").tag(Sort.cpu)
                    } label: {
                        EmptyView()
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                Section {
                    ForEach(rows(snapshot)) { app in
                        row(app, snapshot: snapshot)
                    }
                } footer: {
                    Text("Helper processes are counted with their app. Swipe left on an app to quit it.")
                }
            } else {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            }
            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
        }
        .gradientBackground(intensity: 0.6)
        .navigationTitle(Text("Memory and CPU"))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            Text("Quit \(appToQuit?.name ?? "")?"),
            isPresented: Binding(get: { appToQuit != nil }, set: { if !$0 { appToQuit = nil } }),
            titleVisibility: .visible,
            presenting: appToQuit
        ) { app in
            Button("Quit") { Task { await quit(app, force: false) } }
            Button("Force Quit", role: .destructive) { Task { await quit(app, force: true) } }
        } message: { _ in
            Text("The app is asked to quit, so it can save your work. Force Quit stops it right away; unsaved changes are lost.")
        }
        .task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    // MARK: Sections

    private func verdictSection(_ snapshot: ActivitySnapshot) -> some View {
        let verdict = Self.verdict(snapshot)
        return Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: verdict.symbol)
                    .font(.title2)
                    .foregroundStyle(verdict.color)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verdict.title).font(.headline)
                    Text(verdict.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            gauge(
                title: Text("CPU"), value: snapshot.cpuPercent / 100,
                label: Text(Self.percent(snapshot.cpuPercent)), tint: snapshot.cpuPercent >= 70 ? .orange : Color.accentColor
            )
            gauge(
                title: Text("Memory"), value: Double(snapshot.memoryUsedBytes) / Double(max(snapshot.memoryTotalBytes, 1)),
                label: Text("\(snapshot.memoryUsedBytes.formatted(.byteCount(style: .memory))) of \(snapshot.memoryTotalBytes.formatted(.byteCount(style: .memory)))"),
                tint: snapshot.pressure == .critical ? .red : (snapshot.pressure == .warning ? .orange : Color.accentColor)
            )
        } header: {
            Text(verbatim: connection.mac.name)
        }
    }

    private func gauge(title: Text, value: Double, label: Text, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                title
                Spacer()
                label.foregroundStyle(.secondary).monospacedDigit()
            }
            ProgressView(value: min(max(value, 0), 1))
                .tint(tint)
        }
    }

    private func rows(_ snapshot: ActivitySnapshot) -> [AppActivity] {
        var apps = snapshot.apps
        switch sort {
        case .memory: apps.sort { $0.memoryBytes > $1.memoryBytes }
        case .cpu: apps.sort { $0.cpuPercent > $1.cpuPercent }
        }
        return Array(apps.prefix(10)) + (snapshot.background.map { [$0] } ?? [])
    }

    private func row(_ app: AppActivity, snapshot: ActivitySnapshot) -> some View {
        let share = sort == .memory
            ? Double(app.memoryBytes) / Double(max(snapshot.memoryTotalBytes, 1))
            : app.cpuPercent / 100
        return HStack(spacing: 12) {
            Image(systemName: app.id == Self.backgroundId ? "gearshape.2" : "app")
                .foregroundStyle(.secondary)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(verbatim: Self.name(of: app)).lineLimit(1)
                    Spacer()
                    Text(sort == .memory ? app.memoryBytes.formatted(.byteCount(style: .memory)) : Self.percent(app.cpuPercent))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                ProgressView(value: min(max(share, 0), 1))
                    .tint(Color.accentColor.opacity(0.7))
                if app.processCount > 1 {
                    Text("\(app.processCount) processes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .swipeActions {
            if app.canQuit {
                Button("Quit", role: .destructive) { appToQuit = app }
            }
        }
        .contextMenu {
            if app.canQuit {
                Button("Quit", systemImage: "xmark.circle") { appToQuit = app }
            }
        }
    }

    // MARK: Requests

    private func refresh() async {
        do {
            snapshot = try await connection.activity()
            errorMessage = nil
        } catch {
            errorMessage = (error as? ErrorPayload)?.message ?? error.localizedDescription
        }
    }

    private func quit(_ app: AppActivity, force: Bool) async {
        do {
            try await connection.quitApp(app.id, force: force)
            Haptics.success()
            try? await Task.sleep(for: .seconds(1))
            await refresh()
        } catch {
            errorMessage = (error as? ErrorPayload)?.message ?? error.localizedDescription
        }
    }

    // MARK: Verdict

    struct Verdict {
        var symbol: String
        var color: Color
        var title: String
        var detail: String
    }

    /// One plain sentence: is the Mac fine, and if not, who is responsible.
    static func verdict(_ snapshot: ActivitySnapshot) -> Verdict {
        let topMemory = snapshot.apps.filter(\.canQuit).max { $0.memoryBytes < $1.memoryBytes }
        let topCPU = snapshot.apps.filter(\.canQuit).max { $0.cpuPercent < $1.cpuPercent }
        if snapshot.pressure == .critical, let app = topMemory {
            return Verdict(
                symbol: "exclamationmark.octagon.fill", color: .red, title: String(localized: "Memory almost full"),
                detail: String(localized: "\(app.name) uses the most (\(app.memoryBytes.formatted(.byteCount(style: .memory)))). Quitting it frees memory right away.")
            )
        }
        if snapshot.pressure == .warning, let app = topMemory {
            return Verdict(
                symbol: "exclamationmark.triangle.fill", color: .orange, title: String(localized: "Memory under pressure"),
                detail: String(localized: "Your Mac may slow down. \(app.name) uses the most (\(app.memoryBytes.formatted(.byteCount(style: .memory)))).")
            )
        }
        if snapshot.cpuPercent >= 70, let app = topCPU {
            return Verdict(
                symbol: "flame.fill", color: .orange, title: String(localized: "Processor very busy"),
                detail: String(localized: "\(app.name) uses \(percent(app.cpuPercent)) of the processor.")
            )
        }
        return Verdict(
            symbol: "checkmark.seal.fill", color: .green, title: String(localized: "All good"),
            detail: String(localized: "Your Mac has room to work. Processor \(percent(snapshot.cpuPercent)), memory \(snapshot.memoryUsedBytes.formatted(.byteCount(style: .memory))) of \(snapshot.memoryTotalBytes.formatted(.byteCount(style: .memory))).")
        )
    }

    static let backgroundId = "background"

    /// The background row is named on the phone, in the phone's language.
    static func name(of app: AppActivity) -> String {
        app.id == backgroundId ? String(localized: "System and background") : app.name
    }

    static func percent(_ value: Double) -> String {
        (value / 100).formatted(.percent.precision(.fractionLength(value < 10 ? 1 : 0)))
    }
}
