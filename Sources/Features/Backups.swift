import SwiftUI

extension Model {
    // ── P2 ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
    // §8.5 Time Machine + Spotlight: game binaries and the Windows folder are excluded (re-downloadable), saves under users/ stay backed up.
    func excludeFromBackups(_ bottle: String) {
        let root = "\(bottlesDir)/\(bottle)", mark = root + "/.backup-exclusions-set"
        guard !FileManager.default.fileExists(atPath: mark), FileManager.default.fileExists(atPath: root + "/drive_c") else { return }
        for d in ["drive_c/Program Files", "drive_c/Program Files (x86)", "drive_c/windows", "drive_c/ProgramData"] where FileManager.default.fileExists(atPath: "\(root)/\(d)") { _ = sh("tmutil addexclusion '\(root)/\(d)' 2>/dev/null") }
        FileManager.default.createFile(atPath: root + "/.metadata_never_index", contents: nil)   // Spotlight: never index a bottle
        FileManager.default.createFile(atPath: mark, contents: nil)
        log += "\(bottle): program folders excluded from Time Machine, bottle hidden from Spotlight; saves under users/ stay backed up.\n"
    }
}
