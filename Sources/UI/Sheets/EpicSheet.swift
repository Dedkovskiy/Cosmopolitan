import SwiftUI

extension ContentView {
    // Epic sign-in: Epic's own login page shows an authorizationCode after login; pasting it here hands it to Legendary.
    @ViewBuilder var epicSheet: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sign in to Epic Games").font(.headline)
            Text("1. Open the sign-in page and log in with your Epic account.\n2. The page then shows a line like \"authorizationCode\": \"abc123…\". Copy that code.\n3. Paste it below. Nothing else is stored; Legendary keeps the session in ~/.config/legendary.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button("Open sign-in page") { NSWorkspace.shared.open(Model.epicLoginURL) }
            TextField("authorizationCode", text: $epicCode).textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { showEpic = false }.keyboardShortcut(.cancelAction)
                Button("Sign in") { m.epicSignIn(code: epicCode); epicCode = ""; showEpic = false }.keyboardShortcut(.defaultAction).disabled(epicCode.trimmingCharacters(in: .whitespaces).count < 8)
            }
        }.padding().frame(width: 460)
    }

    @ViewBuilder var storesMenu: some View {
        Menu("Stores…") {
            ForEach(Store.allCases) { s in
                if let exe = m.storeExe(s) { Button("Open \(s.rawValue)") { m.launch(exe) } }
                else { Button("Install \(s.rawValue)…") { m.installStore(s) } }
            }
            Divider()
            if m.legendary == nil { Button("Set up Epic Games (installs Legendary)") { m.installLegendary() } }
            else if !m.epicSignedIn() { Button("Sign in to Epic Games…") { showEpic = true } }
            else {
                Menu("Install Epic game") {
                    let installed = Set(epicGames.values.map { $0.id })
                    let list = epicOwned.filter { !installed.contains($0.id) }
                    if list.isEmpty { Text(epicOwned.isEmpty ? "Loading your library… reopen this menu in a moment." : "Everything you own is installed.") }
                    ForEach(list, id: \.id) { g in Button(g.name) { m.installEpic(g.id) } }
                }
                Button("Sign out of Epic Games") { m.epicSignOut() }
            }
        }.menuStyle(.borderlessButton).fixedSize().disabled(m.selected.isEmpty || m.busy)
         .help("GOG Galaxy and Battle.net install into this bottle like any program. Epic games are downloaded and started by Legendary with this bottle's engine and drivers.")
    }
}
