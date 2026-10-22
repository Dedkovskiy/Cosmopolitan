import SwiftUI

extension Model {
    // §7.3 Game updates: remember each exe's size+mtime; a change means the game updated → re-check and say so (a snapshot taken by the next risky step protects the rest).
    func noteExeChange(_ exe: String) {
        let f = "\(bottlesDir)/\(selected)/options/.exe-\((exe as NSString).lastPathComponent)"
        guard let a = try? FileManager.default.attributesOfItem(atPath: exe) else { return }
        let sig = "\(a[.size] ?? 0)|\((a[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)"
        let old = (try? String(contentsOfFile: f, encoding: .utf8)) ?? ""
        try? FileManager.default.createDirectory(atPath: (f as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try? sig.write(toFile: f, atomically: true, encoding: .utf8)
        if !old.isEmpty, old != sig { log += "\(appName(exe)) was updated — launch check and AVX scan run again. If it broke, Snapshots… has the state before the last change.\n"; try? FileManager.default.removeItem(atPath: avxCache(exe)) }
    }
}
