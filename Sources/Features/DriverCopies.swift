import Foundation

// Driver DLLs belong in the bottle's drivers/ links, loaded per launch, never in system32/syswow64. Two things used to put them there:
// creating a bottle (wineboot ran with the driver slots active) and Wine's own automatic prefix update after an engine change (same).

// Wine updates a prefix by itself when <prefix>/.update-timestamp differs from wine.inf's mtime, inside whatever launch hit it. Doing it
// first, without driver slots, keeps that update from copying driver DLLs into the prefix.
func updatePrefixIfStale(_ prefix: String) {
    let stamp = (try? String(contentsOfFile: prefix + "/.update-timestamp", encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let inf = (wineBin as NSString).deletingLastPathComponent + "/../share/wine/wine.inf"
    guard FileManager.default.fileExists(atPath: prefix + "/drive_c"), stamp != "disable",
          let m = (try? FileManager.default.attributesOfItem(atPath: inf))?[.modificationDate] as? Date, stamp != String(Int(m.timeIntervalSince1970)) else { return }
    _ = shell("\(plainWine(prefix)) wineboot -u >/dev/null 2>&1")
}

extension Model {
    // Moves out of system32/syswow64 only the files whose SHA-256 equals a DLL from one of our backend folders (current, *.old, d3dmetal@*),
    // restores Wine's own copy from the engine, and returns what was moved. Moved files go to support/_to_delete/<date>/<bottle>/.
    nonisolated static func cleanDriverCopies(_ bottle: String) -> [String] {
        let fm = FileManager.default, win = "\(bottlesDir)/\(bottle)/drive_c/windows", lib = (wineBin as NSString).deletingLastPathComponent + "/../lib/wine"
        var ours: [String: String] = [:]   // sha256 → "backend/arch/file"
        for d in (try? fm.contentsOfDirectory(atPath: driversDir)) ?? [] where !d.hasPrefix(".") {
            for arch in ["x86_64-windows", "i386-windows"] {
                for f in (try? fm.contentsOfDirectory(atPath: "\(driversDir)/\(d)/wine/\(arch)")) ?? [] where f.lowercased().hasSuffix(".dll") {
                    if let h = sha256File("\(driversDir)/\(d)/wine/\(arch)/\(f)") { ours[h] = "\(d)/\(arch)/\(f)" }
                }
            }
        }
        let stamp = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd-HHmmss"; return f.string(from: Date()) }()
        var moved: [String] = []
        for (sys, arch) in [("system32", "x86_64-windows"), ("syswow64", "i386-windows")] {
            for f in (try? fm.contentsOfDirectory(atPath: "\(win)/\(sys)")) ?? [] where f.lowercased().hasSuffix(".dll") {
                let p = "\(win)/\(sys)/\(f)"
                guard let h = sha256File(p), let from = ours[h] else { continue }
                let dst = "\(support)/_to_delete/\(stamp)/\(bottle)/\(sys)"
                try? fm.createDirectory(atPath: dst, withIntermediateDirectories: true)
                guard (try? fm.moveItem(atPath: p, toPath: "\(dst)/\(f)")) != nil else { continue }
                let own = "\(lib)/\(arch)/\(f)"
                if fm.fileExists(atPath: own) { try? fm.copyItem(atPath: own, toPath: p) }
                moved.append("\(sys)/\(f) (copy of \(from)) → \(dst)/\(f)" + (fm.fileExists(atPath: p) ? "; Wine's own restored" : ""))
            }
        }
        return moved
    }
}
