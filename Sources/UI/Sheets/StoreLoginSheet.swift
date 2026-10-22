import SwiftUI
import WebKit

// Store sign-in inside the app: the store's own login page runs in a web view with a fresh, private session (so a stale browser
// login cannot skip Epic's policy prompts). The moment the page that carries the code appears, it is read and handed to
// Legendary / lgogdownloader; the user never copies anything. A paste field stays as fallback.
struct StoreLoginWebView: NSViewRepresentable {
    let url: URL
    let onCode: (String) -> Void          // Epic: authorizationCode; GOG: the full redirect URL (what lgogdownloader asks for)
    let isEpic: Bool
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration(); cfg.websiteDataStore = .nonPersistent()
        let v = WKWebView(frame: .zero, configuration: cfg); v.navigationDelegate = context.coordinator
        v.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        v.load(URLRequest(url: url)); return v
    }
    func updateNSView(_ v: WKWebView, context: Context) {}
    final class Coordinator: NSObject, WKNavigationDelegate {
        let p: StoreLoginWebView; var done = false
        init(_ p: StoreLoginWebView) { self.p = p }
        func webView(_ w: WKWebView, didFinish nav: WKNavigation!) {
            guard !done, let u = w.url else { return }
            if p.isEpic, u.path.hasPrefix("/id/api/redirect") {
                w.evaluateJavaScript("document.body.innerText") { r, _ in
                    guard let s = r as? String, let d = s.data(using: .utf8), let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return }
                    if let c = j["authorizationCode"] as? String, !c.isEmpty { self.done = true; self.p.onCode(c) }
                }
            } else if !p.isEpic, u.host?.hasSuffix("gog.com") == true, u.path.contains("on_login_success"), u.absoluteString.contains("code=") {
                done = true; p.onCode(u.absoluteString)
            }
        }
    }
}

extension ContentView {
    @ViewBuilder var storeLoginSheet: some View {
        let epic = loginStore == "epic"
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(epic ? "Sign in to Epic Games" : "Sign in to GOG").font(.headline)
                Spacer()
                Button("Cancel") { loginStore = nil }.keyboardShortcut(.cancelAction)
            }
            Text(epic ? "Log in below. If Epic asks you to accept an updated policy, accept it; the sign-in completes by itself afterwards."
                      : "Log in below. The sign-in completes by itself when GOG's login finishes (the page it lands on looks empty; that is fine).")
                .font(.caption).foregroundStyle(.secondary)
            StoreLoginWebView(url: epic ? Model.epicLoginURL : Model.gogLoginURL, onCode: { code in
                if epic { m.epicSignIn(code: code) } else { m.gogSignIn(redirectURL: code) }
                loginStore = nil
            }, isEpic: epic).frame(width: 720, height: 620).clipShape(RoundedRectangle(cornerRadius: 8))
            HStack {
                TextField(epic ? "…or paste the authorizationCode here" : "…or paste the https://embed.gog.com/on_login_success?… address here", text: $loginCode).textFieldStyle(.roundedBorder)
                Button("Use code") { if epic { m.epicSignIn(code: loginCode) } else { m.gogSignIn(redirectURL: loginCode) }; loginCode = ""; loginStore = nil }
                    .disabled(epic ? loginCode.trimmingCharacters(in: .whitespaces).count < 8 : !loginCode.contains("code="))
            }
        }.padding()
    }

    @ViewBuilder var storesMenu: some View {
        Menu("Stores…") {
            ForEach(Store.allCases) { s in
                if let exe = m.storeExe(s) { Button("Open \(s.rawValue)") { m.launch(exe) } }
                else { Button("Install \(s.rawValue)…") { m.installStore(s) } }
            }
            Divider()
            if m.legendary == nil { Button("Set up Epic Games (installs Legendary)") { m.installLegendary() } }
            else if !m.epicSignedIn() { Button("Sign in to Epic Games…") { loginStore = "epic" } }
            else {
                Menu("Install Epic game") {
                    let installed = Set(epicGames.values.map { $0.id })
                    let list = epicOwned.filter { !installed.contains($0.id) }
                    if list.isEmpty { Text(epicOwned.isEmpty ? "Loading your library… reopen this menu in a moment." : "Everything you own is installed.") }
                    ForEach(list, id: \.id) { g in Button(g.name) { m.installEpic(g.id) } }
                }
                Button("Sign out of Epic Games") { m.epicSignOut() }
            }
            Divider()
            if m.lgog == nil { Button("Set up GOG (installs lgogdownloader)") { m.installLgog() } }
            else if !m.gogSignedIn() { Button("Sign in to GOG…") { loginStore = "gog" } }
            else {
                Menu("Install GOG game") {
                    let installed = m.gogInstalled()
                    let list = gogOwned.filter { !installed.contains($0.id) }
                    if list.isEmpty { Text(gogOwned.isEmpty ? "Loading your library… reopen this menu in a moment." : "Everything you own is installed.") }
                    ForEach(list, id: \.id) { g in Button(g.name) { m.installGog(g.id) } }
                }
                Button("Sign out of GOG") { m.gogSignOut() }
            }
        }.menuStyle(.borderlessButton).fixedSize().disabled(m.selected.isEmpty || m.busy)
         .help("Battle.net installs into this bottle like any program. Epic and GOG games are downloaded by Legendary / lgogdownloader into the bottle and started with its engine and drivers.")
    }
}
