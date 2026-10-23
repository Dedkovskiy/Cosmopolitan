import SwiftUI

extension Model {
    // ── P2 ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
    // §8.5 Time Machine + Spotlight: game binaries and the Windows folder are excluded (re-downloadable), saves under users/ stay backed up.
    func excludeFromBackups(_ bottle: String) {
        let root = "\(bottlesDir)/\(bottle)", mark = root + "/.backup-exclusions-set"
        guard !FileManager.default.fileExists(atPath: mark), FileManager.default.fileExists(atPath: root + "/drive_c") else { return }
        // The same sticky exclusion as `tmutil addexclusion`, set on the folder itself: no tmutil process and no wait on backupd, which made
        // bottle creation hang for half an hour on the main thread when backupd was slow.
        for d in ["drive_c/Program Files", "drive_c/Program Files (x86)", "drive_c/windows", "drive_c/ProgramData"] where FileManager.default.fileExists(atPath: "\(root)/\(d)") {
            var u = URL(fileURLWithPath: "\(root)/\(d)"), v = URLResourceValues(); v.isExcludedFromBackup = true; try? u.setResourceValues(v)
        }
        FileManager.default.createFile(atPath: root + "/.metadata_never_index", contents: nil)   // Spotlight: never index a bottle
        FileManager.default.createFile(atPath: mark, contents: nil)
        log += "\(bottle): program folders excluded from Time Machine, bottle hidden from Spotlight; saves under users/ stay backed up.\n"
    }
}
