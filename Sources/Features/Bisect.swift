import SwiftUI

extension Model {
    // §4.5 Bisect: try the next driver set for one program (saved in its Options so the result sticks), then launch it.
    static let bisectSets: [(String, [String])] = [("dxmt", ["dxmt", "d9vk", "cnc_ddraw"]), ("d3dmetal", ["d3dmetal", "d9vk", "cnc_ddraw"]), ("dxvk", ["dxvk", "cnc_ddraw"]), ("wined3d (Wine's own)", ["cnc_ddraw"])]
    func bisect(_ exe: String) {
        let sets = Model.bisectSets.filter { $0.1.allSatisfy { FileManager.default.fileExists(atPath: "\(driversDir)/\($0)/wine") } && !($0.0 == "d3dmetal" && !d3dmetalOK) }
        let cur = Set(options(exe)["DRIVERS"]?.split(separator: ",").map(String.init) ?? driverList(launchEnvRaw(), bottle: selected))
        let idx = sets.firstIndex { Set($0.1) == cur } ?? -1
        let next = sets[(idx + 1) % sets.count]
        var t = (try? String(contentsOfFile: optionsPath(exe), encoding: .utf8)) ?? Model.optionsTemplate
        t = t.components(separatedBy: "\n").filter { !$0.hasPrefix("DRIVERS=") }.joined(separator: "\n") + "\nDRIVERS=\(next.1.joined(separator: ","))\n"
        snapshot("before driver switch: \(appName(exe)) → \(next.0)"); backupSaves(exe, "before driver switch")
        saveOptions(exe, t); log += "Bisect: \(appName(exe)) now uses \(next.0) (saved in its Options; remove the DRIVERS line to go back to automatic). Launching…\n"
        launch(exe)
    }
}
