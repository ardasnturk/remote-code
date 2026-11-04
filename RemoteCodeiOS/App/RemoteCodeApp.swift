import RemoteCodeKit
import SwiftData
import SwiftUI

@main
struct RemoteCodeApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(colorScheme)
                .onOpenURL { url in
                    if let link = SessionLink(url: url) {
                        Task { await model.open(link) }
                    } else if let link = PromoStudioLink(url: url) {
                        Task { await model.open(link) }
                    } else if let link = MacScreenLink(url: url) {
                        Task { await model.open(link) }
                    } else if url.scheme == PairingPayload.scheme {
                        model.incomingPairingLink = url.absoluteString
                        model.isPresentingPairing = true
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    model.scenePhaseChanged(phase)
                }
                .onChange(of: model.preferences.hapticsEnabled, initial: true) { _, enabled in
                    Haptics.isEnabled = enabled
                }
                .transaction { transaction in
                    if model.launch.isUITesting { transaction.disablesAnimations = true }
                }
        }
        .modelContainer(model.cache.container)
    }

    private var colorScheme: ColorScheme? {
        switch model.preferences.appearance {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Onboarding until a Mac is paired, then the session browser.
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            if let error = model.identityError {
                ContentUnavailableView {
                    Label("Keychain unavailable", systemImage: "key.slash")
                } description: {
                    Text(error)
                }
            } else if model.hasPairedMac {
                let promoStudio = model.connection?.promoStudio
                let vitrin = model.connection?.vitrin
                if promoStudio?.isAvailable == true || vitrin?.isAvailable == true {
                    TabView(selection: $model.selectedTab) {
                        Tab("Chats", systemImage: "bubble.left.and.text.bubble.right", value: RootTab.chats) {
                            MainSplitView()
                        }
                        if let promoStudio, promoStudio.isAvailable {
                            Tab("Promo Studio", systemImage: "sparkles.tv", value: RootTab.promoStudio) {
                                PromoStudioHomeView(store: promoStudio)
                            }
                        }
                        if let vitrin, vitrin.isAvailable {
                            Tab("Vitrin", systemImage: "storefront", value: RootTab.vitrin) {
                                VitrinHomeView(store: vitrin)
                            }
                        }
                    }
                } else {
                    MainSplitView()
                }
            } else {
                WelcomeView()
            }
        }
        .sheet(isPresented: $model.isPresentingPairing) {
            PairingFlowView(initialLink: model.incomingPairingLink)
                .onDisappear { model.incomingPairingLink = nil }
        }
        .task {
            model.connect()
        }
    }
}
