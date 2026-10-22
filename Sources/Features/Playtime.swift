import SwiftUI

// §5.2 Playtime: seconds accumulated per program between launch and the process disappearing. Stored in options/.playtime-<exe>.
extension Model {
    func playtimePath(_ exe: String) -> String { "\(bottlesDir)/\(selected)/options/.playtime-\((exe as NSString).lastPathComponent)" }
    func playtime(_ exe: String) -> String? {
        guard let s = Int(((try? String(contentsOfFile: playtimePath(exe), encoding: .utf8)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)), s > 60 else { return nil }
        return s >= 3600 ? "\(s / 3600) h \((s % 3600) / 60) min" : "\(s / 60) min"
    }
    func trackPlaytime(_ exe: String) {
        let started = Date(), path = playtimePath(exe)
        whenExits(exe) {
            let add = Int(Date().timeIntervalSince(started)) - 10
            guard add > 30 else { return }
            let old = Int(((try? String(contentsOfFile: path, encoding: .utf8)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try? String(old + add).write(toFile: path, atomically: true, encoding: .utf8)
            self.artVersion += 1   // refresh tooltips
        }
    }
}
