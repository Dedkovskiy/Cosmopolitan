import Foundation

// Thin Swift faces for the C++ module (Sources/Native). Everything here used to be a shell spawn (ioreg, pmset, ps, pgrep) or a
// byte-walk in Swift; now it is a direct call, which matters because the status refresh runs every 5 seconds.
func nativeControllers() -> [String] {
    var buf = [CChar](repeating: 0, count: 2048)
    let n = cosmo_controllers(&buf, buf.count)
    return n > 0 ? String(cString: buf).components(separatedBy: ", ").filter { !$0.isEmpty } : []
}
func onBattery() -> Bool { cosmo_on_battery() == 1 }
// Processes whose executable path or argv[0] contains `needle` (for Wine processes argv[0] is the Windows command line's exe); never the caller.
func procFind(_ needle: String) -> [Int32] {
    var pids = [Int32](repeating: 0, count: 256)
    let n = cosmo_proc_find(needle, &pids, Int32(pids.count))
    return Array(pids.prefix(Int(n)))
}
func isRunning(_ needle: String) -> Bool { !procFind(needle).isEmpty }
// PE facts + imports (normal and delay-load), lower-cased.
func peRead(_ path: String) -> (info: cosmo_pe_info, imports: [String]) {
    var buf = [CChar](repeating: 0, count: 16384)
    let info = cosmo_pe_read(path, &buf, buf.count)
    let s = String(cString: buf)
    return (info, s.isEmpty ? [] : s.components(separatedBy: ","))
}
