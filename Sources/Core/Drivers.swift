import SwiftUI

func driverList(_ env: [String: String], bottle: String) -> [String] {
    let l: [String]
    if let v = env["DRIVERS"], v != "auto" { l = v.split(separator: ",").map(String.init) }
    else { l = FileManager.default.fileExists(atPath: dx12Marker(bottle)) && d3dmetalOK ? autoDriverSetDX12 : autoDriverSet }   // no license → plain DXMT set
    return l.filter { $0 != "d3dmetal" || d3dmetalOK }
}
func installedDrivers() -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: driversDir)) ?? []).filter { driverSlot[$0] != nil }.sorted()
}
func driverLabel(_ d: String) -> String {
    let v = (try? String(contentsOfFile: "\(driversDir)/\(d)/version", encoding: .utf8))?.components(separatedBy: "\n").first ?? ""
    return v.isEmpty ? d : "\(d)  (\(v))"
}
let skipExes = ["unins", "uninst", "crashhandler", "crashpad", "helper", "update", "setup", "redist", "dxsetup", "dotnet", "service", "minidump", "errorreporter", "crash", "report", "overlay", "sysinfo", "streaming"]
