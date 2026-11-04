import SwiftUI
import WebKit

/// Instagram accounts connected in Promo Studio; sign in with Facebook on the phone.
struct PromoStudioAccountsView: View {
    let store: PromoStudioStore
    @Environment(\.dismiss) private var dismiss
    @State private var login: PromoStudioLogin?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.state?.accounts ?? []) { account in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: "@\(account.username)").font(.headline)
                            let projects = (store.state?.projects ?? []).filter { $0.accountId == account.userId }.map(\.name)
                            if !projects.isEmpty {
                                Text(projects.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                            }
                            if let expiry = account.tokenExpiresAt {
                                Text("Signed in until \(expiry.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption2).foregroundStyle(expiry.timeIntervalSinceNow < 86400 ? .red : .secondary)
                            }
                        }
                        .swipeActions {
                            Button("Remove", role: .destructive) { run("disconnect", ["accountId": account.userId]) }
                        }
                    }
                } header: {
                    Text("Instagram Accounts")
                } footer: {
                    Text("Each project posts with its own account. Accounts linked to a Facebook Page you manage are added together.")
                }
                Section {
                    Button {
                        startLogin()
                    } label: {
                        Label("Sign In with Facebook", systemImage: "person.badge.key")
                    }
                    Button {
                        run("refreshAccounts", [:])
                    } label: {
                        Label("Refresh Accounts", systemImage: "arrow.clockwise")
                    }
                } footer: {
                    Text("After linking a new Instagram account to one of your Facebook Pages, refresh to add it without signing in again.")
                }
            }
            .promoStudioScreen()
            .navigationTitle(Text("Accounts"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(item: $login) { login in
                PromoStudioLoginSheet(login: login) { result in
                    self.login = nil
                    switch result {
                    case .token(let token, let expiresIn):
                        var body: [String: Any] = ["token": token]
                        if let expiresIn { body["expiresIn"] = expiresIn }
                        run("connectToken", body)
                    case .code(let code):
                        run("connectCode", ["code": code])
                    case .cancelled:
                        break
                    }
                }
            }
            .alert("Promo Studio", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
        }
    }

    private func startLogin() {
        Task {
            do {
                let info = try await store.action("loginInfo")
                guard let url = (info["authorizeURL"] as? String).flatMap(URL.init(string:)),
                      let redirect = info["redirectURI"] as? String else { return }
                login = PromoStudioLogin(url: url, redirectURI: redirect)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func run(_ action: String, _ body: [String: Any]) {
        Task {
            do { try await store.action(action, body) } catch { self.error = error.localizedDescription }
        }
    }
}

struct PromoStudioLogin: Identifiable {
    let id = UUID()
    let url: URL
    let redirectURI: String
}

enum PromoStudioLoginResult {
    case token(String, expiresIn: Int?)
    case code(String)
    case cancelled
}

/// Meta's OAuth page in an embedded browser; the token (Facebook) or code
/// (Instagram) is taken from the redirect and sent to the Mac.
struct PromoStudioLoginSheet: View {
    let login: PromoStudioLogin
    var onFinish: (PromoStudioLoginResult) -> Void

    var body: some View {
        NavigationStack {
            PromoStudioLoginWebView(login: login, onFinish: onFinish)
                .ignoresSafeArea(edges: .bottom)
                .promoStudioScreen()
                .navigationTitle(Text("Sign In"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { onFinish(.cancelled) } }
                }
        }
    }
}

private struct PromoStudioLoginWebView: UIViewRepresentable {
    let login: PromoStudioLogin
    var onFinish: (PromoStudioLoginResult) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(redirectURI: login.redirectURI, onFinish: onFinish) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.load(URLRequest(url: login.url))
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let redirectURI: String
        let onFinish: (PromoStudioLoginResult) -> Void
        private var finished = false

        init(redirectURI: String, onFinish: @escaping (PromoStudioLoginResult) -> Void) {
            self.redirectURI = redirectURI
            self.onFinish = onFinish
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url, url.absoluteString.hasPrefix(redirectURI), !finished else {
                decisionHandler(.allow)
                return
            }
            finished = true
            decisionHandler(.cancel)
            // Facebook returns the token in the fragment, Instagram a code in the query.
            var items: [String: String] = [:]
            for part in [url.fragment, URLComponents(url: url, resolvingAgainstBaseURL: false)?.query].compactMap({ $0 }) {
                for pair in part.split(separator: "&") {
                    let kv = pair.split(separator: "=", maxSplits: 1).map { String($0).removingPercentEncoding ?? String($0) }
                    if kv.count == 2 { items[kv[0]] = kv[1] }
                }
            }
            if let token = items["access_token"] {
                onFinish(.token(token, expiresIn: items["expires_in"].flatMap(Int.init)))
            } else if let code = items["code"] {
                onFinish(.code(code.replacingOccurrences(of: "#_", with: "")))
            } else {
                onFinish(.cancelled)
            }
        }
    }
}
