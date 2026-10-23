import SwiftUI

// Item 39: the main window. Every bottle's games in one grid, each with Play, its status in words (the reason on hover and on click) and a
// menu: Fix this game, Report a problem, Show in Finder, Uninstall…. One "Add game" menu; drag and drop still works. Problems come with a Fix button.
// No log here: a progress bar and one plain sentence. Everything else is in Advanced (Settings › Show advanced options).
extension ContentView {
    @ViewBuilder var libraryView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Library").font(.system(size: 34, weight: .bold))
                    Text(librarySummary).font(.system(size: 15, weight: .semibold)).foregroundStyle(.secondary)
                }
                Spacer()
                addGameMenu
                if showAdvancedOption { Button { advancedMode = true } label: { Label("Advanced", systemImage: "wrench.and.screwdriver") }.labelStyle(.iconOnly).help("Advanced").secondaryButton() }
                SettingsLink { Label("Settings", systemImage: "gearshape") }.labelStyle(.iconOnly).help("Settings").secondaryButton()
            }.controlSize(.large)
            if let p = m.pendingSteamRestart {
                notice("clock", Theme.accent, "Steam restarts once it's free (it is \(p.busy) right now), so \(p.why).") {
                    Button("Restart now") { m.pendingSteamRestart = nil; m.restartSteam(p.bottle, because: p.why) }
                    Button("Not now") { m.pendingSteamRestart = nil }
                }
            }
            if let pr = m.problem {
                notice("exclamationmark.triangle.fill", .orange, pr.text + " Fix checks and repairs it; a snapshot is taken first.") {
                    Button("Fix") { m.problem = nil; m.fixGame(pr.game) }.primaryButton()
                    Button("Dismiss") { m.problem = nil }
                }
            }
            if !m.healthProblems.isEmpty {   // item 35: the start-up health check
                notice("stethoscope", .orange, "Cosmopolitan found something to fix: " + m.healthProblems.map(\.text).joined(separator: " ")) {
                    Button("Fix") { m.fixHealth() }.primaryButton()
                }
            }
            if !m.online { notice("wifi.slash", .orange, "You're offline. Each game says whether it starts without internet.") { EmptyView() } }
            if hintStep < 3 && !m.library.isEmpty {
                notice("lightbulb.fill", Theme.accent, ["Press Play to start a game. The first start can take a moment while it sets itself up.",
                                                        "Add game gets games from Steam, GOG, Epic or Battle.net, or installs one from a file.",
                                                        "The ··· menu on a game can fix it, report a problem or show its files."][hintStep]) {
                    Button(hintStep < 2 ? "Next" : "Got it") { hintStep += 1 }
                }
            }
            if m.library.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "gamecontroller.fill").font(.system(size: 40, weight: .semibold)).foregroundStyle(Theme.accent)
                        .frame(width: 92, height: 92).background(Circle().fill(Theme.accent.opacity(0.14)))
                    Text("No games yet").font(.title2.bold())
                    Text("Get your games from Steam, GOG, Epic or Battle.net, or install one from a file.").foregroundStyle(.secondary).multilineTextAlignment(.center)
                    addGameMenu(title: "Add your first game").controlSize(.large)
                }.padding(36).glassCard(24).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 16)], spacing: 16) { ForEach(m.library, id: \.self) { gameTile($0) } }
                        .padding(.vertical, 4)
                }
            }
            if m.busy || m.setupRunning || !m.activity.isEmpty {
                HStack(spacing: 10) {
                    if m.busy || m.setupRunning { ProgressView(value: m.setupRunning ? m.setupProgress : nil).frame(width: 140) }
                    Text(m.setupRunning ? "Getting things ready…" : m.activity.isEmpty ? "Working on it…" : m.activity).foregroundStyle(.secondary).lineLimit(1)
                }.padding(.horizontal, 14).padding(.vertical, 9).glassCard(14)
            }
        }.padding(.horizontal, 24).padding(.bottom, 20).padding(.top, 8)
        .onChange(of: m.busy) { _, b in if !b, m.activity.hasSuffix("…") { m.activity = "" } }
    }

    var librarySummary: String {
        let n = m.library.count, ready = m.library.filter { ["Ready", "Works offline"].contains(m.gameState($0).word) }.count
        return n == 0 ? "Windows games on your Mac" : "\(n) game\(n == 1 ? "" : "s") · \(ready) ready to play"
    }

    func gameTile(_ p: String) -> some View {
        let s = m.gameState(p), red = s.word.hasPrefix("Won't run"), fix = s.word == "Needs a fix"
        let tone: Color = red ? .red : fix ? .orange : s.word == "Ready" || s.word == "Works offline" ? Theme.accent : .secondary
        return VStack(alignment: .leading, spacing: 8) {
            cover(p)
            Text(appName(p)).font(.system(size: 14, weight: .semibold)).lineLimit(1)
            Button { reasonFor = p } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Circle().fill(tone).frame(width: 7, height: 7).alignmentGuide(.firstTextBaseline) { $0[.bottom] }
                    Text(s.word).font(.system(size: 12, weight: .medium)).foregroundStyle(tone)
                        .lineLimit(2, reservesSpace: true).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                }
            }.buttonStyle(.plain).help(s.reason)
            .popover(isPresented: Binding(get: { reasonFor == p }, set: { if !$0 { reasonFor = nil } })) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(s.word).font(.headline); Text(s.reason).fixedSize(horizontal: false, vertical: true)
                    if s.fix != nil { Button("Fix") { reasonFor = nil; m.fixGame(p) }.primaryButton() }
                }.padding().frame(width: 300)
            }
            HStack(spacing: 6) {
                Button { m.play(p) } label: { Label("Play", systemImage: "play.fill") }.primaryButton().disabled(m.busy || red)
                if fix { Button("Fix") { m.fixGame(p) }.secondaryButton().disabled(m.busy) }
                Spacer(minLength: 0)
                Menu {
                    Button("Fix this game") { m.fixGame(p) }
                    Button("Report a problem") { m.reportProblem(p) }
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p)]) }
                    Divider()
                    Button("Uninstall…") { uninstallExe = p }   // the same confirmation as Advanced; Steam games through Steam's own uninstall
                } label: { Image(systemName: "ellipsis.circle").imageScale(.large) }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
        }.padding(10).glassCard()
    }

    // The game's cover (Steam's portrait box, else its landscape header) over a soft blur of itself, or its icon on an emerald glow.
    func cover(_ p: String) -> some View {
        let art = m.artPath(p).flatMap { NSImage(contentsOfFile: $0) }, img = Image(nsImage: art ?? m.icons[p] ?? NSWorkspace.shared.icon(for: .applicationBundle))
        return Color.clear.aspectRatio(3 / 4, contentMode: .fit)
            .overlay {
                if art != nil {
                    ZStack { img.resizable().scaledToFill().blur(radius: 28).opacity(0.55); img.resizable().interpolation(.high).scaledToFit() }
                } else {
                    ZStack {
                        LinearGradient(colors: [Theme.accent.opacity(0.28), Theme.surface.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                        img.resizable().interpolation(.high).scaledToFit().frame(width: 64, height: 64).shadow(color: .black.opacity(0.45), radius: 10, y: 4)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous)).id(m.artVersion)
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
        } label: { Label(title, systemImage: "plus") }.menuStyle(.button).primaryButton().fixedSize().disabled(m.busy)
    }

    func notice<B: View>(_ icon: String, _ tone: Color, _ text: String, @ViewBuilder _ buttons: () -> B) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(tone).frame(width: 30, height: 30).background(Circle().fill(tone.opacity(0.15)))
            Text(text).fixedSize(horizontal: false, vertical: true)
            Spacer()
            buttons()
        }.secondaryButton().padding(12).glassCard(16)
    }
}
