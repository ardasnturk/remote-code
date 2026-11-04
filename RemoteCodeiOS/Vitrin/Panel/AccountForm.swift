// Ported from Vitrin for Mac (apps/VitrinMac/VitrinMac/Views/OnboardingView.swift, AccountForm).
import SwiftUI

/// The App Store Connect key: the form when none is stored, a summary with the team's app count when one is. The .p8
/// comes from Files on the phone and goes to the Mac (`/v1/asc/key`); saving reads the team's apps with it, the check.
struct AccountForm: View {
    @Environment(VitrinPanelModel.self) private var model
    @State private var keyId = ""
    @State private var issuerId = ""
    @State private var p8: String?
    @State private var p8Name: String?
    @State private var picking = false
    @State private var saving = false
    @State private var error: String?
    @State private var editing = false
    @State private var confirmRemove = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let k = model.credentials.key, !editing {
                HStack(alignment: .top, spacing: 12) {
                    VitrinBadge(symbol: "checkmark", colors: BadgeColors.fresh, size: 28)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L.t("onb.account.saved")).font(.headline)
                        Text(verbatim: "Key ID \(k.keyId) · Issuer \(k.issuerId.prefix(8))…").font(.callout.monospaced()).foregroundStyle(.secondary)
                        check
                    }
                }
                HStack {
                    Button(L.t("onb.account.change")) { editing = true }.buttonStyle(.bordered)
                    Button(L.t("settings.removeKey"), role: .destructive) { confirmRemove = true }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("settings.removeKey")
                }
                if let error { failure(error) }
            } else {
                SectionTitle(L.t("onb.account.form"))
                labeled(L.t("settings.keyId")) {
                    TextField("", text: $keyId, prompt: Text(verbatim: "ABC123DEFG")).textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.characters).autocorrectionDisabled().accessibilityIdentifier("settings.keyId")
                }
                labeled(L.t("settings.issuerId")) {
                    TextField("", text: $issuerId, prompt: Text(verbatim: "69a6de7f-0000-47e3-e053-5b8c7c11a4d1")).textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("settings.issuerId")
                }
                labeled(L.t("settings.p8")) {
                    HStack {
                        Button(L.t("settings.chooseP8")) { picking = true }.buttonStyle(.bordered).accessibilityIdentifier("settings.chooseP8")
                        Text(p8Name ?? L.t("settings.keyNone")).font(.callout).foregroundStyle(p8Name == nil ? .secondary : .primary).lineLimit(1).truncationMode(.middle)
                    }
                }
                if let error { failure(error) }
                HStack {
                    if editing { Button(L.t("common.cancel")) { editing = false; error = nil } }
                    Spacer()
                    if saving { ProgressView().controlSize(.small) }
                    Button { Task { await save() } } label: { Label(L.t("onb.account.saveCheck"), systemImage: "checkmark.shield") }
                        .buttonStyle(VitrinGradientButtonStyle(fullWidth: false))
                        .disabled(saving || keyId.trimmingCharacters(in: .whitespaces).isEmpty || issuerId.trimmingCharacters(in: .whitespaces).isEmpty || p8 == nil)
                        .accessibilityIdentifier("settings.saveKey")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Files knows no type for .p8, so any file can be picked and its text decides.
        .fileImporter(isPresented: $picking, allowedContentTypes: [.data]) { read($0) }
        .confirmationDialog(L.t("settings.removeKey"), isPresented: $confirmRemove, titleVisibility: .visible) {
            Button(L.t("settings.removeKey"), role: .destructive) { Task { await remove() } }
            Button(L.t("common.cancel"), role: .cancel) {}
        }
    }

    /// The result of reading the team's apps with the stored key: the check that the key works.
    @ViewBuilder private var check: some View {
        let list = model.ascApps
        if list.loading {
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text(L.t("onb.account.checking")).font(.callout) }
        } else if let e = list.error {
            failure(e)
            Button(L.t("apps.refresh")) { Task { await model.refreshApps() } }.buttonStyle(.bordered).controlSize(.small)
        } else if list.loadedAt != nil {
            Label(L.t("onb.account.ok").replacingOccurrences(of: "{n}", with: "\(list.apps.count)"), systemImage: "checkmark.circle.fill").font(.callout).foregroundStyle(.green)
        }
    }

    private func failure(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.callout)
            content()
        }
    }

    private func read(_ result: Result<URL, any Error>) {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let text = try String(contentsOf: url, encoding: .utf8)
            guard text.contains("PRIVATE KEY-----") else { error = L.t("settings.keyNotP8"); return }
            p8 = text
            p8Name = url.lastPathComponent
            error = nil
            // AuthKey_ABC123DEFG.p8 names its key id: fill it in when the field is empty.
            let name = url.deletingPathExtension().lastPathComponent
            if keyId.isEmpty, name.hasPrefix("AuthKey_") { keyId = String(name.dropFirst("AuthKey_".count)) }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func save() async {
        guard let p8 else { return }
        saving = true
        defer { saving = false }
        do {
            try await model.credentials.save(keyId: keyId, issuerId: issuerId, p8: p8)
            error = nil
            editing = false
            keyId = ""; issuerId = ""; self.p8 = nil; p8Name = nil
            await model.refreshApps()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func remove() async {
        do {
            try await model.credentials.clear()
            error = nil
            model.ascApps.clear()
            await model.refreshApps()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// The account screen: who App Store Connect runs as, and every way to change that.
struct VitrinAccountView: View {
    @Environment(VitrinPanelModel.self) private var model
    @State private var session = AppleWebSession.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L.t("onb.account.title")).font(.title3.bold())
                    Text(L.t("onb.account.subtitle")).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                switch model.connection.state {
                case .missingCLI:
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L.t("asc.missing")).font(.headline)
                        AscInstallButton()
                    }
                    .vitrinCard(padding: 14)
                case .ascLogin(let name, let keyId):
                    HStack(alignment: .top, spacing: 12) {
                        VitrinBadge(symbol: "terminal.fill", colors: BadgeColors.fresh, size: 28)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L.t("onb.account.ascFound")).font(.headline)
                            Text(verbatim: "\(name) · Key ID \(keyId)").font(.callout.monospaced()).foregroundStyle(.secondary)
                            Text(L.t("onb.account.ascFoundDetail")).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .vitrinCard(padding: 14)
                default:
                    EmptyView()
                }
                if session.authenticated, !session.appleID.isEmpty {
                    Label(L.t("vitrin.signedInAs").replacingOccurrences(of: "{id}", with: session.appleID), systemImage: "person.crop.circle.badge.checkmark")
                        .font(.callout).foregroundStyle(.secondary)
                }
                AscKeySetup()
                Label(L.t("onb.account.privacy"), systemImage: "lock.fill").font(.caption).foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .brandWindowBackground()
        .navigationTitle(L.t("settings.account"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await session.refresh() }
    }
}
