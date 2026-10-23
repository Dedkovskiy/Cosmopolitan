import SwiftUI

// Item 39: the main window. Every bottle's games in one grid, each with Play, its status in words (the reason on hover and on click) and a
// menu: Fix this game, Report a problem, Show in Finder, Uninstall…. One "Add game" menu; drag and drop still works. Problems come with a Fix button.
// No log here: a progress bar and one plain sentence. Everything else is in Advanced (Settings › Show advanced options).
extension ContentView {
    @ViewBuilder var libraryView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text("Library").font(.largeTitle.bold())
                Spacer()
                addGameMenu
                if showAdvancedOption { Button { advancedMode = true } label: { Label("Advanced", systemImage: "wrench.and.screwdriver") } }
                SettingsLink { Label("Settings", systemImage: "gearshape") }
            }
            if let p = m.pendingSteamRestart {
                notice("clock", "Steam restarts once it's free (it is \(p.busy) right now), so \(p.why).") {
                    Button("Restart now") { m.pendingSteamRestart = nil; m.restartSteam(p.bottle, because: p.why) }
                    Button("Not now") { m.pendingSteamRestart = nil }
                }
            }
            if let pr = m.problem {
                notice("exclamationmark.triangle.fill", pr.text + " Fix checks and repairs it; a snapshot is taken first.") {
                    Button("Fix") { m.problem = nil; m.fixGame(pr.game) }.buttonStyle(.borderedProminent)
                    Button("Dismiss") { m.problem = nil }
                }
            }
            if !m.healthProblems.isEmpty {   // item 35: the start-up health check
                notice("stethoscope", "Cosmopolitan found something to fix: " + m.healthProblems.map(\.text).joined(separator: " ")) {
                    Button("Fix") { m.fixHealth() }.buttonStyle(.borderedProminent)
                }
            }
            if !m.online { notice("wifi.slash", "You're offline. Each game says whether it starts without internet.") { EmptyView() } }
            if hintStep < 3 && !m.library.isEmpty {
                notice("lightbulb", ["Press Play to start a game. The first start can take a moment while it sets itself up.",
                                     "Add game gets games from Steam, GOG, Epic or Battle.net, or installs one from a file.",
                                     "The ··· menu on a game can fix it, report a problem or show its files."][hintStep]) {
                    Button(hintStep < 2 ? "Next" : "Got it") { hintStep += 1 }
                }
            }
            if m.library.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "gamecontroller").font(.system(size: 52)).foregroundStyle(.secondary)
                    Text("No games yet").font(.title2)
                    Text("Get your games from Steam, GOG, Epic or Battle.net, or install one from a file.").foregroundStyle(.secondary)
                    addGameMenu(title: "Add your first game").controlSize(.large)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 18)], spacing: 18) { ForEach(m.library, id: \.self) { gameTile($0) } }
                        .padding(.vertical, 4)
                }
            }
            if m.busy || m.setupRunning || !m.activity.isEmpty {
                HStack(spacing: 10) {
                    if m.busy || m.setupRunning { ProgressView(value: m.setupRunning ? m.setupProgress : nil).frame(width: 140) }
                    Text(m.setupRunning ? "Getting things ready…" : m.activity.isEmpty ? "Working on it…" : m.activity).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }.padding(20)
        .onChange(of: m.busy) { _, b in if !b, m.activity.hasSuffix("…") { m.activity = "" } }
    }

    func gameTile(_ p: String) -> some View {
        let s = m.gameState(p), red = s.word.hasPrefix("Won't run"), fix = s.word == "Needs a fix"
        return VStack(alignment: .leading, spacing: 6) {
            Image(nsImage: (m.artPath(p).flatMap { NSImage(contentsOfFile: $0) }) ?? m.icons[p] ?? NSWorkspace.shared.icon(for: .applicationBundle))
                .resizable().interpolation(.high).scaledToFit().frame(maxWidth: .infinity).frame(height: 96).id(m.artVersion)
            Text(appName(p)).font(.headline).lineLimit(1)
            Button { reasonFor = p } label: {
                Text(s.word).font(.callout).foregroundStyle(red ? .red : fix ? .orange : s.word == "Ready" || s.word == "Works offline" ? .green : .secondary)
                    .lineLimit(2).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
            }.buttonStyle(.plain).help(s.reason)
            .popover(isPresented: Binding(get: { reasonFor == p }, set: { if !$0 { reasonFor = nil } })) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(s.word).font(.headline); Text(s.reason).fixedSize(horizontal: false, vertical: true)
                    if s.fix != nil { Button("Fix") { reasonFor = nil; m.fixGame(p) }.buttonStyle(.borderedProminent) }
                }.padding().frame(width: 300)
            }
            HStack {
                Button("Play") { m.play(p) }.buttonStyle(.borderedProminent).disabled(m.busy || red)
                if fix { Button("Fix") { m.fixGame(p) }.disabled(m.busy) }
                Spacer()
                Menu {
                    Button("Fix this game") { m.fixGame(p) }
                    Button("Report a problem") { m.reportProblem(p) }
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p)]) }
                    Divider()
                    Button("Uninstall…") { uninstallExe = p }   // the same confirmation as Advanced; Steam games through Steam's own uninstall
                } label: { Image(systemName: "ellipsis.circle").imageScale(.large) }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
        }.padding(10).background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.5)))
    }

    var addGameMenu: some View { addGameMenu(title: "Add game") }
    func addGameMenu(title: String) -> some View {
        Menu {
            Button("Steam") { m.addStore(.steam) }
            if m.lgog == nil { Button("GOG") { m.installLgog(); loginStore = "gog" } }
            else if !m.gogSignedIn() { Button("GOG") { loginStore = "gog" } }
            else { Menu("GOG") { let mine = m.gogInstalled(); ForEach(gogOwned.filter { !mine.contains($0.id) }, id: \.id) { g in Button(g.name) { m.installGog(g.id) } } } }
            if m.legendary == nil { Button("Epic Games") { m.installLegendary() } }
            else if !m.epicSignedIn() { Button("Epic Games") { loginStore = "epic" } }
            else { Menu("Epic Games") { let mine = Set(epicGames.values.map { $0.id }); ForEach(epicOwned.filter { !mine.contains($0.id) }, id: \.id) { g in Button(g.name) { m.installEpic(g.id) } } } }
            Button("Battle.net") { m.addStore(.battlenet) }
            Divider()
            Button("I have an installer file…") { pick() }
        } label: { Label(title, systemImage: "plus") }.fixedSize().disabled(m.busy)
    }

    func notice<B: View>(_ icon: String, _ text: String, @ViewBuilder _ buttons: () -> B) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(.orange)
            Text(text).fixedSize(horizontal: false, vertical: true)
            Spacer()
            buttons()
        }.padding(10).background(RoundedRectangle(cornerRadius: 8).fill(.orange.opacity(0.12)))
    }
}
