import SwiftUI
import Sparkle

let updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

@main struct CosmopolitanApp: App {
    // Terminal use: Cosmopolitan.app/Contents/MacOS/Cosmopolitan --troubleshoot [bottle] | --repair [bottle]  (same code as the buttons)
    init() {
        let a = CommandLine.arguments
        let modes = ["--troubleshoot", "--repair", "--input", "--find", "--status", "--check", "--update", "--launch", "--tune", "--tunesteam", "--newbottle", "--accept-d3dmetal", "--snapshot", "--rollback", "--importables", "--import", "--willitrun", "--bugreport", "--hints", "--offline", "--compress", "--shaders", "--volumes", "--offlineexe", "--uslayout"]   // --launch <bottle> <exe> [seconds]   // --check <bottle> <exe>: dry-run of the launch check
        guard let i = a.firstIndex(where: { modes.contains($0) }) else { return }
        cliMode = true
        let m = Model()
        if i + 1 < a.count, FileManager.default.fileExists(atPath: "\(bottlesDir)/\(a[i + 1])/drive_c") { m.selected = a[i + 1]; m.scan() }   // only real bottles: caches must never create one
        switch a[i] {
        case "--repair": m.repair(); case "--input": m.inputCheck(); case "--find": m.findApps(); case "--update": m.log += Model.performUpdate()
        case "--tunesteam": m.tuneSteam()
        case "--newbottle": if i + 1 < a.count { m.createBottle(a[i + 1]); RunLoop.main.run(until: Date().addingTimeInterval(90)) }   // --newbottle <name>
        case "--accept-d3dmetal": m.acceptD3DMetal()   // same action as the "I accept" button; for the user's own scripting only
        case "--snapshot": m.snapshot(a.count > i + 2 ? a[i + 2] : "manual")
        case "--willitrun": if i + 2 < a.count { m.log += m.willItRun(a[i + 2]) }
        case "--bugreport": m.copyBugReport(); m.log += NSPasteboard.general.string(forType: .string)?.components(separatedBy: "\n").prefix(6).joined(separator: "\n") ?? ""; m.log += "\n"
        case "--hints": m.log += m.powerHints().isEmpty ? "no power/thermal hints right now\n" : m.powerHints()
        case "--offline": m.offlineCheck()
        case "--shaders": m.shaderCacheReport()
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
        case "--launch": if i + 2 < a.count { m.launch(a[i + 2]); RunLoop.main.run(until: Date().addingTimeInterval(Double(a.count > i + 3 ? a[i + 3] : "30") ?? 30)) }
        case "--check": if i + 2 < a.count { let n = m.launchNeeds(a[i + 2]); m.log += n.note + "drivers override: \(n.drivers ?? ["(bottle setting)"]) verbs: \(n.verbs) overrides: \(n.overrides) env: \(n.env) args: \(n.args) desktop: \(n.desktop) light: \(n.status == .green ? "green" : n.status == .yellow ? "yellow" : "red")\n" }
        case "--status": m.log += "drivers: \(m.driverStatus.0 == .green ? "green" : m.driverStatus.0 == .yellow ? "yellow" : "red") (\(m.driverStatus.1))\ncontroller: \(m.padStatus.0 == .green ? "green" : m.padStatus.0 == .yellow ? "yellow" : "red") (\(m.padStatus.1))\n"
        default: m.troubleshoot() }
        print(m.log); exit(0)
    }
    var body: some Scene {
        WindowGroup("Cosmopolitan") { ContentView() }   // cosmopolitan://launch?name=<program> handled in ContentView (§7.7 via Shortcuts/Siri)
            .commands { CommandGroup(after: .appInfo) { Button("Check for Updates…") { updater.checkForUpdates(nil) } } }
    }
}
