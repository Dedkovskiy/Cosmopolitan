import SwiftUI

extension Model {
    // §7.9 Contribute back (opt-in, by click): a pre-filled Highball issue with chip, macOS, engine and driver set — no personal data, no library.
    func reportToHighball(_ exe: String) {
        let g = steamGames[exe], chip = sh("sysctl -n machdep.cpu.brand_string"), ram = ProcessInfo.processInfo.physicalMemory / 1_073_741_824
        let title = "Report: \(appName(exe))\(g.map { " (\($0.id))" } ?? "") on \(chip)"
        let body = """
        **Game:** \(appName(exe))\(g.map { " — Steam app id \($0.id)" } ?? "")
        **Mac:** \(chip), \(ram) GB, macOS \(ProcessInfo.processInfo.operatingSystemVersionString)
        **Launcher:** Cosmopolitan \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "?"), engine \(sh("'\(wineBin)' --version 2>/dev/null"))
        **Backend:** \(driverList(launchEnvRaw(), bottle: selected).joined(separator: " + "))\(readiness[exe]?.drivers.map { " (this game: \($0.joined(separator: " + ")))" } ?? "")
        **Result:** <works / works with issues / does not start — please fill in>
        **Notes:** <fps, settings, crashes>
        """
        var c = URLComponents(string: "https://github.com/gauthierpiarrette/highball-db/issues/new")!
        c.queryItems = [.init(name: "title", value: title), .init(name: "body", value: body), .init(name: "labels", value: "report")]
        if let u = c.url { NSWorkspace.shared.open(u); log += "Opened a pre-filled Highball report for \(appName(exe)) in the browser; nothing is sent until you submit it.\n" }
    }
}
