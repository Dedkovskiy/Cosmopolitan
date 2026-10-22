import SwiftUI

extension Model {
    // §6.3 Power and thermal hints, logged at launch when they would change the experience.
    func powerHints() -> String {
        var out = ""
        if sh("pmset -g | grep -i lowpowermode | awk '{print $2}'") == "1" { out += "⚠ Low Power Mode is on: expect lower frame rates (System Settings › Battery).\n" }
        if let l = Int(sh("pmset -g therm 2>/dev/null | awk '/CPU_Speed_Limit/{print $3}'")), l < 100 { out += "⚠ Thermal pressure: CPU limited to \(l)% right now; let the Mac cool or lower settings.\n" }
        if onBattery() { out += "On battery: DXMT games are capped at 60 fps with lighter rendering; Direct3D 12 games " + (d3dmetalFrameCap() ? "are capped at 60 fps by D3DMetal.\n" : "are not capped (this D3DMetal has no frame limiter).\n") }
        return out
    }
}

// The battery cap applies on battery, or when macOS reports serious thermal pressure. Test build only: COSMO_TEST_ON_BATTERY=1 simulates battery.
func batteryCapWanted() -> Bool {
    if isTestBuild, ProcessInfo.processInfo.environment["COSMO_TEST_ON_BATTERY"] == "1" { return true }
    return onBattery() || ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue
}
// Whether the installed D3DMetal has its documented frame limiter (D3DM_MAX_FPS, in the 4.0 beta Read Me; absent from 3.0). Cached per framework file.
private let frameCapLock = NSLock()
nonisolated(unsafe) private var frameCapCache = (key: "", has: false)
func d3dmetalFrameCap() -> Bool {
    let bin = driversDir + "/d3dmetal/external/D3DMetal.framework/D3DMetal"
    let a = try? FileManager.default.attributesOfItem(atPath: bin)
    let key = "\((a?[.size] as? NSNumber)?.intValue ?? 0)|\((a?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)"
    frameCapLock.lock(); defer { frameCapLock.unlock() }
    if frameCapCache.key != key { frameCapCache = (key, a != nil && (Model.d3dmetalInfo(driversDir + "/d3dmetal")?.features.contains("D3DM_MAX_FPS") ?? false)) }
    return frameCapCache.has
}
