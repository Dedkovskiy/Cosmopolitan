import SwiftUI

extension ContentView {
    // Browser sign-in for the native store clients: the store's own login page opens in Safari; what the page shows afterwards
    // (Epic: an authorizationCode; GOG: the address of the page you land on) is pasted here and handed to Legendary / lgogdownloader.
    @ViewBuilder var storeLoginSheet: some View {
        let epic = loginStore == "epic"
        VStack(alignment: .leading, spacing: 10) {
            Text(epic ? "Sign in to Epic Games" : "Sign in to GOG").font(.headline)
            Text(epic ? "1. Open the sign-in page and log in with your Epic account.\n2. The page then shows a line like \"authorizationCode\": \"abc123…\". Copy that code.\n3. Paste it below. Legendary keeps the session in ~/.config/legendary; nothing else is stored."
                      : "1. Open the sign-in page and log in with your GOG account.\n2. You land on a page that looks broken or empty; that is expected. Copy its full address from the address bar (it starts with https://embed.gog.com/on_login_success).\n3. Paste it below. lgogdownloader keeps the session in ~/.config/lgogdownloader; nothing else is stored.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button("Open sign-in page") { NSWorkspace.shared.open(epic ? Model.epicLoginURL : Model.gogLoginURL) }
            TextField(epic ? "authorizationCode" : "https://embed.gog.com/on_login_success?origin=client&code=…", text: $loginCode).textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { loginStore = nil }.keyboardShortcut(.cancelAction)
                Button("Sign in") { if epic { m.epicSignIn(code: loginCode) } else { m.gogSignIn(redirectURL: loginCode) }; loginCode = ""; loginStore = nil }
                    .keyboardShortcut(.defaultAction).disabled(epic ? loginCode.trimmingCharacters(in: .whitespaces).count < 8 : !loginCode.contains("code="))
            }
        }.padding().frame(width: 480)
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
