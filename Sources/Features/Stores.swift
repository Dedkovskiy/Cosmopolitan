import SwiftUI

// Stores. Battle.net is a Windows client: its official installer is downloaded into the bottle and run like any installer (same launch
// checks, snapshot, log), and its games show up in the grid through the normal scan. Epic and GOG go through native open-source
// clients instead of their Windows launchers: Legendary (Epic) and lgogdownloader (GOG) sign in, list the library and download games
// into the bottle; Cosmopolitan launches them with the engine, drivers and options it uses for everything else.
// (GOG Galaxy 2.1 was tried first: its Qt 6 UI needs a render backend and fails the Direct3D 11 probe under every layer available here,
// D3DMetal, DXMT, DXVK and Wine's own, so its windows never get drawn. GOG games are DRM-free, so nothing is lost without it.)
var epicGames: [String: (id: String, name: String)] = [:]      // exe path -> Legendary app name / title (installed games)
var epicOwned: [(id: String, name: String)] = []                 // signed-in Epic library (refreshed in the background by scan)
var gogOwned: [(id: String, name: String)] = []                  // signed-in GOG library: gamename slug / title

enum Store: String, CaseIterable, Identifiable {
    case battlenet = "Battle.net"
    var id: String { rawValue }
    var url: String { "https://downloader.battle.net/download/getInstaller?os=win&installer=Battle.net-Setup.exe" }
    var file: String { "Battle.net-Setup.exe" }
    var exes: [String] { ["Program Files (x86)/Battle.net/Battle.net Launcher.exe", "Program Files (x86)/Battle.net/Battle.net.exe"] }
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

