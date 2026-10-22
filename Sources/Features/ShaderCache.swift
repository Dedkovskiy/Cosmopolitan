import SwiftUI

// §6.4 Shader caches: where the translation layers and games keep compiled shaders, how big they are, and a way to clear them
// (a cleared cache means the first minutes of a game stutter again while it rebuilds). Pre-warming is not possible from outside the game.
extension Model {
    func shaderCacheDirs() -> [(String, String)] {
        let b = "\(bottlesDir)/\(selected)", h = NSHomeDirectory()
        var out: [(String, String)] = [("Steam shader cache", "\(b)/drive_c/Program Files (x86)/Steam/steamapps/shadercache")]
        for d in (try? FileManager.default.contentsOfDirectory(atPath: "\(h)/Library/Caches")) ?? [] where d.lowercased().contains("d3dmetal") || d.lowercased().contains("dxmt") || d.lowercased().contains("metal") && d.lowercased().contains("shader") { out.append((d, "\(h)/Library/Caches/\(d)")) }
        let ue = shell("find '\(b)/drive_c/users' -maxdepth 6 -name '*.upipelinecache' 2>/dev/null | head -20").split(separator: "\n").map(String.init)
        for f in ue { out.append(("Unreal PSO cache: \((f as NSString).lastPathComponent)", f)) }
        return out.filter { FileManager.default.fileExists(atPath: $0.1) }
    }
    func shaderCacheReport() {
        var out = "── Shader caches (\(selected)) ──\n"
        for (n, p) in shaderCacheDirs() { out += "  \(sh("du -sh '\(p)' 2>/dev/null | cut -f1"))\t\(n)\n" }
        if shaderCacheDirs().isEmpty { out += "  none found yet (they appear after games have run)\n" }
        out += "Clearing forces games to recompile shaders on their next start (slower first minutes), useful after a driver update that produces glitches.\n──\n"
        logToFile(out); log += out
    }
    func clearShaderCaches() {
        guard sh("ps -axo command= | grep -c 'steamapps.common'").hasPrefix("0") else { log += "Shader caches: quit running games first.\n"; return }
        for (n, p) in shaderCacheDirs() { _ = sh("rm -rf '\(p)'"); log += "Cleared \(n)\n" }
    }
}
