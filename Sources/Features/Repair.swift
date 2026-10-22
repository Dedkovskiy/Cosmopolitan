import SwiftUI

extension Model {
    // Safe, idempotent fixes for the ✗ lines above.
    func repair() {
        guard !selected.isEmpty else { return }
        busy = true
        let r = "\(bottlesDir)/\(selected)"
        snapshot("before Repair")
        log += "Repair: stopping all Wine processes…\n"
        // wineserver -k/-w act on $WINEPREFIX's server; without it they'd silently target ~/.wine.
        let ws = "env WINEPREFIX='\(r)' '\((wineBin as NSString).deletingLastPathComponent)/wineserver'"
        _ = sh("\(ws) -k; sleep 1; pkill -9 -f '\\.exe' ; pkill -9 -f wineserver; true")
        var cmds = [["reg", "add", "HKLM\\System\\CurrentControlSet\\Services\\winebus", "/v", "DisableHidraw", "/t", "REG_DWORD", "/d", "1", "/f"],
                    ["reg", "add", "HKCU\\Control Panel\\Desktop", "/v", "LogPixels", "/t", "REG_DWORD", "/d", "96", "/f"],
                    ["reg", "add", "HKCU\\Software\\Wine\\Fonts", "/v", "LogPixels", "/t", "REG_DWORD", "/d", "96", "/f"]]
        if FileManager.default.fileExists(atPath: r + "/drive_c/Program Files (x86)/Steam/steam.exe") {
            for dll in ["xinput1_1", "xinput1_2", "xinput1_3", "xinput1_4", "xinput9_1_0", "xinputuap", "dinput", "dinput8"] {
                cmds.append(["reg", "add", "HKCU\\Software\\Wine\\AppDefaults\\steam.exe\\DllOverrides", "/v", dll, "/t", "REG_SZ", "/d", "", "/f"]) }
            for dll in ["d3d11", "dxgi", "d3d10core"] {
                cmds.append(["reg", "add", "HKCU\\Software\\Wine\\AppDefaults\\steamwebhelper.exe\\DllOverrides", "/v", dll, "/t", "REG_SZ", "/d", "builtin", "/f"]) }
        }
        let env = launchEnv(selected).map { "\($0.key)='\($0.value)'" }.joined(separator: " ")
        for c in cmds { _ = sh("env \(env) '\(wineBin)' " + c.map { "'\($0)'" }.joined(separator: " ") + " >/dev/null 2>&1") }
        _ = sh("\(ws) -w")   // wait for the server to exit = registry flushed to disk
        busy = false
        log += "Repair done. Run Troubleshoot again to confirm, then relaunch your program.\n"
        scan()
    }
}
