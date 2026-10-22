import SwiftUI

extension Model {
    // Anti-cheat detection. Signatures checked against real installs (Dawnwalker ships EOSSDK without EAC — EOS alone is NOT anti-cheat).
    func antiCheatSignatures(in folder: String) -> [String] {
        var found: [String] = []
        guard let en = FileManager.default.enumerator(atPath: folder) else { return found }
        for case let p as String in en {
            if en.level > 4 { en.skipDescendants(); continue }
            let n = (p as NSString).lastPathComponent.lowercased()
            if n == "easyanticheat" || n.hasPrefix("easyanticheat_") || n == "easyanticheat_eos_setup.exe" { found.append("Easy Anti-Cheat") }
            else if n == "battleye" || n.hasPrefix("beservice") || n.hasPrefix("beclient") { found.append("BattlEye") }
            else if n == "vgc.exe" || n == "vgk.sys" { found.append("Vanguard") }
            else if n.contains("ricochet") && n.hasSuffix(".sys") { found.append("RICOCHET") }
            else if n == "nprotect" || n.hasPrefix("gameguard") { found.append("nProtect GameGuard") }
            else if n.hasPrefix("xigncode") { found.append("XIGNCODE3") }
            else if n == "mhyprot2.sys" || n == "mhyprot3.sys" { found.append("mhyprot") }
        }
        return Array(Set(found)).sorted()
    }
    // Honest badge. Kernel-level systems cannot run under any Wine; EAC/BattlEye run only for games that ship the Proton/EOS variant, which
    // the Mac build of Wine does not provide either — so online play is out, single-player usually fine.
    static let kernelAC = ["Vanguard", "RICOCHET", "FACEIT", "nProtect GameGuard", "XIGNCODE3", "mhyprot", "Javelin", "Denuvo Anti-Cheat", "EQU8", "Wellbia"]
    func antiCheatVerdict(_ names: [String]) -> (Color, String)? {
        guard !names.isEmpty else { return nil }
        if let k = names.first(where: { n in Model.kernelAC.contains { n.localizedCaseInsensitiveContains($0) } }) { return (.red, "Kernel anti-cheat (\(k)) — will not run; use cloud gaming or a native Mac version") }
        return (.yellow, "Online won't work (\(names.joined(separator: ", "))); offline/single-player usually fine")
    }
}
