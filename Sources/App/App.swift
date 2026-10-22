import SwiftUI
import Sparkle

let updater = SPUStandardUpdaterController(startingUpdater: !isTestBuild, updaterDelegate: nil, userDriverDelegate: nil)

@main struct CosmopolitanApp: App {
    // Terminal use: Cosmopolitan.app/Contents/MacOS/Cosmopolitan --troubleshoot [bottle] | --repair [bottle]  (same code as the buttons)
    init() {
        enterTestModeIfNeeded()   // first, before any path is computed
        let a = CommandLine.arguments
        let modes = ["--settings", "--setup", "--session-end", "--troubleshoot", "--repair", "--input", "--find", "--status", "--check", "--update", "--launch", "--tune", "--tunesteam", "--newbottle", "--accept-d3dmetal", "--snapshot", "--rollback", "--importables", "--import", "--willitrun", "--bugreport", "--hints", "--offline", "--compress", "--shaders", "--volumes", "--offlineexe", "--uslayout", "--hudocr", "--saves", "--mods", "--addmod", "--mod", "--rumble", "--padmode", "--procs", "--clean-driver-copies", "--sweep-registry", "--tree-hash", "--install-d3dmetal", "--print-env", "--install-runtime"]   // --launch <bottle> <exe> [seconds]   // --check <bottle> <exe>: dry-run of the launch check
        guard let i = a.firstIndex(where: { modes.contains($0) }) else { return }
        cliMode = true
        let m = Model()
        if i + 1 < a.count, FileManager.default.fileExists(atPath: "\(bottlesDir)/\(a[i + 1])/drive_c") { m.selected = a[i + 1]; m.scan() }   // only real bottles: caches must never create one
        switch a[i] {
        case "--repair": m.repair(); case "--input": m.inputCheck(); case "--find": m.findApps(); case "--update": m.log += Model.performUpdate(install: a.contains("--install"))
        case "--tunesteam": m.tuneSteam()
        case "--newbottle": if i + 1 < a.count { m.createBottle(a[i + 1]); RunLoop.main.run(until: Date().addingTimeInterval(90)) }   // --newbottle <name>
        case "--accept-d3dmetal": m.acceptD3DMetal()   // same action as the "I accept" button; for the user's own scripting only
        case "--snapshot": m.snapshot(a.count > i + 2 ? a[i + 2] : "manual")
        case "--willitrun": if i + 2 < a.count { m.log += m.willItRun(a[i + 2]) }
        case "--bugreport": m.copyBugReport(); m.log += NSPasteboard.general.string(forType: .string)?.components(separatedBy: "\n").prefix(6).joined(separator: "\n") ?? ""; m.log += "\n"
        case "--hints": m.log += m.powerHints().isEmpty ? "no power/thermal hints right now\n" : m.powerHints()
        case "--offline": m.offlineCheck()
        case "--shaders": m.shaderCacheReport()
        case "--hudocr": if i + 2 < a.count { m.log += "fps read from image: \(Model.hudFPS(in: a[i + 2]).map { String($0) } ?? "none")\n" }
        case "--saves": if i + 2 < a.count { m.log += "save folders: \(m.saveFolders(a[i + 2]))\n" }
        case "--mods": if i + 2 < a.count { m.log += "\(m.mods(a[i + 2]))\n" }
        case "--addmod": if i + 3 < a.count { m.addMod(a[i + 2], from: a[i + 3]) }
        case "--mod": if i + 4 < a.count { m.setMod(a[i + 2], a[i + 3], enabled: a[i + 4] == "on") }
        case "--rumble": m.testRumble(); RunLoop.main.run(until: Date().addingTimeInterval(2))
        case "--settings":   // what the app decides from each setting, through the same code that uses it
            print("engine setting      → wine used: \(wineBin)  (installed: \(engineOK))")
            print("autostartSteam      → autostart allowed: \(m.autostartAllowed())")
            print("compatReports       → long session offers a report: \(Model.shouldOfferReport(enabled: UserDefaults.standard.bool(forKey: "compatReports"), seconds: 600, alreadyOffered: false))")
        case "--clean-driver-copies": let r = Model.cleanDriverCopies(m.selected); m.log += r.isEmpty ? "\(m.selected): no driver copies in system32/syswow64.\n" : "\(m.selected): moved \(r.count) driver copies:\n" + r.map { "  " + $0 }.joined(separator: "\n") + "\n"
        case "--sweep-registry": let r = m.sweepRegistry(m.selected); m.log += r.isEmpty ? "\(m.selected): no registry settings to remove.\n" : "\(m.selected): removed \(r.count) registry settings:\n" + r.map { "  " + $0 }.joined(separator: "\n") + "\n"
        case "--tree-hash": for p in a.dropFirst(i + 1) { m.log += "\(treeHash(p) ?? "unreadable")  \(p)\n" }
        case "--install-d3dmetal": if i + 1 < a.count { m.installD3DMetal(from: a[i + 1], confirmed: a.contains("--yes")) }
        case "--print-env": for (k, v) in launchEnv(m.selected).sorted(by: { $0.key < $1.key }) { m.log += "\(k)=\(v)\n" }
        case "--install-runtime": if i + 2 < a.count, let r = Runtime(rawValue: a[i + 2]) { Model.installRuntime(r, prefix: "\(bottlesDir)/\(m.selected)") { m.log += $0 } } else { m.log += "usage: --install-runtime <bottle> vcredist86|vcredist64|directx\n" }
        case "--setup": let ok = Model.performSetup(engine: engineName) { s, p in print(String(format: "[%3.0f%%] ", p * 100) + s) }; print(ok ? "setup ok" : "setup failed"); if !ok { exit(1) }
        case "--session-end": if i + 2 < a.count {   // test the report offer: --session-end <exe> <seconds> [on|off]; prints, never opens anything
            if i + 3 < a.count { UserDefaults.standard.set(a[i + 3] == "on", forKey: "compatReports") }
            let r = m.sessionEnded(a[i + 1], seconds: Double(a[i + 2]) ?? 0, ask: { print("ASK: " + $0); return true }, open: { print("WOULD OPEN (browser form, unsubmitted): " + $0.absoluteString.prefix(140)) })
            print("RESULT: " + r) }
        case "--procs": if i + 2 < a.count { m.log += "pids containing \"\(a[i + 2])\": \(procFind(a[i + 2]))  steamRunning: \(m.steamRunning())  controllers: \(nativeControllers())  battery: \(onBattery())\n" }
        case "--padmode": if i + 2 < a.count { let changed = m.ensureControllerMode(for: a[i + 2]); m.log += "changed: \(changed); hidraw disabled now: \(m.hidrawDisabled())\n" }
        case "--uslayout":   // test: switch to US for 3 s, then restore
            let before = Model.currentLayoutID(); m.log += "before: \(before)\n"
            m.log += "select US: \(Model.selectLayout("com.apple.keylayout.US")) → now \(Model.currentLayoutID())\n"
            Thread.sleep(forTimeInterval: 3); Model.selectLayout(before); m.log += "restored: \(Model.currentLayoutID())\n"
        case "--volumes": m.log += (m.externalVolumes().isEmpty ? "no writable external volumes" : m.externalVolumes().joined(separator: "\n")) + "\n"
        case "--offlineexe": if i + 2 < a.count { m.log += (m.offlineExe(a[i + 2]) ?? "no offline launcher found") + "\n" }
        case "--compress": if i + 2 < a.count { m.compressGame(a[i + 2]); RunLoop.main.run(until: Date().addingTimeInterval(120)) }
        case "--rollback": if let s = m.snapshots().first { m.rollback(to: s.path); RunLoop.main.run(until: Date().addingTimeInterval(40)) } else { m.log += "no snapshots\n" }
        case "--importables": m.log += m.importableBottles().map { "\($0.label)\t\($0.path)" }.joined(separator: "\n") + "\n"
        case "--import": if i + 3 < a.count { m.importBottle(a[i + 2], as: a[i + 3]); RunLoop.main.run(until: Date().addingTimeInterval(60)) }
        case "--tune": if i + 2 < a.count { m.log += m.tuneUnreal(a[i + 2]) ?? "nothing to tune (no settings file yet, or already tuned)\n" }
        case "--launch": if i + 2 < a.count {   // --launch <bottle> <exe> [max seconds, default 120]: returns when the program exits
            let exe = a[i + 2], limit = Double(a.count > i + 3 ? a[i + 3] : "120") ?? 120, t0 = Date(), name = (exe as NSString).lastPathComponent
            m.launch(exe)
            while m.launchExits[exe] == nil, !m.log.contains("\(name) is already running."), Date().timeIntervalSince(t0) < limit { RunLoop.main.run(until: Date().addingTimeInterval(0.5)) }
            let took = String(format: "%.1f", Date().timeIntervalSince(t0))
            m.log += m.launchExits[exe].map { "launch: \(name) exited with code \($0) after \(took) s\n" } ?? "launch: \(name) still running after \(took) s (limit \(Int(limit)) s)\n"
        }
        case "--check": if i + 2 < a.count { let n = m.launchNeeds(a[i + 2]); m.log += n.note + "drivers override: \(n.drivers ?? ["(bottle setting)"]) verbs: \(n.verbs) overrides: \(n.overrides) env: \(n.env) args: \(n.args) desktop: \(n.desktop) light: \(n.status == .green ? "green" : n.status == .yellow ? "yellow" : "red")\n" }
        case "--status": m.log += "d3dmetal: " + (m.d3dmetalNow.map { "\($0.pretty) from \($0.source); features: " + $0.features.sorted().joined(separator: " ") + (d3dmetalOK ? "; license accepted" : "; license not accepted") } ?? "not installed") + "\n"; m.log += "drivers: \(m.driverStatus.0 == .green ? "green" : m.driverStatus.0 == .yellow ? "yellow" : "red") (\(m.driverStatus.1))\ncontroller: \(m.padStatus.0 == .green ? "green" : m.padStatus.0 == .yellow ? "yellow" : "red") (\(m.padStatus.1))\n"
        default: m.troubleshoot() }
        print(m.log); exit(0)
    }
    var body: some Scene {
        WindowGroup("Cosmopolitan") { ContentView().handlesExternalEvents(preferring: ["launch"], allowing: ["*"]) }   // cosmopolitan://launch?name=<program> goes to the existing window, not a new one (§7.7 via Shortcuts/Siri)
            .commands { CommandGroup(after: .appInfo) { Button("Check for Updates…") { updater.checkForUpdates(nil) } } }
        Settings { SettingsView() }
    }
}
