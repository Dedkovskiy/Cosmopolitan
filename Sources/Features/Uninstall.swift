import AppKit

// Uninstall from the tile's right-click menu, the way each program wants to be removed:
//  • Steam game  → Steam's own uninstall (steam://uninstall/<appid>), so its library stays consistent;
//  • Epic game   → `legendary uninstall`;
//  • anything with its own uninstaller (unins000.exe, uninstall.exe, …) → that uninstaller, under Wine;
//  • otherwise   → the program's folder goes to the macOS Trash (recoverable), plus its Find-apps entry.
// Saves in AppData and the bottle itself are never touched.
extension Model {
    func uninstallKind(_ exe: String) -> String {
        if steamGames[exe] != nil { return "Steam will remove it" }
        if epicGames[exe] != nil { return "Legendary will remove it" }
        if uninstaller(exe) != nil { return "its own uninstaller will run" }
        return "its folder goes to the Trash (you can restore it from there)"
    }
    func uninstaller(_ exe: String) -> String? {
        let root = appRoot(exe).root, fm = FileManager.default
        guard let en = fm.enumerator(atPath: root) else { return nil }
        for case let p as String in en {
            if en.level > 2 { en.skipDescendants(); continue }
            let n = (p as NSString).lastPathComponent.lowercased()
            if n.hasSuffix(".exe"), n.hasPrefix("unins") || n.hasPrefix("uninstall") || n == "uninst.exe" { return "\(root)/\(p)" }
        }
        return nil
    }
    func uninstall(_ exe: String) {
        let b = bottleOf(exe); if b != selected { selected = b; scan() }   // the Library holds every bottle's games
        let name = appName(exe)
        if let g = steamGames[exe], let r = exe.range(of: "/steamapps/") {
            let steam = String(exe[..<r.lowerBound]) + "/steam.exe"
            log += "Asking Steam to uninstall \(name)…\n"
            wine(selected, [winPath(steam), "steam://uninstall/\(g.id)"], block: false)
        } else if let g = epicGames[exe], let l = legendary {
            exec(l, ["uninstall", g.id, "-y"]) { self.log += "\(name) uninstalled.\n"; self.scan() }
        } else if let u = uninstaller(exe) {
            log += "Running \(name)'s uninstaller…\n"
            wine(selected, [winPath(u)], exe: u, then: { self.scan() })
        } else {
            let root = appRoot(exe).root
            guard root.contains("/drive_c/") else { return }   // never anything outside the bottle
            do { try FileManager.default.trashItem(at: URL(fileURLWithPath: root), resultingItemURL: nil); log += "\(name) moved to the Trash.\n" }
            catch { log += "Could not remove \(name): \(error.localizedDescription)\n" }
            let list = "\(bottlesDir)/\(selected)/cosmopolitan.apps"
            if let t = try? String(contentsOfFile: list, encoding: .utf8) {
                try? t.components(separatedBy: "\n").filter { !$0.hasPrefix(root) }.joined(separator: "\n").write(toFile: list, atomically: true, encoding: .utf8)
            }
            scan()
        }
    }
}
