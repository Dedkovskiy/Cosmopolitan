import SwiftUI

extension Model {
    // §8.12 Bug report: everything a maintainer needs, with the username and home folder stripped, on the clipboard.
    func copyBugReport() {
        let home = NSHomeDirectory(), user = NSUserName()
        var r = "## Cosmopolitan bug report\n"
        r += "- App: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "?") (\(Bundle.main.infoDictionary?["CFBundleVersion"] ?? "?"))\n"
        r += "- Mac: \(sh("sysctl -n machdep.cpu.brand_string")), \(ProcessInfo.processInfo.physicalMemory / 1_073_741_824) GB, macOS \(ProcessInfo.processInfo.operatingSystemVersionString)\n"
        r += "- Engine: \(sh("'\(wineBin)' --version 2>/dev/null")); drivers: \(driverList(launchEnvRaw(), bottle: selected).joined(separator: "+")); D3DMetal accepted: \(d3dmetalOK)\n"
        r += "- Bottle: \(selected); programs: \(programs.map { appName($0) + " [" + (readiness[$0]?.note.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") + "]" }.joined(separator: "; "))\n"
        r += "- Status: \(driverStatus.1) / \(padStatus.1)\n\n### Log (last 200 lines)\n```\n"
        r += log.components(separatedBy: "\n").suffix(200).joined(separator: "\n") + "\n```\n"
        r = r.replacingOccurrences(of: home, with: "~").replacingOccurrences(of: user, with: "<user>")
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(r, forType: .string)
        log += "Bug report copied to the clipboard (paths and username removed). Paste it into a GitHub issue.\n"
    }
}
