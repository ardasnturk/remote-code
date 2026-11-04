import RemoteCodeKit
import SwiftUI

/// Picks a folder on the Mac for a new project, with the browser the new-chat screen uses.
struct VitrinFolderPicker: View {
    let connection: MacConnection
    let choose: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var path: String?
    @State private var listing: DirectoryListing?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                if let listing {
                    Section {
                        Breadcrumb(listing: listing) { path = $0 }
                            .listRowBackground(Color.clear)
                    }
                    Section {
                        ForEach(listing.entries.filter(\.isDirectory), id: \.path) { entry in
                            FolderRow(entry: entry) { path = entry.path }
                        }
                    }
                } else if let error {
                    Text(error).foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(L.t("vitrin.chooseFolder"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.t("vitrin.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.t("vitrin.addThisFolder")) {
                        if let listing { choose(listing.path) }
                        dismiss()
                    }
                    .disabled(listing == nil)
                    .accessibilityIdentifier("vitrin.addFolder")
                }
            }
            .task(id: path) {
                do {
                    listing = try await connection.listDirectory(path, showHidden: false)
                    error = nil
                } catch {
                    self.error = error.localizedDescription
                }
            }
        }
    }
}