    // Extra places the plain scan does not look: GOG game folders (one level deeper) and Legendary's installed Epic games.
    // Also refreshes the owned-library lists for the Install menus in the background (network calls, off the main thread).
    func storeGames() -> [String] {
        let c = "\(bottlesDir)/\(selected)/drive_c", fm = FileManager.default
        var out: [String] = []
        for root in ["GOG Games", "Program Files (x86)/GOG Galaxy/Games", "Program Files (x86)/GOG Games"] {
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
            // `list --json` came back empty for this account while the plain listing (with -T for third-party-managed titles) had the
            // games, so the text form is parsed:  " * Title (App name: xyz | Version: …)"; "  + …" lines are DLC and are skipped.
            if epicSignedIn() { Task.detached {
                let s = shell("'\(l)' list --platform Windows -T 2>/dev/null")   // on macOS Legendary defaults to the Mac platform, which lists nothing here
                var owned: [(id: String, name: String)] = []
                for line in s.components(separatedBy: "\n") where line.hasPrefix(" * ") {
                    guard let r = line.range(of: " (App name: ") else { continue }
                    let title = String(line.dropFirst(3)[..<r.lowerBound]), rest = line[r.upperBound...]
                    let id = String(rest.prefix { $0 != " " && $0 != "|" && $0 != ")" })
                    if !id.isEmpty { owned.append((id, title)) }
                }
                epicOwned = owned.sorted { $0.1 < $1.1 }
            } }
        }
        if let g = lgog, gogSignedIn(), gogOwned.isEmpty { Task.detached {
            let s = shell("'\(g)' --list json --platform w 2>/dev/null")
            guard let d = s.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: d) else { return }
            let arr = (obj as? [[String: Any]]) ?? ((obj as? [String: Any])?["games"] as? [[String: Any]]) ?? []
            gogOwned = arr.compactMap { g in (g["gamename"] as? String).map { ($0, g["title"] as? String ?? $0) } }.sorted { $0.1 < $1.1 }
        } }
        return out
    }

    // ---- Epic (Legendary) ----
    // Legendary is not in Homebrew; pipx puts it in ~/.local/bin.
    var legendary: String? { ["/opt/homebrew/bin/legendary", NSHomeDirectory() + "/.local/bin/legendary", "/usr/local/bin/legendary"].first { FileManager.default.fileExists(atPath: $0) } }
    func epicSignedIn() -> Bool { legendary != nil && FileManager.default.fileExists(atPath: NSHomeDirectory() + "/.config/legendary/user.json") }
    func installLegendary() {
        exec("/bin/sh", ["-c", "command -v pipx >/dev/null || brew install pipx; pipx install legendary-gl"], env: ["PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"]) {
            self.log += self.legendary == nil ? "Legendary did not install; see the log above.\n" : "Legendary installed. Stores… › Sign in to Epic Games.\n"
        }
    }
    // Epic's login with the redirect to the code endpoint (Legendary's client id). The in-app web view uses a private session, so this is
    // always a fresh login, which is the only place Epic shows pending policy acceptances (a signed-in browser otherwise lands on
    // "corrective_action_required" instead of the authorizationCode).
    static let epicLoginURL = URL(string: "https://www.epicgames.com/id/login?redirectUrl=https%3A%2F%2Fwww.epicgames.com%2Fid%2Fapi%2Fredirect%3FclientId%3D34a02cf8f4414e29b15921876da36f9a%26responseType%3Dcode")!
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
        exec(l, ["install", app, "--platform", "Windows", "--base-path", "\(bottlesDir)/\(selected)/drive_c/Games/Epic", "-y"], block: false) { self.scan() }
    }
    // Legendary only describes the launch (`launch --json`: exe, Epic's auth arguments, env); Cosmopolitan starts Wine itself, as for every
    // other program. Letting Legendary spawn Wine does not work: it exits right after spawning, its pipes close, and the game dies on
    // its first write to stderr.
    func launchEpic(_ app: String, exe: String) {
        guard let l = legendary else { return }
        var need = prepare(exe)
        let js = shell("'\(l)' launch '\(app)' --json --wine '\(wineBin)' --wine-prefix '\(bottlesDir)/\(selected)' 2>/dev/null")
        guard let d = js.data(using: .utf8), let info = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else {
            log += "Legendary could not prepare the launch (not signed in, or the game needs an update: Stores… › Sign in / reinstall).\n"; return
        }
        for k in ["game_parameters", "egl_parameters", "user_parameters"] { need.args += (info[k] as? [String]) ?? [] }
        for (k, v) in (info["environment"] as? [String: String]) ?? [:] where k != "CX_BOTTLE" && k != "WINEPREFIX" { need.env[k] = v }
        start(need, winPath(exe), extraArgs(exe), exe: exe)
    }

    // ---- GOG (lgogdownloader) ----
    var lgog: String? { ["/opt/homebrew/bin/lgogdownloader", "/usr/local/bin/lgogdownloader"].first { FileManager.default.fileExists(atPath: $0) } }
    func gogSignedIn() -> Bool {
        lgog != nil && ((try? FileManager.default.attributesOfItem(atPath: NSHomeDirectory() + "/.config/lgogdownloader/galaxy_tokens.json"))?[.size] as? Int ?? 0) > 20
    }
    func installLgog() { exec("/bin/sh", ["-c", "brew install lgogdownloader"], env: ["PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"]) { self.log += self.lgog == nil ? "lgogdownloader did not install; see the log above.\n" : "lgogdownloader installed. Stores… › Sign in to GOG.\n" } }
    // GOG's own login page (what lgogdownloader --browser-login prints); after login the browser lands on embed.gog.com/on_login_success?…code=…
    static let gogLoginURL = URL(string: "https://auth.gog.com/auth?client_id=46899977096215655&redirect_uri=https%3A%2F%2Fembed.gog.com%2Fon_login_success%3Forigin%3Dclient&response_type=code&layout=default&brand=gog")!
    func gogSignIn(redirectURL: String) {
        guard let g = lgog else { return }
        let u = redirectURL.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "'", with: "")
        exec("/bin/sh", ["-c", "printf '%s\\n' '\(u)' | '\(g)' --browser-login"]) { gogOwned = []; self.scan(); if self.gogSignedIn() { self.log += "Signed in to GOG. Stores… › Install GOG game (the library takes a moment to load).\n" } }
    }
    func gogSignOut() { gogOwned = []; for f in ["galaxy_tokens.json", "cookies.txt"] { try? FileManager.default.removeItem(atPath: NSHomeDirectory() + "/.config/lgogdownloader/" + f) }; scan() }
    func gogInstalled() -> Set<String> { Set((try? FileManager.default.contentsOfDirectory(atPath: "\(bottlesDir)/\(selected)/drive_c/GOG Games")) ?? []) }
    // Installs the Windows build straight from GOG's content system into C:\GOG Games\<gamename> (DRM-free, no installer to click through).
    func installGog(_ gamename: String) {
        guard let g = lgog else { return }
        snapshot("before installing GOG game \(gamename)")
        let dir = "\(bottlesDir)/\(selected)/drive_c/GOG Games"; try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        exec(g, ["--galaxy-install", gamename, "--galaxy-platform", "w", "--directory", dir, "--no-color", "--no-unicode", "--no-window-progress"], block: false) { self.scan() }
    }
}
