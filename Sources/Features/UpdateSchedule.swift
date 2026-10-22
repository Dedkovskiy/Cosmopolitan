import SwiftUI

extension Model {
    // Weekly, in the background, no clicking: a newer release is installed as soon as it's found.
    func checkDriverUpdates() {
        guard !cliMode, !isTestBuild else { return }   // command-line runs and the test build never start the weekly downloads
        let stamp = support + "/.driver-check"
        if let m = (try? FileManager.default.attributesOfItem(atPath: stamp))?[.modificationDate] as? Date, Date().timeIntervalSince(m) < 7 * 86400 { return }
        updateDrivers()
    }
    func updateDrivers() {
        guard !busy else { return }
        busy = true; driverUpdates = "checking upstream…"
        Task.detached {
            let out = Model.performUpdate()
            await MainActor.run { logToFile(out); self.log += out; self.busy = false; self.driverUpdates = ""; self.updateStatus() }
        }
    }
}
