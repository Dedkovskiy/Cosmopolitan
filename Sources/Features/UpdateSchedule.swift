import SwiftUI

extension Model {
    // Weekly, in the background: checks upstream and reports; never installs anything by itself.
    func checkDriverUpdates() {
        guard !cliMode, !isTestBuild else { return }   // command-line runs and the test build never start the weekly downloads
        let stamp = support + "/.driver-check"
        if let m = (try? FileManager.default.attributesOfItem(atPath: stamp))?[.modificationDate] as? Date, Date().timeIntervalSince(m) < 7 * 86400 { return }
        Task.detached { let out = Model.performUpdate(install: false); await MainActor.run { logToFile(out); self.log += out } }   // check only
    }
    // The Update… button: shows what would change and replaces nothing without a yes.
    func updateDrivers() {
        guard !busy else { return }
        busy = true; driverUpdates = "checking upstream…"
        Task.detached {
            let pending = Model.latestDriverTags().filter { !Model.isCurrent($0) }
            await MainActor.run {
                self.busy = false; self.driverUpdates = ""
                guard !pending.isEmpty else { self.log += "Drivers: DXMT and DXVK are current.\n"; return }
                let a = NSAlert(); a.messageText = "Replace these drivers with upstream releases?"
                a.informativeText = pending.map { "\($0.name): \($0.installed) → \($0.tag)" }.joined(separator: "\n")
                    + "\n\nThe installed builds are the tested Sikarugir ones. Each is kept as <name>.old, so you can switch back."
                a.addButton(withTitle: "Replace"); a.addButton(withTitle: "Cancel")
                guard a.runModal() == .alertFirstButtonReturn else { self.log += "Drivers: nothing replaced.\n"; return }
                self.busy = true; self.driverUpdates = "installing…"
                Task.detached { let out = Model.performUpdate(install: true); await MainActor.run { logToFile(out); self.log += out; self.busy = false; self.driverUpdates = ""; self.updateStatus() } }
            }
        }
    }
    // A driver folder that went missing comes back from the pinned template (verified by tree hash), not from a newer upstream release.
    func restoreMissingDrivers() {
        guard let app = Pins.verifiedTemplate() else { log += "A driver folder is missing and the pinned Sikarugir template isn't on disk; run setup again.\n"; return }
        for d in ["dxmt", "dxvk", "dxvk3", "d9vk", "cnc_ddraw"] where !FileManager.default.fileExists(atPath: "\(driversDir)/\(d)/wine") {
            _ = shell("cp -cR '\(app)/Contents/SharedSupport/renderer/\(d)' '\(driversDir)/\(d)'")
            log += FileManager.default.fileExists(atPath: "\(driversDir)/\(d)/wine") ? "Restored the missing driver \(d) from \(Pins.sikarugirTemplate).\n" : "✗ Could not restore \(d).\n"
        }
        updateStatus()
    }
}
