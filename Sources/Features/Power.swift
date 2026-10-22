import SwiftUI

extension Model {
    // §6.3 Power and thermal hints, logged at launch when they would change the experience.
    func powerHints() -> String {
        var out = ""
        if sh("pmset -g | grep -i lowpowermode | awk '{print $2}'") == "1" { out += "⚠ Low Power Mode is on: expect lower frame rates (System Settings › Battery).\n" }
        if let l = Int(sh("pmset -g therm 2>/dev/null | awk '/CPU_Speed_Limit/{print $3}'")), l < 100 { out += "⚠ Thermal pressure: CPU limited to \(l)% right now; let the Mac cool or lower settings.\n" }
        if onBattery() { out += "On battery: 60 fps cap and lighter rendering are active automatically.\n" }
        return out
    }
}
