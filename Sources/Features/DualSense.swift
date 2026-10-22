import SwiftUI

// DualSense "native" mode per game. Two ways a game can see the pad, and Wine's HID bus can only do one at a time per bottle:
//  • xinput (default): winebus hides raw HID (DisableHidraw=1) and SDL presents an Xbox-style pad → every game gets sticks, buttons, rumble.
//  • native: winebus passes the real DualSense through macOS HID (DisableHidraw=0): the game sees VID 054C / PID 0CE6 and can send the
//    pad's own output reports → adaptive triggers, voice-coil haptics, lightbar, touchpad — for games that support DualSense on PC.
//    Games without that support then see only a DirectInput pad (no XInput), which is why this is a per-game switch (Options DUALSENSE=native).
// The bus driver reads the setting when the prefix starts, so changing it means restarting Steam (the app does that) before the launch.
extension Model {
    // Live value via reg query (system.reg on disk lags behind while a wineserver is running).
    func hidrawDisabled() -> Bool {
        let env = launchEnv(selected).map { "\($0.key)='\($0.value)'" }.joined(separator: " ")
        let q = sh("env \(env) WINEDEBUG=-all '\(wineBin)' reg query 'HKLM\\System\\CurrentControlSet\\Services\\winebus' /v DisableHidraw 2>/dev/null | tr -d '\\r'")
        return q.contains("0x1") || (q.isEmpty && regSection("system.reg", "System\\CurrentControlSet\\Services\\winebus").contains("\"DisableHidraw\"=dword:00000001"))
    }
    // Returns true when the bus mode had to change (caller restarts Steam so the new mode is live).
    @discardableResult func ensureControllerMode(for exe: String) -> Bool {
        let native = options(exe)["DUALSENSE"]?.lowercased() == "native"
        guard native == hidrawDisabled() else { return false }   // already in the right mode (native ⇔ hidraw enabled)
        let env = launchEnv(selected).map { "\($0.key)='\($0.value)'" }.joined(separator: " ")
        _ = sh("env \(env) '\(wineBin)' reg add 'HKLM\\System\\CurrentControlSet\\Services\\winebus' /v DisableHidraw /t REG_DWORD /d \(native ? 0 : 1) /f >/dev/null 2>&1")
        // Wine 11+ also takes a per-device choice (WineBus\Devices\<VID>, value Hidraw); the 10.0 engine ignores it. Written as well, so on a
        // newer engine only Sony pads (VID 054C) switch and other controllers stay on SDL/XInput.
        _ = sh("env \(env) '\(wineBin)' reg add 'HKLM\\System\\CurrentControlSet\\Services\\winebus\\Devices\\054c' /v Hidraw /t REG_DWORD /d \(native ? 1 : 0) /f >/dev/null 2>&1")
        log += native ? "DualSense native mode for \(appName(exe)): the game gets the real pad (triggers, haptics, touchpad); XInput games need the next launch to switch back.\n"
                      : "Controller back to XInput mode (SDL) for \(appName(exe)).\n"
        return true
    }
}
