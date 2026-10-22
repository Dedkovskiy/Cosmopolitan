import SwiftUI

func driverList(_ env: [String: String], bottle: String) -> [String] {
    let l: [String]
    if let v = env["DRIVERS"], v != "auto" { l = v.split(separator: ",").map(String.init) }
    else { l = FileManager.default.fileExists(atPath: dx12Marker(bottle)) && d3dmetalOK ? autoDriverSetDX12 : autoDriverSet }   // no license → plain DXMT set
    return l.filter { ($0 != "d3dmetal" || d3dmetalOK) && driverUsable($0) }
}
// DXVK 3.x refuses every MoltenVK device ("required feature 'shaderCullDistance'": Metal has no cull distance), so it renders nothing here.
// Measured with tests/stress on DXVK-Sikarugir v3.1.1 (folders d9vk, dxvk3) + MoltenVK 1.4.1: no adapter for D3D9 or D3D11, the game aborts.
// The D3D9 v2.3 in dxvk and Wine's own D3D9 both render. ponytail: decided from the version file; re-run tests/stress when a new DXVK or
// MoltenVK arrives, and drop this if MoltenVK gains cull distance.
func driverUsable(_ d: String) -> Bool {
    let v = (try? String(contentsOfFile: "\(driversDir)/\(d)/version", encoding: .utf8)) ?? ""
    return v.range(of: #"DXVK[^ ]*-v([3-9]|[1-9][0-9])\."#, options: .regularExpression) == nil
}
func installedDrivers() -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: driversDir)) ?? []).filter { driverSlot[$0] != nil }.sorted()
}
func driverLabel(_ d: String) -> String {
    if d == "d3dmetal", let i = Model.d3dmetalInfo(driversDir + "/d3dmetal") { return "d3dmetal  (\(i.pretty), from \(i.source))" }
    let v = (try? String(contentsOfFile: "\(driversDir)/\(d)/version", encoding: .utf8))?.components(separatedBy: "\n").first ?? ""
    return (v.isEmpty ? d : "\(d)  (\(v))") + (driverUsable(d) ? "" : " — not used: can't run on Metal's Vulkan")
}
let skipExes = ["unins", "oalinst", "vcredist", "physx", "uninst", "crashhandler", "crashpad", "helper", "update", "setup", "redist", "dxsetup", "dotnet", "service", "minidump", "errorreporter", "crash", "report", "overlay", "sysinfo", "streaming"]
