import SwiftUI

extension Model {
    // Input precheck, game-independent: macOS -> Wine HID bus (SDL) -> XInput is the one chain every game reads from.
    // Ends by opening Wine's own Game Controllers panel: a pad listed there is visible to every game in the bottle.
    func inputCheck() {
        guard !selected.isEmpty else { return }
        var out = "── Input check ──\n"
        func check(_ ok: Bool, _ what: String, _ fix: String = "") { out += (ok ? "✓ " : "✗ ") + what + (ok || fix.isEmpty ? "" : "  →  \(fix)") + "\n" }
        let pads = sh("ioreg -r -c IOHIDDevice -l 2>/dev/null | grep -o '\"Product\" = \"[^\"]*\"' | grep -i 'DualSense\\|Wireless Controller\\|Xbox\\|Gamepad' | cut -d'\"' -f4 | sort -u | tr '\\n' ',' | sed 's/,$//'")
        check(!pads.isEmpty, pads.isEmpty ? "macOS sees a controller" : "macOS sees: \(pads)", "turn the pad on (PS/Xbox button) or pair it in Bluetooth settings")
        check(!sh("ioreg -r -c IOHIDDevice -l 2>/dev/null | grep -c -i '\"Product\" = \".*Keyboard'").hasPrefix("0"), "Keyboard present (Wine gets it through the Mac driver)")
        let bus = regSection("system.reg", "System\\CurrentControlSet\\Services\\winebus")
        check(bus.contains("\"DisableHidraw\"=dword:00000001"), "Wine HID bus uses SDL → pad appears as XInput in every game", "Repair")
        check(!bus.contains("\"Enable SDL\"=dword:00000000"), "Wine SDL backend enabled", "Repair")
        let reg = (try? String(contentsOfFile: "\(bottlesDir)/\(selected)/system.reg", encoding: .utf8)) ?? ""
        check(["054C", "045E", "057E", "28DE"].contains { reg.contains("Enum\\\\HID\\\\VID_\($0)") }, "Wine has seen a Sony/Microsoft/Nintendo/Steam pad in this bottle before", "turn the pad on and use the panel that opens now")
        if FileManager.default.fileExists(atPath: "\(bottlesDir)/\(selected)/drive_c/Program Files (x86)/Steam/steam.exe") {
            check(regSection("user.reg", "Software\\Wine\\AppDefaults\\steam.exe\\DllOverrides").contains("\"xinput1_4\"=\"\""), "Steam Input stays out of the way (Steam can't grab the pad, games can)", "Repair")
        }
        out += "Opening Wine's Game Controllers panel: press buttons on the pad; if it reacts there under XInput, every game in this bottle sees it.\n──\n"
        logToFile(out); log += out
        wine(selected, ["control", "joy.cpl"], block: false)
    }
}
