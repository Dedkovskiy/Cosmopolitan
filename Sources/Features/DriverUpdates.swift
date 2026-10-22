import SwiftUI

extension Model {
    // Driver updates from upstream GitHub releases. D3DMetal is Apple's and only ships with the Sikarugir template (brew upgrade), so it's not here.
    // ponytail: "installed" = the version file mentions the release tag; the Sikarugir builds carry extra commits on top of a tag.
    nonisolated static let driverSources = [("dxmt", "3Shain/dxmt", "-builtin.tar.gz"), ("dxvk", "Gcenx/DXVK-macOS", "-builtin.tar.gz")]
    nonisolated static func latestDriverTags() -> [(name: String, tag: String, url: String, installed: String)] {
        Model.driverSources.compactMap { name, repo, suffix in
            let j = shell("curl -s -m 8 https://api.github.com/repos/\(repo)/releases/latest")
            guard let tag = j.components(separatedBy: "\"tag_name\": \"").dropFirst().first?.components(separatedBy: "\"").first,
                  let url = j.components(separatedBy: "\"browser_download_url\": \"").dropFirst().map({ $0.components(separatedBy: "\"")[0] }).first(where: { $0.hasSuffix(suffix) }) else { return nil }
            let installed = ((try? String(contentsOfFile: "\(driversDir)/\(name)/version", encoding: .utf8)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return (name, tag, url, installed)
        }
    }
    nonisolated static func isCurrent(_ d: (name: String, tag: String, url: String, installed: String)) -> Bool {
        let num = d.tag.components(separatedBy: CharacterSet(charactersIn: "-_")).first ?? d.tag   // "v1.10.3-20230507-repack" -> "v1.10.3"
        return d.installed.contains(num)
    }
    // All the work, off the main thread. Returns the log text. Previous versions are kept as <name>.old for a manual swap back.
    nonisolated static func performUpdate() -> String {
        var out = ""
        let list = latestDriverTags()
        if list.isEmpty { out += "Driver update: could not reach GitHub.\n" }
        for d in list {
            if isCurrent(d) { out += "✓ \(d.name) is current (\(d.installed), upstream \(d.tag))\n"; continue }
            out += "↓ \(d.name) \(d.tag) — downloading…\n"
            let tmp = NSTemporaryDirectory() + "cosmo-\(d.name)-\(d.tag)"; _ = shell("rm -rf '\(tmp)'; mkdir -p '\(tmp)'")
            let found = shell("cd '\(tmp)' && curl -sL -m 300 -o pkg.tar.gz '\(d.url)' && tar xzf pkg.tar.gz && find . -type d -name x86_64-windows | head -1")
            guard !found.isEmpty else { out += "✗ \(d.name): download or unpack failed\n"; continue }
            let src = (tmp + "/" + found) as NSString   // …/x86_64-windows -> its parent is the new 'wine' dir
            let dst = "\(driversDir)/\(d.name)"
            _ = shell("rm -rf '\(dst).old'; mv '\(dst)' '\(dst).old' 2>/dev/null; mkdir -p '\(dst)' && cp -R '\(src.deletingLastPathComponent)/.' '\(dst)/wine/' && printf '%s\\n' '\(d.tag)' > '\(dst)/version'; rm -rf '\(tmp)'")
            if FileManager.default.fileExists(atPath: dst + "/wine/x86_64-windows") { out += "✓ \(d.name) updated to \(d.tag) (previous kept as \(d.name).old)\n" }
            else { _ = shell("rm -rf '\(dst)'; mv '\(dst).old' '\(dst)'"); out += "✗ \(d.name): install failed, previous version restored\n" }
        }
        // One previous version per driver (<name>.old) stays until the next update replaces it: the rollback is always there if needed.
        // Newest Sikarugir template (carries D3DMetal and the engine's dylibs): fetch it ourselves if the Creator app hasn't.
        let tpl = NSHomeDirectory() + "/Library/Application Support/Sikarugir/Template"
        let newestTpl = shell("curl -s -m 8 https://sikarugir-app.github.io/Template/NewestVersion.txt").trimmingCharacters(in: .whitespacesAndNewlines)
        if newestTpl.hasPrefix("Template-"), !FileManager.default.fileExists(atPath: "\(tpl)/\(newestTpl).app") {
            out += "↓ Sikarugir \(newestTpl) — downloading…\n"
            let r = shell("mkdir -p '\(tpl)' && cd '\(tpl)' && curl -sL -m 600 -o '\(newestTpl).tar.xz' 'https://github.com/Sikarugir-App/Template/releases/download/v1.0/\(newestTpl).tar.xz' && tar xf '\(newestTpl).tar.xz' && rm -f '\(newestTpl).tar.xz' && ls -d \(newestTpl)*.app | head -1")
            out += r.hasSuffix(".app") ? "✓ \(newestTpl) installed\n" : "✗ \(newestTpl): download failed\n"
        }
        // Newest Sikarugir Wine engine: downloaded and prepared side by side, never switched automatically
        // (Wine 11.x still renders Steam black on macOS 27; switching is a tested, manual step).
        let newestEng = shell("curl -s -m 8 https://sikarugir-app.github.io/Engines/EngineList.txt | grep '^WS12WineSikarugir' | head -1")
        // engines/.rejected lists engines already tested and found not to run here; they are not downloaded again.
        let rejected = ["WS12WineSikarugir11.0_1"] + ((try? String(contentsOfFile: "\(support)/engines/.rejected", encoding: .utf8)) ?? "").components(separatedBy: "\n")   // 11.0_1: children die on macOS 27 (tested)
        if !newestEng.isEmpty, !rejected.contains(newestEng), !FileManager.default.fileExists(atPath: "\(support)/engines/\(newestEng)") {
            out += "↓ engine \(newestEng) — fetching…\n"
            let local = NSHomeDirectory() + "/Library/Application Support/Sikarugir/Engines/\(newestEng).tar.xz"
            let dst = "\(support)/engines/\(newestEng)"
            let get = FileManager.default.fileExists(atPath: local) ? "cp '\(local)' eng.tar.xz" : "curl -sL -m 900 -o eng.tar.xz 'https://github.com/Sikarugir-App/Engines/releases/download/v1.0/\(newestEng).tar.xz'"
            _ = shell("mkdir -p '\(dst)' && cd '\(dst)' && \(get) && tar xf eng.tar.xz && rm -f eng.tar.xz")
            if FileManager.default.fileExists(atPath: dst + "/wswine.bundle/bin/wine") { out += prepareEngine(dst + "/wswine.bundle") + "✓ engine \(newestEng) ready at \(dst) (not active; current engine unchanged)\n" }
            else { _ = shell("rm -rf '\(dst)'"); out += "✗ engine \(newestEng): download failed\n" }
        }
        // D3DMetal is Apple's and is never fetched or synced automatically (license rule): the user installs it from Apple's own download via Drivers › D3DMetal….
        out += FileManager.default.fileExists(atPath: driversDir + "/d3dmetal/wine") ? (d3dmetalOK ? "✓ d3dmetal present, Apple's license accepted\n" : "• d3dmetal present, Apple's license not accepted yet (Drivers › D3DMetal…)\n") : "• d3dmetal not installed (optional, needed for Direct3D 12)\n"
        FileManager.default.createFile(atPath: support + "/.driver-check", contents: nil)
        return out
    }
}
