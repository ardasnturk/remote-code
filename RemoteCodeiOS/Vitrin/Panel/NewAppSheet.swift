// Ported from Vitrin for Mac (apps/VitrinMac/VitrinMac/Views/NewAppSheet.swift).
import SwiftUI

/// A new app on App Store Connect. Apple's API can't create one, so this signs in with the Apple Account and runs
/// `asc web apps create`, which also registers the bundle ID when the team's key can.
struct NewAppSheet: View {
    @Environment(VitrinPanelModel.self) private var model
    var close: () -> Void
    @State private var session = AppleWebSession.shared
    @State private var name = ""
    @State private var bundleID = ""
    @State private var sku = ""
    @State private var skuEdited = false
    @State private var platform = "IOS"
    @State private var locale = "en-US"
    @State private var version = "1.0"
    @State private var knownBundles: [String] = []
    @State private var checking = true
    @State private var running = false
    @State private var confirm = false
    @State private var error: String?

    static let platforms = ["IOS", "MAC_OS", "TV_OS", "UNIVERSAL"]
    /// The languages App Store Connect takes as a primary language.
    static let locales = ["ar-SA", "ca", "cs", "da", "de-DE", "el", "en-AU", "en-CA", "en-GB", "en-US", "es-ES", "es-MX", "fi", "fr-CA", "fr-FR", "he", "hi", "hr", "hu", "id", "it", "ja", "ko", "ms", "nl-NL", "no", "pl", "pt-BR", "pt-PT", "ro", "ru", "sk", "sv", "th", "tr", "uk", "vi", "zh-Hans", "zh-Hant"]

    private var ready: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && Self.validBundleID(bundleID) && !sku.trimmingCharacters(in: .whitespaces).isEmpty && !version.isEmpty
    }

    /// `com.example.app`: letters, digits, hyphens and dots, at least two parts.
    nonisolated static func validBundleID(_ s: String) -> Bool {
        s.wholeMatch(of: /[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+/) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(alignment: .top, spacing: 12) {
                        VitrinBadge(symbol: "plus.app.fill", colors: BadgeColors.brand, size: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L.t("newapp.title")).font(.headline)
                            Text(L.t("newapp.detail")).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if checking {
                    Section { ProgressView() }
                } else if !session.authenticated && !running {
                    Section { AppleAccountForm { } }
                } else {
                    form
                }
                if session.needsCode && running && session.authenticated {
                    Section { AppleAccountCodeRow() }
                }
                if let error { Section { Label(error, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) } }
                if session.authenticated {
                    Section {
                        Button { confirm = true } label: {
                            HStack(spacing: 8) {
                                if running { ProgressView().tint(.white) }
                                Text(L.t("newapp.create"))
                            }
                        }
                        .buttonStyle(VitrinGradientButtonStyle()).disabled(!ready || running)
                        .accessibilityIdentifier("newapp.create")
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.t("common.cancel"), action: close).disabled(running)
                }
            }
            .interactiveDismissDisabled(running)
        }
        .task {
            await session.refresh()
            checking = false
            if let doc = try? await AscCLI.json(["bundle-ids", "list", "--paginate"]) {
                knownBundles = JSONAPI.items(doc).map { JSONAPI.text($0, "identifier") }.filter { !$0.isEmpty && !$0.contains("*") }.sorted()
            }
        }
        .confirmationDialog(L.t("newapp.create"), isPresented: $confirm, titleVisibility: .visible) {
            Button(L.t("newapp.create")) { Task { await create() } }
            Button(L.t("common.cancel"), role: .cancel) {}
        } message: { Text(L.t("newapp.confirm").replacingOccurrences(of: "{name}", with: name)) }
    }

    @ViewBuilder private var form: some View {
        Section {
            labeled(L.t("newapp.name"), info: "info.newapp.name") {
                TextField("", text: $name).accessibilityIdentifier("newapp.name")
            }
            labeled("Bundle ID", info: "info.newapp.bundle") {
                HStack {
                    TextField("", text: Binding(get: { bundleID }, set: { bundleID = $0; if !skuEdited { sku = $0 } }), prompt: Text(verbatim: "com.example.app"))
                        .textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("newapp.bundle")
                    if !knownBundles.isEmpty {
                        Menu(L.t("newapp.existing")) {
                            ForEach(knownBundles, id: \.self) { b in Button(b) { bundleID = b; if !skuEdited { sku = b } } }
                        }
                        .fixedSize()
                    }
                }
            }
            labeled("SKU", info: "info.newapp.sku") {
                TextField("", text: Binding(get: { sku }, set: { sku = $0; skuEdited = true }))
                    .textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("newapp.sku")
            }
            Picker(AscText.field("platform"), selection: $platform) {
                ForEach(Self.platforms, id: \.self) { p in Text(AscText.value(p)).tag(p) }
            }
            labeled(L.t("newapp.version"), info: nil) {
                TextField("", text: $version, prompt: Text(verbatim: "1.0")).keyboardType(.numbersAndPunctuation).autocorrectionDisabled()
            }
            Picker(L.t("newapp.language"), selection: $locale) {
                ForEach(Self.locales.sorted { AscText.language($0) < AscText.language($1) }, id: \.self) { l in Text(AscText.language(l)).tag(l) }
            }
        }
    }

    private func labeled<Content: View>(_ title: String, info: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) { Text(title).font(.callout); if let info { InfoButton(key: info) } }
            content()
        }
    }

    private func create() async {
        running = true
        defer { running = false }
        error = nil
        let id = bundleID.trimmingCharacters(in: .whitespaces)
        do {
            // --auto-rename would quietly add a suffix to a taken name; the person should decide.
            let r = try await session.run(["web", "apps", "create", "--name", name.trimmingCharacters(in: .whitespaces), "--bundle-id", id, "--sku", sku.trimmingCharacters(in: .whitespaces),
                                           "--platform", platform, "--primary-locale", locale, "--version", version, "--auto-rename=false", "--output", "json"])
            guard r.ok else { error = r.errorLine.replacingOccurrences(of: "Error: ", with: ""); return }
            await model.refreshApps()
            let app = model.ascApps.apps.first { $0.bundleId == id }
            close()
            if let app { model.select(app: app) }
        } catch { self.error = error.localizedDescription }
    }
}

/// The code field, when a run that was already signed in needs a fresh sign-in on the way.
private struct AppleAccountCodeRow: View {
    @State private var session = AppleWebSession.shared
    @State private var code = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L.t("web.codeHint")).font(.callout).fixedSize(horizontal: false, vertical: true)
            HStack {
                TextField(L.t("web.code"), text: $code).textContentType(.oneTimeCode).keyboardType(.numberPad)
                Button(L.t("web.sendCode")) { session.submit(code: code); code = "" }.buttonStyle(.bordered).disabled(code.filter(\.isNumber).count < 6)
            }
        }
    }
}
