import SwiftUI

// Environment a bottle's programs are launched with (also used by Dock shortcuts).
func launchEnv(_ bottle: String, drivers: [String]? = nil) -> [String: String] {   // drivers: per-launch override of the bottle's DRIVERS
    // VK_DRIVER_FILES: registers MoltenVK with the Vulkan loader; without it DXVK has no GPU (res=-9).
    var e = ["WINEPREFIX": "\(bottlesDir)/\(bottle)", "WINEDEBUG": "-all",
             "VK_DRIVER_FILES": engineDir + "/MoltenVK_icd.json",
             "MVK_CONFIG_RESUME_LOST_DEVICE": "1", "MVK_CONFIG_FAST_MATH_ENABLED": "1",
             "MVK_CONFIG_LOG_LEVEL": "1",   // errors only: MoltenVK otherwise prints its 150-line extension list for every VkInstance (Qt apps make six at startup)
             // Video/audio decoding (Media Foundation, DirectShow) goes through GStreamer; the framework comes from the Sikarugir template.
             "GST_PLUGIN_PATH": support + "/engines/gstreamer/GStreamer.framework/Versions/1.0/lib/gstreamer-1.0",
             "GST_PLUGIN_SYSTEM_PATH_1_0": support + "/engines/gstreamer/GStreamer.framework/Versions/1.0/lib/gstreamer-1.0",
             // DualSense through SDL's own hidapi driver: rumble reaches the pad's motors via XInput vibration; player LED off (no distraction).
             "SDL_JOYSTICK_HIDAPI": "1", "SDL_JOYSTICK_HIDAPI_PS5": "1", "SDL_JOYSTICK_HIDAPI_PS5_PLAYER_LED": "0",
             // Wine hands DOS programs to `dosbox` from PATH; apps launched from Finder don't see Homebrew's bin otherwise.
             "PATH": "/opt/homebrew/bin:/usr/local/bin:" + (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin")]
    let t = (try? String(contentsOfFile: "\(bottlesDir)/\(bottle)/cosmopolitan.env", encoding: .utf8)) ?? ""
    for l in t.components(separatedBy: "\n") {
        let kv = l.split(separator: "=", maxSplits: 1).map(String.init)
        if kv.count == 2 { e[kv[0]] = kv[1] }
    }
    // msync: thread waits on Mach semaphores instead of server round-trips — less CPU, no effect on rendering. (The DLSS→MetalFX bridge stays OFF:
    // it was the real cause of the Dawnwalker lag; FSR in the game menu is the right upscaler under D3DMetal.)
    if e["WINEMSYNC"] == nil { e["WINEMSYNC"] = "1" }
    // On battery, or when the Mac is thermally throttled (§7.8): 60 fps cap in D3DMetal and DXMT, DXMT renders at 2/3 and MetalFX-upscales. Off again when plugged in and cool.
    if e["D3DM_MAX_FPS"] == nil, onBattery() || (Int(shell("pmset -g therm 2>/dev/null | awk '/CPU_Speed_Limit/{print $3}'")) ?? 100) < 100 {
        e["D3DM_MAX_FPS"] = "60"; e["DXMT_CONFIG"] = "d3d11.preferredMaxFrameRate=60;d3d11.metalSpatialUpscaleFactor=1.5"
    }
    // Upstream DXVK can't run on Metal; the Sikarugir DXVK builds here can.
    // Only the engine's per-slot variables, never plain WINEDLLPATH: tried 2026-10-22, it made DXMT's dxgi/d3d11 the builtin for every
    // process including steamwebhelper (which must stay on Wine's own D3D) → "Steamwebhelper is not responding".
    for d in drivers ?? driverList(e, bottle: bottle) {
        guard let s = driverSlot[d], driverUsable(d) else { continue }   // a driver that can't create a device here would only crash the game
        e["WINEDLLPATH_" + s] = "\(driversDir)/\(d)/wine"
        // libd3dshared dlopen()s this value as-is; the dylibs are reached through the symlinked x86_64-unix path, so @rpath can't find the framework on its own.
        if d == "d3dmetal" { e["D3DMETAL_FRAMEWORK_PATH"] = "\(driversDir)/d3dmetal/external/D3DMetal.framework/D3DMetal" }
    }
    return e
}
