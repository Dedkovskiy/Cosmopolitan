import SwiftUI
import WebKit

// Store sign-in inside the app: the store's own login page runs in a web view with a fresh, private session (so a stale browser
// login cannot skip Epic's policy prompts). The moment the page that carries the code appears, it is read and handed to
// Legendary / lgogdownloader; the user never copies anything. Epic keeps a paste field as fallback; GOG needs none.
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
        // GOG: the success address is caught before it loads (nothing is sent to that page); didFinish below stays as a fallback.
        func webView(_ w: WKWebView, decidePolicyFor a: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            if !p.isEpic, !done, let u = a.request.url, Model.isGogRedirect(u) { done = true; decisionHandler(.cancel); p.onCode(u.absoluteString); return }
            decisionHandler(.allow)
        }
        func webView(_ w: WKWebView, didFinish nav: WKNavigation!) {
            guard !done, let u = w.url else { return }
            if p.isEpic, u.path.hasPrefix("/id/api/redirect") {
                w.evaluateJavaScript("document.body.innerText") { r, _ in
                    guard let s = r as? String, let d = s.data(using: .utf8), let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return }
                    if let c = j["authorizationCode"] as? String, !c.isEmpty { self.done = true; self.p.onCode(c) }
                }
            } else if !p.isEpic, Model.isGogRedirect(u) {
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
                Button(loginResult?.ok == true ? "Done" : "Cancel") { closeLogin() }.keyboardShortcut(.cancelAction)
            }
            if !epic, let r = loginResult {   // item 22: GOG's outcome stays on screen: "Signed in" or the reason it failed
                Label(r.message, systemImage: r.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(r.ok ? .green : .orange).font(.title3).fixedSize(horizontal: false, vertical: true).frame(width: 720, alignment: .leading)
                if r.ok { Text("Your GOG library loads in the background: Stores… › Install GOG game.").font(.caption).foregroundStyle(.secondary) }
                else { Button("Try again") { loginResult = nil } }
            } else if loginBusy {
                ProgressView("Signing in to GOG…").frame(width: 720, height: 120)
            } else {
                Text(epic ? "Log in below. If Epic asks you to accept an updated policy, accept it; the sign-in completes by itself afterwards."
                          : "Log in below. The sign-in completes by itself when GOG's login finishes.")
                    .font(.caption).foregroundStyle(.secondary)
                StoreLoginWebView(url: epic ? Model.epicLoginURL : Model.gogLoginURL, onCode: { code in
                    if epic { m.epicSignIn(code: code); loginStore = nil } else { gogFinish(code) }
                }, isEpic: epic).frame(width: 720, height: 620).clipShape(RoundedRectangle(cornerRadius: 8))
                if epic {   // GOG needs no pasting any more: its redirect is caught (item 22)
                    HStack {
                        TextField("…or paste the authorizationCode here", text: $loginCode).textFieldStyle(.roundedBorder)
                        Button("Use code") { m.epicSignIn(code: loginCode); loginStore = nil; loginCode = "" }
                            .disabled(loginCode.trimmingCharacters(in: .whitespaces).count < 8)
                    }
                }
            }
        }.padding()
    }
    func gogFinish(_ address: String) { loginBusy = true; m.gogSignIn(redirectURL: address) { ok, msg in loginBusy = false; loginResult = (ok, msg) } }
    func closeLogin() { loginStore = nil; loginResult = nil; loginBusy = false }

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
            // GOG's Windows client cannot draw its UI under Wine on macOS (Qt 6 web view stays blank on every backend); GOG's native Mac
            // client is the one that runs. Windows-only builds still come through lgogdownloader below.
            if let app = ["/Applications/GOG Galaxy.app", NSHomeDirectory() + "/Applications/GOG Galaxy.app"].first(where: { FileManager.default.fileExists(atPath: $0) }) {
                Button("Open GOG Galaxy (Mac app)") { NSWorkspace.shared.open(URL(fileURLWithPath: app)) }
            } else { Button("Install GOG Galaxy (Mac app)…") { m.installNativeGalaxy() } }
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
