import SwiftUI

extension Model {
    // §7.4 APFS snapshots: a copy-on-write clone of the bottle (seconds, ~0 bytes) before anything that writes into it beyond a plain launch.
    // Hidden from the bottle list (.auto-…), pruned after 30 days; Snapshots… lists them and rolls back in seconds.
    @discardableResult func snapshot(_ reason: String) -> String? {
        guard !selected.isEmpty else { return nil }
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"
        let bak = "\(bottlesDir)/.auto-\(selected)-\(f.string(from: Date()))"
        _ = sh("cp -cR '\(bottlesDir)/\(selected)' '\(bak)' && printf '%s' '\(reason)' > '\(bak)/.snapshot-reason'")
        log += "Snapshot (\(reason)): \((bak as NSString).lastPathComponent)\n"; return bak
    }
    func snapshots() -> [(path: String, when: String, reason: String)] {
        ((try? FileManager.default.contentsOfDirectory(atPath: bottlesDir)) ?? []).filter { $0.hasPrefix(".auto-\(selected)-") }.sorted(by: >).map { n in
            let p = "\(bottlesDir)/\(n)", stamp = String(n.dropFirst(".auto-\(selected)-".count))
            return (p, stamp, (try? String(contentsOfFile: p + "/.snapshot-reason", encoding: .utf8)) ?? "backup")
        }
    }
    func rollback(to snap: String) {
        busy = true
        Task { @MainActor in
            if steamRunning() { await stopSteam() }
            _ = sh("pkill -9 -f '\\.exe'; env WINEPREFIX='\(bottlesDir)/\(selected)' perl -e 'alarm 10; exec @ARGV' -- '\((wineBin as NSString).deletingLastPathComponent)/wineserver' -w 2>/dev/null")
            let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"
            let aside = "\(bottlesDir)/.auto-\(selected)-\(f.string(from: Date()))"
            _ = sh("mv '\(bottlesDir)/\(selected)' '\(aside)' && printf 'state before rollback' > '\(aside)/.snapshot-reason' && cp -cR '\(snap)' '\(bottlesDir)/\(selected)' && rm -f '\(bottlesDir)/\(selected)/.snapshot-reason'")
            log += "Rolled back \(selected) to \((snap as NSString).lastPathComponent); the previous state is kept as a snapshot too.\n"
            busy = false; refresh()
        }
    }
}
