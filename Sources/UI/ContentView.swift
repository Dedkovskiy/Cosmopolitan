import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject var m = Model()
    @State var newName = ""
    @State var confirmDelete = false
    @State var uninstallExe: String? = nil
    @State var optExe: String? = nil
    @State var optText = ""
    @State var showD3DM = false
    @State var licRead = false
    @State var showTerms = !termsAccepted()
    @State var showSnaps = false
    @State var modExe: String? = nil
    @State var showWIR = false
    @State var wirLink = ""
    @State var showImport = false
    @State var rollbackTarget: String? = nil
    @State var loginStore: String? = nil   // "epic" / "gog" while the sign-in sheet is up
    @State var loginCode = ""
    var body: some View {
        HSplitView {
            VStack(alignment: .leading) {
                Text("Bottles").font(.headline)
                List(m.bottles, id: \.self, selection: Binding(get: { m.selected }, set: { m.selected = $0; m.scan() })) { Text($0).tag($0) }
                HStack {
                    TextField("new bottle", text: $newName)
                    Button("Create") { m.createBottle(newName); newName = "" }.disabled(newName.isEmpty || m.busy)
                }
                // Whole-bottle actions, rarely needed: one menu instead of eight buttons.
                Menu("Manage bottle") {
                    Button("Snapshots…") { showSnaps = true }.disabled(m.selected.isEmpty)
                    Button("Back up") { m.backupBottle() }.disabled(m.selected.isEmpty || m.busy)
                    Button("Archive to a file") { m.archiveBottle() }.disabled(m.selected.isEmpty || m.busy)
                    Button("Restore from a file…") { m.restoreBottle() }.disabled(m.busy)
                    Button("Import from Whisky / CrossOver / Sikarugir…") { showImport = true }
                    Divider()
                    Button("Share with other Mac users") { m.shareBottle() }.disabled(m.selected.isEmpty || m.busy)
                    Menu("Move to external drive") {   // §8.4 copies the bottle, leaves a link; hides while unplugged
                        let vols = m.externalVolumes()
                        if vols.isEmpty { Text("No writable external drive connected") }
                        ForEach(vols, id: \.self) { v in Button((v as NSString).lastPathComponent) { m.moveBottle(to: v) } }
                    }.disabled(m.selected.isEmpty || m.busy)
                    Divider()
                    // Kernel anti-cheat (Call of Duty, Valorant, Fortnite…) can't run on a Mac in any form; the anti-cheat runs on the streaming server instead.
                    Button("Play anti-cheat games in the cloud…") {
                        if let gfn = ["/Applications/GeForceNOW.app", "/Applications/NVIDIA GeForce NOW.app"].first(where: { FileManager.default.fileExists(atPath: $0) }) { NSWorkspace.shared.open(URL(fileURLWithPath: gfn)) }
                        else { NSWorkspace.shared.open(URL(string: "https://play.geforcenow.com")!) }
                        NSWorkspace.shared.open(URL(string: "https://www.xbox.com/play")!)
                        m.log += "Cloud: GeForce NOW (own the game on Battle.net/Steam) and Xbox Cloud Gaming (Game Pass Ultimate) stream Call of Duty to this Mac; the DualSense works over Bluetooth.\n"
                    }
                    Divider()
                    Button("Delete bottle…", role: .destructive) { confirmDelete = true }.disabled(m.selected.isEmpty || m.busy)
                }.fixedSize()
                Divider()
                Text("Automatic").font(.headline)
                Text("Windows version per program · drivers per program · runtimes and community fixes on launch · Steam starts with the app · msync · 60 fps cap and lighter rendering while on battery")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Metal performance HUD", isOn: $m.hud).disabled(m.selected.isEmpty)
                    .onChange(of: m.hud) { _, v in if !m.loading { m.envSet("MTL_HUD_ENABLED", v ? "1" : nil); m.restartSteamIfIdle() } }
                Divider()
                HStack {
                    Circle().fill(m.driverStatus.0).frame(width: 10, height: 10)
                    Text("Drivers").font(.headline); Spacer()
                    Button("D3DMetal…") { showD3DM = true }.controlSize(.small)
                        .help("Apple's Game Porting Toolkit for Direct3D 12: install from Apple's download, read and accept Apple's license, or remove it.")
                    Button("Update…") { m.updateDrivers() }.controlSize(.small).disabled(m.busy)
                        .help("Runs the weekly driver update now: DXMT and DXVK from their GitHub releases, D3DMetal from the newest Sikarugir template. Previous versions are kept as .old.")
                    Button("Folder…") { NSWorkspace.shared.open(URL(fileURLWithPath: driversDir)) }.controlSize(.small)
                }
                Text(m.driverStatus.1 + (m.driverUpdates.isEmpty ? "" : " · " + m.driverUpdates)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                HStack {
                    Circle().fill(m.padStatus.0).frame(width: 10, height: 10)
                    Text("Controller").font(.headline)
                    Text(m.padStatus.1).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                ForEach(installedDrivers(), id: \.self) { d in   // read-only: the launch check picks per program
                    Label(driverLabel(d), systemImage: m.drivers.contains(d) ? "checkmark.circle.fill" : "circle")
                        .font(.caption).foregroundStyle(m.drivers.contains(d) ? .primary : .secondary).padding(.leading, 4)
                }
                Text("Chosen from what is installed: dxmt for Direct3D 10/11 bottles, d3dmetal as soon as a Direct3D 12 game is present (Steam is restarted automatically).")
                    .font(.caption).foregroundStyle(.secondary)
            }.frame(minWidth: 200, maxWidth: 340).padding()
            VStack(alignment: .leading) {
                HStack {
                    Text("Programs in \(m.selected)").font(.headline)
                    Spacer()
                    Button("Find apps") { m.findApps() }.disabled(m.selected.isEmpty || m.busy)
                        .help("Searches the whole C: drive of this bottle for programs the normal scan missed.")
                    Button("Run .exe / .msi…") { pick() }.disabled(m.busy)
                    storesMenu
                }
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 16)], spacing: 16) {
                        ForEach(m.programs, id: \.self) { p in
                            Button { m.launch(p) } label: {
                                VStack {
                                    // Cover art from Steam's CDN when cached (artVersion bumps on arrival), the exe's own icon otherwise.
                                    Image(nsImage: (m.artPath(p).flatMap { NSImage(contentsOfFile: $0) }) ?? m.icons[p] ?? NSWorkspace.shared.icon(for: .applicationBundle))
                                        .resizable().interpolation(.high).scaledToFit().frame(width: 64, height: 64).id(m.artVersion)
                                        .overlay(alignment: .topTrailing) {   // pre-verification light; hover for the reason
                                            if let r = m.readiness[p] { Circle().fill(r.status).frame(width: 12, height: 12).overlay(Circle().stroke(.black.opacity(0.4))).offset(x: 4, y: -4) }
                                        }
                                    Text(appName(p)).font(.caption).lineLimit(2).multilineTextAlignment(.center)
                                }.frame(width: 100).padding(.vertical, 6).contentShape(Rectangle())
                            }.buttonStyle(.plain).disabled(m.busy)
                            .help((m.readiness[p]?.note.trimmingCharacters(in: .whitespacesAndNewlines) ?? "checking…") + (m.playtime(p).map { "\nPlayed \($0)" } ?? ""))
                            .contextMenu {
                                if let off = m.offlineExe(p) { Button("Launch offline version (official, offline only)") { m.launch(off) } }
                                Button("Check requirements") { m.readiness[p] = m.launchNeeds(p); m.log += m.readiness[p]?.note ?? ""; if m.readiness[p]?.note.isEmpty ?? true { m.log += "\(appName(p)): nothing special needed.\n" } }
                                Button("Options…") { optText = (try? String(contentsOfFile: m.optionsPath(p), encoding: .utf8)) ?? Model.optionsTemplate; optExe = p }
                                Button("Mods…") { modExe = p }
                                Button("Benchmark (90 s, Metal HUD)") { m.benchmark(p) }
                                Button("fps history") { m.log += m.fpsHistory(p) }
                                Button("Try next driver set") { m.bisect(p) }
                                Button("Report result to Highball…") { m.reportToHighball(p) }
                                Button("Compress on disk (APFS)…") { m.compressGame(p) }
                                Button("Create Dock shortcut") { m.makeShortcut(p) }
                                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p)]) }
                                Divider()
                                Button("Uninstall…", role: .destructive) { uninstallExe = p }
                            }
                        }
                    }.padding(8)
                }
                HStack {
                    Text("Drop an installer anywhere in this window — a bottle is created automatically if needed.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Will it run?…") { showWIR = true }.controlSize(.small)
                        .help("Paste a Steam store link: verdict for this Mac from Highball, ProtonDB and the anti-cheat map, before you buy.")
                    Button("Offline check") { m.offlineCheck() }.controlSize(.small).disabled(m.selected.isEmpty)
                        .help("Which programs will start without internet, and what to do in Steam before a trip.")
                    Button("Bug report") { m.copyBugReport() }.controlSize(.small)
                        .help("Copies a report with log, engine, drivers and Mac details to the clipboard, with your username and home folder removed.")
                    Button("Test rumble") { m.testRumble() }.controlSize(.small)
                        .help("Pulses the connected controller's motors from macOS; in games, rumble arrives through SDL. Adaptive triggers are not available under Wine.")
                    Button("Input check") { m.inputCheck() }.controlSize(.small).disabled(m.selected.isEmpty || m.busy)
                        .help("Checks controller + keyboard from macOS through Wine, then opens Wine's Game Controllers panel for a live test.")
                    Menu("Shader caches") {
                        Button("Show sizes") { m.shaderCacheReport() }
                        Button("Clear all (games recompile on next start)", role: .destructive) { m.clearShaderCaches() }
                    }.controlSize(.small).frame(width: 120).disabled(m.selected.isEmpty)
                    Button("Troubleshoot") { m.troubleshoot() }.controlSize(.small)
                    Button("Repair") { m.repair() }.controlSize(.small).disabled(m.selected.isEmpty || m.busy)
                    Button("Clean up") { m.runCleanUp() }.controlSize(.small).disabled(m.busy)
                        .help("Removes temp files, crash dumps, old logs, used installers and download caches. Keeps one previous version of each driver and engine and the two newest safety clones. Runs by itself once a day.")
                        .help("Kills stuck Wine processes and restores the bottle defaults: SDL controllers, 96 DPI, Steam overrides.")
                }
                ScrollView { Text(m.log).font(.system(.caption, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }
                    .frame(height: 160).background(.black.opacity(0.08))
            }.padding()
        }
        .frame(minWidth: 760, minHeight: 700)
        .sheet(isPresented: $showWIR) { willItRunSheet }
        .sheet(isPresented: Binding(get: { modExe != nil }, set: { if !$0 { modExe = nil } })) { modsSheet }
        .sheet(isPresented: $showSnaps) { snapshotsSheet }
        .sheet(isPresented: $showImport) { importBottlesSheet }
        .sheet(isPresented: $showTerms) { termsSheet }
        .sheet(isPresented: $showD3DM) { d3dmetalSheet }
        .sheet(isPresented: Binding(get: { loginStore != nil }, set: { if !$0 { loginStore = nil } })) { storeLoginSheet }
        .sheet(isPresented: Binding(get: { optExe != nil }, set: { if !$0 { optExe = nil } })) { optionsSheet }
        .confirmationDialog("Delete bottle \"\(m.selected)\" and everything in it?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { m.deleteBottle() }
        }
        .confirmationDialog("Uninstall \"\(uninstallExe.map(appName) ?? "")\"?", isPresented: Binding(get: { uninstallExe != nil }, set: { if !$0 { uninstallExe = nil } }), titleVisibility: .visible) {
            Button("Uninstall", role: .destructive) { if let e = uninstallExe { m.uninstall(e) }; uninstallExe = nil }
        } message: { Text(uninstallExe.map { m.uninstallKind($0) + ". Saves and settings in the bottle stay." } ?? "") }
        .onOpenURL { url in   // §7.7 Shortcuts / Siri: a Shortcut that opens cosmopolitan://launch?name=Steam (Siri runs Shortcuts by name)
            guard url.scheme == "cosmopolitan", url.host == "launch", let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "name" })?.value else { return }
            if let p = m.programs.first(where: { appName($0).localizedCaseInsensitiveCompare(q) == .orderedSame }) ?? m.programs.first(where: { appName($0).localizedCaseInsensitiveContains(q) }) { m.launch(p) }
            else { m.log += "Shortcut asked for “\(q)”: no such program in \(m.selected).\n" }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { ps in
            ps.first?.loadItem(forTypeIdentifier: "public.file-url") { d, _ in
                if let d = d as? Data, let u = URL(dataRepresentation: d, relativeTo: nil) { Task { @MainActor in m.install(u) } } }
            return true }
    }
    func pick() {
        let p = NSOpenPanel(); p.allowedContentTypes = ["exe", "msi"].compactMap { UTType(filenameExtension: $0) }
        if p.runModal() == .OK, let u = p.url { m.install(u) }
    }
}
