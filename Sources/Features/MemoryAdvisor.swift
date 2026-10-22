import SwiftUI

extension Model {
    // §8.8 Memory-pressure advisor: while a game runs, warn (at most every 10 min) when macOS is low on memory or swapping hard.
    func memoryAdvisor() {
        guard Date().timeIntervalSince(lastMemWarn) > 600, !sh("ps -axo command= | grep -c 'steamapps.common\\|Program Files.*\\.exe'").hasPrefix("0") else { return }
        let level = Int(sh("sysctl -n kern.memorystatus_level")) ?? 100
        let swap = Double(sh("sysctl -n vm.swapusage | sed -E 's/.*used = ([0-9.]+)M.*/\\1/'")) ?? 0
        if level < 20 || swap > 4096 {
            lastMemWarn = Date()
            log += "⚠ Memory pressure while a game runs (free level \(level)%, swap \(Int(swap / 1024)) GB): close other apps or lower texture quality; stutter and long loads come from swapping.\n"
        }
    }
}
