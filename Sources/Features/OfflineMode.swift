import SwiftUI

// §3.3 Official offline launchers: some games ship a separate executable or folder for playing without their online service / anti-cheat
// (e.g. *_offline.exe, Offline/...). When one exists it is offered as "Launch offline version", never a modified file of ours.
extension Model {
    func offlineExe(_ exe: String) -> String? {
        let root: String = { if let r = exe.range(of: "/steamapps/common/") { let rest = exe[r.upperBound...]; if let s = rest.firstIndex(of: "/") { return String(exe[..<s]) } }; return (exe as NSString).deletingLastPathComponent }()
        guard let en = FileManager.default.enumerator(atPath: root) else { return nil }
        for case let p as String in en {
            if en.level > 4 { en.skipDescendants(); continue }
            let n = (p as NSString).lastPathComponent.lowercased()
            if n.hasSuffix(".exe"), n.contains("offline"), !skipExes.contains(where: { n.contains($0) }), "\(root)/\(p)" != exe { return "\(root)/\(p)" }
        }
        return nil
    }
}
