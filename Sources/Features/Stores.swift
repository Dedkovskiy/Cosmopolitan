import SwiftUI

// Stores. GOG Galaxy and Battle.net are Windows clients: their official installer is downloaded into the bottle and run like any
// installer (same launch checks, snapshot, log), and their games show up in the grid through the normal scan. Epic goes through
// Legendary (open-source, native): the Epic launcher itself is unreliable under Wine, while Legendary signs in, downloads into
// C:\Games\Epic and launches games with Epic's auth parameters, with Cosmopolitan supplying the engine, drivers and env as always.
var epicGames: [String: (id: String, name: String)] = [:]      // exe path -> Legendary app name / title (installed games)
var epicOwned: [(id: String, name: String)] = []                 // signed-in library (refreshed in the background by scan)

enum Store: String, CaseIterable, Identifiable {
    case gog = "GOG Galaxy", battlenet = "Battle.net"
    var id: String { rawValue }
    var url: String {
        switch self {
        case .gog: return "https://webinstallers.gog-statics.com/download/GOG_Galaxy_2.0.exe"
        case .battlenet: return "https://downloader.battle.net/download/getInstaller?os=win&installer=Battle.net-Setup.exe"
        }
    }
    var file: String { self == .gog ? "GOG_Galaxy_2.0.exe" : "Battle.net-Setup.exe" }
    var exes: [String] {
        switch self {
        case .gog: return ["Program Files (x86)/GOG Galaxy/GalaxyClient.exe"]
        case .battlenet: return ["Program Files (x86)/Battle.net/Battle.net Launcher.exe", "Program Files (x86)/Battle.net/Battle.net.exe"]
        }
    }
}

extension Model {
    func storeExe(_ s: Store) -> String? { s.exes.map { "\(bottlesDir)/\(selected)/drive_c/\($0)" }.first { FileManager.default.fileExists(atPath: $0) } }

    // Download the official installer into <bottle>/installers and run it. Battle.net also gets Arial (its UI shows boxes without it)
    // and its client config set to software rendering before the first start, which is the known fix for a black launcher under Wine.
    func installStore(_ s: Store) {
        guard !selected.isEmpty else { log += "Create or select a bottle first.\n"; return }
        let dir = "\(bottlesDir)/\(selected)/installers"; try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let dst = "\(dir)/\(s.file)"
        busy = true; log += "Downloading the \(s.rawValue) installer…\n"
        Task.detached {
            let r = shell("curl -fsSL --retry 3 -o '\(dst)' '\(s.url)' 2>&1 && echo __ok")
            await MainActor.run {
                self.busy = false
                guard r.contains("__ok") else { self.log += "Download failed: \(r)\n"; return }
                if s == .battlenet { self.battlenetConfig() }
                self.log += "\(s.rawValue): follow the installer; the client appears in the grid when it is done.\n"
                var need = self.prepare(dst)
                if s == .battlenet, winetricks != nil, !need.verbs.contains("arial") { need.verbs.append("arial") }
                self.start(need, dst, [], exe: dst, block: true)
            }
        }
    }

