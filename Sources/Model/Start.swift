import SwiftUI

extension Model {
    func start(_ need: Needs, _ cmd: String, _ args: [String], exe: String, block: Bool = false, restartSteam: Bool = false) {
        var go = { self.wine(self.selected, [cmd] + args + need.args, block: block, env: need.env, drivers: need.drivers, exe: exe) }
        focusAutomation(exe); pauseInBackground(exe, anticheat: need.anticheat != nil); trackPlaytime(exe); scanUntrusted(exe); forceKeyboardLayout(exe)
        if steamGames[exe] != nil || exe.hasSuffix("/Steam/steam.exe"), sh("ps -axo command= | grep -c '^C:.Program Files (x86).Steam.steam.exe'").hasPrefix("0") { tuneSteam() }   // Steam is down: safe to edit its config
        // Steam games inherit the env of the *running* Steam, so a per-launch driver change needs Steam restarted with it.
        if restartSteam {
            log += "Restarting Steam so the game gets its drivers…\n"
            let run = go
            go = { Task { @MainActor in await self.stopSteam(); self.tuneSteam(); run() } }
        }
        if need.verbs.isEmpty { go() } else {
            snapshot("before installing \(need.verbs.joined(separator: " "))")
            // Runtime missing: let winetricks fetch it into this bottle first (output streams to the log), then start the program.
            var env = launchEnv(selected); env["WINE"] = wineBin; env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin")
            exec(winetricks!, ["-q"] + need.verbs, env: env) { go() }
        }
    }

    // Launch check: what the exe imports decides the driver set and any runtime to fetch. Nothing is written to the bottle settings.
}
