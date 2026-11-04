// Ported from Vitrin for Mac (apps/VitrinMac/VitrinMac/Views/AppleAdsConnect.swift).
import SwiftUI
import UIKit

/// Connects Apple Ads from inside the app. Apple Ads has its own API users and keys, so three steps stay with the user
/// (inviting the API user, pasting the public key, copying back the ids); the app makes the key pair and signs in.
struct AppleAdsConnect: View {
    @Environment(AppModel.self) private var remote
    var done: () -> Void
    @State private var publicKey: String?
    /// Its path on the Mac: `asc ads auth login` reads a file.
    @State private var privateKey = ""
    @State private var clientId = ""
    @State private var teamId = ""
    @State private var keyId = ""
    @State private var running = false
    @State private var error: String?
    private static let adsURL = URL(string: "https://ads.apple.com")!

    private var ready: Bool { [clientId, teamId, keyId, privateKey].allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VitrinBadge(symbol: "megaphone.fill", colors: BadgeColors.brand, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L.t("ads.title")).font(.headline)
                    Text(L.t("ads.why")).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .vitrinCard(padding: 14)
            step(1, L.t("ads.step1.title")) {
                Text(L.t("ads.step1")).font(.callout).fixedSize(horizontal: false, vertical: true)
                Link(destination: Self.adsURL) { Label(L.t("ads.open"), systemImage: "arrow.up.right.square") }.font(.callout)
            }
            step(2, L.t("ads.step2.title")) {
                Text(L.t("ads.step2")).font(.callout).fixedSize(horizontal: false, vertical: true)
                if let publicKey {
                    Text(publicKey).font(.caption.monospaced()).textSelection(.enabled).padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                    Button {
                        UIPasteboard.general.string = publicKey
                    } label: { Label(L.t("ads.copyKey"), systemImage: "doc.on.doc") }
                        .controlSize(.small)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            step(3, L.t("ads.step3.title")) {
                Text(L.t("ads.step3")).font(.callout).fixedSize(horizontal: false, vertical: true)
                field("clientId", "SEARCHADS.…", $clientId)
                field("teamId", "SEARCHADS.…", $teamId)
                field("keyId", "", $keyId)
                if let error { Label(error, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
                HStack {
                    if running { ProgressView().controlSize(.small) }
                    Spacer()
                    Button(L.t("ads.connect")) { Task { await connect() } }
                        .buttonStyle(VitrinGradientButtonStyle(fullWidth: false)).disabled(running || !ready)
                        .accessibilityIdentifier("ads.connect")
                }
            }
        }
        .task {
            // The pair stays on the Mac; the private half is the file `asc ads auth login` reads.
            do {
                guard let pair = try await remote.connection?.vitrin.adsKeyPair() else { return }
                publicKey = pair.publicKey
                privateKey = pair.privateKey
            } catch { self.error = error.localizedDescription }
        }
    }

    private func step<Content: View>(_ n: Int, _ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            StepLine(number: n, text: title).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .vitrinCard(padding: 14)
    }

    /// One id; the block Apple shows, pasted here, fills all three.
    private func field(_ name: String, _ prompt: String, _ value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(name).font(.callout)
            TextField("", text: Binding(get: { value.wrappedValue }, set: { v in
                if let ids = AppleAdsKey.parse(block: v) { clientId = ids.clientId; teamId = ids.teamId; keyId = ids.keyId } else { value.wrappedValue = v }
            }), prompt: Text(prompt))
            .textFieldStyle(.roundedBorder).textInputAutocapitalization(.never).autocorrectionDisabled()
        }
    }

    private func connect() async {
        running = true
        defer { running = false }
        error = nil
        let args = ["ads", "auth", "login", "--name", "Vitrin", "--client-id", clientId.trimmingCharacters(in: .whitespaces), "--team-id", teamId.trimmingCharacters(in: .whitespaces),
                    "--key-id", keyId.trimmingCharacters(in: .whitespaces), "--private-key", privateKey.trimmingCharacters(in: .whitespaces), "--network"]
        do {
            let r = try await AscCLI.run(args, readOnly: false)
            if r.ok { done() } else { error = r.errorLine.replacingOccurrences(of: "Error: ", with: "") }
        } catch { self.error = error.localizedDescription }
    }
}

/// Apple Ads on the team page: the connection when it is missing, the account when it is there.
struct AppleAdsPage: View {
    @State private var tick = 0
    var body: some View {
        AscLoad(args: ["ads", "auth", "status"], refresh: tick) { doc, reload in
            if (doc.objectValue?["credentials"]?.arrayValue ?? []).isEmpty {
                AppleAdsConnect { tick += 1; reload() }
            } else {
                AscSection(title: L.t("ads.account"), args: ["ads", "me", "view"])
                AscSection(title: L.t("ads.accounts"), args: ["ads", "auth", "discover"])
            }
        }
    }
}