    // Battle.net.config: hardware acceleration and streaming off (CEF under Wine renders black otherwise). Merged, never clobbered.
    func battlenetConfig() {
        let p = "\(bottlesDir)/\(selected)/drive_c/users/\(NSUserName())/AppData/Roaming/Battle.net/Battle.net.config"
        var cfg = (try? JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: p)))) as? [String: Any] ?? [:]
        var client = cfg["Client"] as? [String: Any] ?? [:]
        var streaming = client["Streaming"] as? [String: Any] ?? [:]
        streaming["StreamingEnabled"] = "false"; client["Streaming"] = streaming; client["HardwareAcceleration"] = "false"; cfg["Client"] = client
        try? FileManager.default.createDirectory(atPath: (p as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        if let d = try? JSONSerialization.data(withJSONObject: cfg, options: [.prettyPrinted, .sortedKeys]) { try? d.write(to: URL(fileURLWithPath: p)) }
    }

    // Extra places the plain scan does not look: GOG's games folders (one level deeper) and Legendary's installed Epic games.
    func storeGames() -> [String] {
        let c = "\(bottlesDir)/\(selected)/drive_c", fm = FileManager.default
        var out: [String] = []
        for root in ["Program Files (x86)/GOG Galaxy/Games", "GOG Games", "Program Files (x86)/GOG Games"] {
            for game in (try? fm.contentsOfDirectory(atPath: "\(c)/\(root)")) ?? [] where !game.hasPrefix(".") {
                for f in (try? fm.contentsOfDirectory(atPath: "\(c)/\(root)/\(game)")) ?? [] where f.lowercased().hasSuffix(".exe") && !skipExes.contains(where: { f.lowercased().contains($0) }) && !f.lowercased().hasPrefix("unins") {
                    out.append("\(c)/\(root)/\(game)/\(f)")
                }
            }
        }
        epicGames = [:]
        if let l = legendary, let data = shell("'\(l)' list-installed --json 2>/dev/null").data(using: .utf8),
           let list = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] {
            for g in list {
                guard let path = g["install_path"] as? String, path.hasPrefix(c), let exe = g["executable"] as? String, let id = g["app_name"] as? String else { continue }
                let p = "\(path)/\(exe.replacingOccurrences(of: "\\", with: "/"))"
                if fm.fileExists(atPath: p) { epicGames[p] = (id, g["title"] as? String ?? id); out.append(p) }
            }
            // Owned library for the Install menu: network call, so off the main thread; the menu reads the global when it opens.
            if epicSignedIn() { Task.detached { let s = shell("'\(l)' list --json 2>/dev/null"); if let d = s.data(using: .utf8), let arr = (try? JSONSerialization.jsonObject(with: d)) as? [[String: Any]] {
                epicOwned = arr.compactMap { g in (g["app_name"] as? String).map { ($0, g["app_title"] as? String ?? $0) } }.sorted { $0.1 < $1.1 } } } }
        }
        return out
    }

    // Legendary is not in Homebrew; pipx puts it in ~/.local/bin.
    var legendary: String? { ["/opt/homebrew/bin/legendary", NSHomeDirectory() + "/.local/bin/legendary", "/usr/local/bin/legendary"].first { FileManager.default.fileExists(atPath: $0) } }
    func epicSignedIn() -> Bool { legendary != nil && FileManager.default.fileExists(atPath: NSHomeDirectory() + "/.config/legendary/user.json") }
    func installLegendary() {
        exec("/bin/sh", ["-c", "command -v pipx >/dev/null || brew install pipx; pipx install legendary-gl"], env: ["PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"]) {
            self.log += self.legendary == nil ? "Legendary did not install; see the log above.\n" : "Legendary installed. Stores… › Sign in to Epic Games.\n"
        }
    }
    static let epicLoginURL = URL(string: "https://legendary.gl/epiclogin")!   // Epic's own login; the page then shows an authorizationCode
    func epicSignIn(code: String) {
        guard let l = legendary else { return }
        let c = code.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        exec(l, ["auth", "--code", c]) { self.scan(); if self.epicSignedIn() { self.log += "Signed in to Epic Games. Stores… › Install Epic game.\n" } }
    }
    func epicSignOut() { guard let l = legendary else { return }; epicOwned = []; exec(l, ["auth", "--delete"]) { self.scan() } }
    // Downloads into <bottle>/drive_c/Games/Epic/<Game>; progress streams to the log; the tile appears when the download is done.
    func installEpic(_ app: String) {
        guard let l = legendary else { return }
        snapshot("before installing Epic game \(app)")
        exec(l, ["install", app, "--base-path", "\(bottlesDir)/\(selected)/drive_c/Games/Epic", "-y"], block: false) { self.scan() }
    }
    // Launch through Legendary so the game gets Epic's auth arguments; Legendary runs our loader copy with our env (prefix, drivers, options).
    func launchEpic(_ app: String, exe: String) {
        guard let l = legendary else { return }
        let need = prepare(exe)
        var env = launchEnv(selected, drivers: need.drivers).merging(need.env) { $1 }
        env["WINEPREFIX"] = "\(bottlesDir)/\(selected)"
        let args = ["launch", app, "--wine", loaderNamed(exe), "--wine-prefix", env["WINEPREFIX"]!] + (epicOnline() ? [] : ["--offline"]) + need.args + extraArgs(exe)
        start(need, "", [], exe: exe, runner: { self.exec(l, args, env: env, block: false, exe: exe) })
    }
    func epicOnline() -> Bool { shell("curl -s -m 3 -o /dev/null -w '%{http_code}' https://account-public-service-prod.ol.epicgames.com/ 2>/dev/null").hasPrefix("4") || shell("curl -s -m 3 -o /dev/null -w '%{http_code}' https://www.epicgames.com/ 2>/dev/null").hasPrefix("2") }
}
