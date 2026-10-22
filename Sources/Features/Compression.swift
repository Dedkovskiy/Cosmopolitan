import SwiftUI

extension Model {
    // §8.3 Transparent APFS compression of one game's folder: files stay readable as-is; the OS decompresses on read. Refused while the game runs.
    func compressGame(_ exe: String) {
        let root: String = { if let r = exe.range(of: "/steamapps/common/") { let rest = exe[r.upperBound...]; if let s = rest.firstIndex(of: "/") { return String(exe[..<s]) } }; return (exe as NSString).deletingLastPathComponent }()
        guard !isRunning((exe as NSString).lastPathComponent) else { log += "Compress: \(appName(exe)) is running; quit it first.\n"; return }
        busy = true; log += "Compressing \(root) with APFS transparent compression (ditto --hfsCompression)… this reads and rewrites every file once.\n"
        Task.detached {
            let before = shell("du -sk '\(root)' | cut -f1")
            let r = shell("rm -rf '\(root).compressing' && ditto --hfsCompression '\(root)' '\(root).compressing' 2>&1 | tail -1 && rm -rf '\(root)' && mv '\(root).compressing' '\(root)'")
            let after = shell("du -sk '\(root)' | cut -f1")
            await MainActor.run { self.busy = false; self.log += r.isEmpty ? "Compressed: \((Int(before) ?? 0) / 1024) MB → \((Int(after) ?? 0) / 1024) MB on disk.\n" : "Compress: \(r)\n"; self.scan() }
        }
    }
}
