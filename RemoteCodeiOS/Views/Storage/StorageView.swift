import RemoteCodeKit
import SwiftUI

/// Free space on the Mac and a cleanup of files that are safe to delete
/// (capability `storage`, D-115). The Mac decides what is safe; the phone
/// only picks from its list.
struct StorageView: View {
    let connection: MacConnection
    @State private var overview: StorageOverview?
    @State private var scan: CleanupScan?
    @State private var selected: Set<String> = []
    @State private var expanded: Set<String> = []
    @State private var isScanning = false
    @State private var isCleaning = false
    @State private var confirmCleanup = false
    @State private var result: CleanupResult?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            overviewSection
            if let result {
                Section {
                    Label(resultText(result), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
            if let scan {
                ForEach(scan.categories) { category in
                    categorySection(category)
                }
            } else {
                Section {
                    Button {
                        Task { await runScan() }
                    } label: {
                        HStack {
                            Label("Find Files to Clean Up", systemImage: "sparkles")
                            if isScanning {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isScanning)
                    .accessibilityIdentifier("scanCleanupButton")
                } footer: {
                    Text("Looks for caches, logs, Xcode build data, package caches, downloaded installers and the Trash. Apps create these again when they need them. Scanning large folders can take a minute.")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if scan != nil {
                cleanupBar
            }
        }
        .gradientBackground(intensity: 0.6)
        .navigationTitle(Text("Storage"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if scan != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await runScan() }
                    } label: {
                        Label("Scan Again", systemImage: "arrow.clockwise")
                    }
                    .disabled(isScanning || isCleaning)
                }
            }
        }
        .confirmationDialog(Text("Clean up \(selectedBytes.formatted(.byteCount(style: .file)))?"), isPresented: $confirmCleanup, titleVisibility: .visible) {
            Button("Move to Trash") { Task { await runCleanup(permanently: false) } }
            Button("Delete Permanently", role: .destructive) { Task { await runCleanup(permanently: true) } }
        } message: {
            Text("Moving to the Trash frees the space only after the Trash is emptied. Items in the Trash itself are always deleted permanently.")
        }
        .task { await loadOverview() }
        .refreshable { await loadOverview() }
    }

    // MARK: Sections

    @ViewBuilder private var overviewSection: some View {
        Section {
            if let overview, overview.totalBytes > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(overview.availableBytes.formatted(.byteCount(style: .file))) free")
                            .font(.title3.weight(.semibold))
                        Spacer()
                        Text("of \(overview.totalBytes.formatted(.byteCount(style: .file)))")
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: Double(overview.usedBytes), total: Double(overview.totalBytes))
                        .tint(overview.isLow ? .red : Color.accentColor)
                    if overview.isLow {
                        Label("Your Mac is running out of space. Agents may fail to build or save files.", systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.vertical, 4)
            } else {
                ProgressView()
            }
        } header: {
            Text(verbatim: connection.mac.name)
        }
    }

    private func categorySection(_ category: CleanupCategory) -> some View {
        Section {
            if let reason = category.unavailableReason {
                Label(reason, systemImage: "lock")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if category.items.isEmpty {
                Text("Nothing to clean up")
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    toggle(category)
                } label: {
                    HStack {
                        checkmark(isAllSelected(category) ? .all : (isPartlySelected(category) ? .some : .none))
                        Text(Self.title(of: category))
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(category.totalBytes.formatted(.byteCount(style: .file)))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .accessibilityIdentifier("cleanupCategory-\(category.id)")
                DisclosureGroup(isExpanded: Binding(
                    get: { expanded.contains(category.id) },
                    set: { if $0 { expanded.insert(category.id) } else { expanded.remove(category.id) } }
                )) {
                    ForEach(category.items) { item in
                        Button {
                            if selected.contains(item.id) { selected.remove(item.id) } else { selected.insert(item.id) }
                        } label: {
                            HStack {
                                checkmark(selected.contains(item.id) ? .all : .none)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: item.name)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(verbatim: item.location)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                Spacer()
                                Text(item.sizeBytes.formatted(.byteCount(style: .file)))
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                    if category.itemCount > category.items.count {
                        Text("And \(category.itemCount - category.items.count) smaller items")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } label: {
                    Text("\(category.itemCount) items")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var cleanupBar: some View {
        Button {
            confirmCleanup = true
        } label: {
            HStack {
                if isCleaning { ProgressView().tint(.white) }
                Text("Clean Up \(selectedBytes.formatted(.byteCount(style: .file)))")
                    .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .disabled(selected.isEmpty || isCleaning || isScanning)
        .padding()
        .background(.bar)
        .accessibilityIdentifier("cleanupButton")
    }

    private enum CheckState { case none, some, all }

    private func checkmark(_ state: CheckState) -> some View {
        let symbol = switch state {
        case .all: "checkmark.circle.fill"
        case .some: "minus.circle.fill"
        case .none: "circle"
        }
        return Image(systemName: symbol)
            .foregroundStyle(state == .none ? Color.secondary : Color.accentColor)
            .imageScale(.large)
            .accessibilityHidden(true)
    }

    // MARK: Selection

    private func isAllSelected(_ category: CleanupCategory) -> Bool {
        !category.items.isEmpty && category.items.allSatisfy { selected.contains($0.id) }
    }

    private func isPartlySelected(_ category: CleanupCategory) -> Bool {
        category.items.contains { selected.contains($0.id) }
    }

    private func toggle(_ category: CleanupCategory) {
        let ids = Set(category.items.map(\.id))
        if isAllSelected(category) { selected.subtract(ids) } else { selected.formUnion(ids) }
    }

    /// A fully selected category also takes the items the list did not show.
    private var selectedBytes: Int64 {
        guard let scan else { return 0 }
        return scan.categories.reduce(0) { total, category in
            if isAllSelected(category) { return total + category.totalBytes }
            return total + category.items.filter { selected.contains($0.id) }.reduce(0) { $0 + $1.sizeBytes }
        }
    }

    // MARK: Requests

    private func loadOverview() async {
        do {
            overview = try await connection.storageOverview()
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    private func runScan() async {
        isScanning = true
        errorMessage = nil
        defer { isScanning = false }
        do {
            let scan = try await connection.scanCleanup()
            self.scan = scan
            overview = scan.storage
            selected = Set(scan.categories.filter(\.selectedByDefault).flatMap { $0.items.map(\.id) })
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    private func runCleanup(permanently: Bool) async {
        guard let scan else { return }
        isCleaning = true
        errorMessage = nil
        defer { isCleaning = false }
        let whole = scan.categories.filter(isAllSelected)
        let wholeIds = Set(whole.map(\.id))
        let items = scan.categories.filter { !wholeIds.contains($0.id) }.flatMap { $0.items.filter { selected.contains($0.id) }.map(\.id) }
        do {
            let result = try await connection.runCleanup(RunCleanup(
                scanId: scan.scanId, itemIds: items, categoryIds: whole.map(\.id), permanently: permanently
            ))
            self.result = result
            overview = result.storage
            self.scan = nil
            selected = []
            Haptics.success()
        } catch {
            errorMessage = Self.message(for: error)
            if (error as? ErrorPayload)?.code == .scanExpired { self.scan = nil }
        }
    }

    private func resultText(_ result: CleanupResult) -> String {
        let freed = result.freedBytes.formatted(.byteCount(style: .file))
        var text = result.movedToTrash
            ? String(localized: "\(freed) moved to the Trash.")
            : String(localized: "\(freed) freed.")
        if result.failedCount > 0 {
            text += " " + String(localized: "\(result.failedCount) items were skipped because they are in use or protected.")
        }
        return text
    }

    static func message(for error: Error) -> String {
        (error as? ErrorPayload)?.message ?? error.localizedDescription
    }

    static func title(of category: CleanupCategory) -> String {
        switch category.id {
        case CleanupCategory.Kind.caches: String(localized: "App caches")
        case CleanupCategory.Kind.logs: String(localized: "Logs and crash reports")
        case CleanupCategory.Kind.xcode: String(localized: "Xcode leftovers")
        case CleanupCategory.Kind.developer: String(localized: "Developer package caches")
        case CleanupCategory.Kind.installers: String(localized: "Downloaded installers")
        case CleanupCategory.Kind.trash: String(localized: "Trash")
        default: category.title
        }
    }
}
