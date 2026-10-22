import SwiftUI
import UniformTypeIdentifiers
import PDFKit
import Sparkle
import FoundationModels

// §8.11 Auto-updates: Sparkle with EdDSA-signed appcast (no Apple Developer account needed). Feed URL and public key come from Info.plist (build.sh).
let updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

// Shows Apple's license file exactly as shipped in the user's download: PDF through PDFKit, RTF through a read-only text view.
struct LicenseView: NSViewRepresentable {
    let path: String
    func makeNSView(context: Context) -> NSView {
        if path.lowercased().hasSuffix(".pdf") { let v = PDFView(); v.autoScales = true; v.document = PDFDocument(url: URL(fileURLWithPath: path)); return v }
        let sv = NSScrollView(), tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 560, height: 0))
        tv.isEditable = false; tv.isVerticallyResizable = true; tv.autoresizingMask = [.width]; tv.textContainer?.widthTracksTextView = true
        if let s = try? NSAttributedString(url: URL(fileURLWithPath: path), options: [:], documentAttributes: nil) { tv.textStorage?.setAttributedString(s) }
        sv.documentView = tv; sv.hasVerticalScroller = true
        return sv
    }
    func updateNSView(_ v: NSView, context: Context) {}
}

// Engine: open-source Wine 10.0 (Sikarugir build) kept in our own folder. No CodeWeavers code.
// ponytail: Wine 11.x Staging renders Steam's UI black on macOS 27 (client surface detached); stay on 10.0 until that's fixed upstream.
let support = NSHomeDirectory() + "/Library/Application Support/Cosmopolitan"
let wineBin = support + "/engines/WS12WineSikarugir10.0_8/wswine.bundle/bin/wine"
let bottlesDir = support + "/bottles"
let engineOK = FileManager.default.fileExists(atPath: wineBin)
// Drivers live in engines/renderer/<name>/wine; the engine loads a folder's DLLs as builtins when WINEDLLPATH_<slot> points at it.
// Per-bottle choice is DRIVERS=dxmt,cnc_ddraw in cosmopolitan.env (absent = dxmt). Drop a new renderer folder in and add its slot here.
let driversDir = support + "/engines/renderer"
let driverSlot = ["dxmt": "DXMT", "dxvk": "DXVK", "dxvk3": "DXVK", "d9vk": "D9VK", "d3dmetal": "D3DMETAL", "cnc_ddraw": "CNCD"]
// Auto = the set whose DLLs don't overlap: dxmt (d3d10core/d3d11/dxgi), d9vk (d3d8/d3d9), cnc_ddraw (ddraw). D3D12 needs d3dmetal, which
// replaces dxmt's d3d11/dxgi too, so it stays a manual choice. ponytail: no per-exe import sniffing; games LoadLibrary D3D at runtime anyway.
let autoDriverSet = ["dxmt", "d9vk", "cnc_ddraw"]
// A bottle holding a Direct3D 12 program gets d3dmetal in place of dxmt (both provide d3d11/dxgi; D3DMetal does 11 and 12), so that
// games started from inside Steam get DirectX 12 too. verifyAll() keeps the marker file current and restarts Steam when it flips.
let autoDriverSetDX12 = ["d3dmetal", "d9vk", "cnc_ddraw"]
func dx12Marker(_ bottle: String) -> String { "\(bottlesDir)/\(bottle)/.needs-dx12" }
// D3DMetal is Apple's proprietary Game Porting Toolkit: usable only after the user has read Apple's license and accepted it explicitly.
// Acceptance = date + SHA-256 of the License file; a different license (new GPTK) asks again. Not accepted ⇒ d3dmetal is never loaded.
let d3dmetalAcceptFile = support + "/d3dmetal-license.json"
// Terms of Use: shown on first run and again whenever TERMS.txt changes (acceptance = date + SHA-256 of the shipped file).
let termsPath = Bundle.main.path(forResource: "TERMS", ofType: "txt") ?? "", termsAcceptFile = support + "/terms-accepted.json"
func termsHash() -> String { shell("shasum -a 256 '\(termsPath)' 2>/dev/null | cut -d' ' -f1") }
func termsAccepted() -> Bool {
    guard let j = try? String(contentsOfFile: termsAcceptFile, encoding: .utf8), let h = j.components(separatedBy: "\"sha256\":\"").dropFirst().first?.components(separatedBy: "\"").first else { return false }
    return !h.isEmpty && h == termsHash()
}
func acceptTerms() { let f = ISO8601DateFormatter(); try? FileManager.default.createDirectory(atPath: support, withIntermediateDirectories: true); try? "{\"accepted\":\"\(f.string(from: Date()))\",\"sha256\":\"\(termsHash())\"}".write(toFile: termsAcceptFile, atomically: true, encoding: .utf8) }
// Apple's license as found in the user's own download: License.pdf (GPTK disk image) or License.rtf (the redist folder). Never a copy of ours.
func d3dmetalLicenseFile() -> String? { ["License.pdf", "License.rtf"].map { driversDir + "/d3dmetal/" + $0 }.first { FileManager.default.fileExists(atPath: $0) } }
func d3dmetalInstalled() -> Bool {
    let d = driversDir + "/d3dmetal"
    return FileManager.default.fileExists(atPath: d + "/wine/x86_64-windows/d3d12.dll") && FileManager.default.fileExists(atPath: d + "/external/D3DMetal.framework/D3DMetal") && d3dmetalLicenseFile() != nil
}
func licenseHash() -> String { d3dmetalLicenseFile().map { shell("shasum -a 256 '\($0)' 2>/dev/null | cut -d' ' -f1") } ?? "" }
func checkD3DMetalAccepted() -> Bool {
    guard let j = try? String(contentsOfFile: d3dmetalAcceptFile, encoding: .utf8), let h = j.components(separatedBy: "\"sha256\":\"").dropFirst().first?.components(separatedBy: "\"").first else { return false }
    return !h.isEmpty && h == licenseHash()
}
var d3dmetalOK = checkD3DMetalAccepted()
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

// Environment a bottle's programs are launched with (also used by Dock shortcuts).
func launchEnv(_ bottle: String, drivers: [String]? = nil) -> [String: String] {   // drivers: per-launch override of the bottle's DRIVERS
    // VK_DRIVER_FILES: registers MoltenVK with the Vulkan loader; without it DXVK has no GPU (res=-9).
    var e = ["WINEPREFIX": "\(bottlesDir)/\(bottle)", "WINEDEBUG": "-all",
             "VK_DRIVER_FILES": support + "/engines/WS12WineSikarugir10.0_8/wswine.bundle/MoltenVK_icd.json",
             "MVK_CONFIG_RESUME_LOST_DEVICE": "1", "MVK_CONFIG_FAST_MATH_ENABLED": "1",
             // Video/audio decoding (Media Foundation, DirectShow) goes through GStreamer; the framework comes from the Sikarugir template.
             "GST_PLUGIN_PATH": support + "/engines/gstreamer/GStreamer.framework/Versions/1.0/lib/gstreamer-1.0",
             "GST_PLUGIN_SYSTEM_PATH_1_0": support + "/engines/gstreamer/GStreamer.framework/Versions/1.0/lib/gstreamer-1.0",
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
    if e["D3DM_MAX_FPS"] == nil, shell("pmset -g batt").contains("Battery Power") || (Int(shell("pmset -g therm 2>/dev/null | awk '/CPU_Speed_Limit/{print $3}'")) ?? 100) < 100 {
        e["D3DM_MAX_FPS"] = "60"; e["DXMT_CONFIG"] = "d3d11.preferredMaxFrameRate=60;d3d11.metalSpatialUpscaleFactor=1.5"
    }
    // Upstream DXVK can't run on Metal; the Sikarugir DXVK builds here can.
    for d in drivers ?? driverList(e, bottle: bottle) {
        guard let s = driverSlot[d] else { continue }
        e["WINEDLLPATH_" + s] = "\(driversDir)/\(d)/wine"
        // libd3dshared dlopen()s this value as-is; the dylibs are reached through the symlinked x86_64-unix path, so @rpath can't find the framework on its own.
        if d == "d3dmetal" { e["D3DMETAL_FRAMEWORK_PATH"] = "\(driversDir)/d3dmetal/external/D3DMetal.framework/D3DMetal" }
    }
    return e
}

// Everything shown in the log pane is also appended to ~/Library/Logs/Cosmopolitan.log (truncated on each app start).
let logPath = NSHomeDirectory() + "/Library/Logs/Cosmopolitan.log"
let logFile: FileHandle? = { FileManager.default.createFile(atPath: logPath, contents: nil); return FileHandle(forWritingAtPath: logPath) }()
func logToFile(_ s: String) { logFile?.write(Data(s.utf8)) }
// Run a shell command and return its output; usable from any thread.
func shell(_ cmd: String) -> String {
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/sh"); p.arguments = ["-c", cmd]
    let o = Pipe(); p.standardOutput = o; p.standardError = o
    try? p.run(); let d = o.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
    return String(decoding: d, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}

// DLL names an .exe imports (PE import directory), lowercased. Drives the launch check.
func exeImports(_ path: String) -> [String] {
    guard let d = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe), d.count > 0x100 else { return [] }
    func u16(_ o: Int) -> Int { o + 2 <= d.count ? Int(d[o]) | Int(d[o+1]) << 8 : 0 }
    func u32(_ o: Int) -> Int { o + 4 <= d.count ? u16(o) | u16(o+2) << 16 : 0 }
    let pe = u32(0x3C); guard u32(pe) == 0x4550 else { return [] }
    let nSec = u16(pe + 6), opt = pe + 24, plus = u16(opt) == 0x20b, secs = opt + u16(pe + 20)
    func off(_ rva: Int) -> Int? {
        for i in 0..<nSec { let s = secs + i * 40; let va = u32(s + 12), sz = max(u32(s + 8), u32(s + 16))
            if rva >= va && rva < va + sz { return rva - va + u32(s + 20) } }
        return nil
    }
    guard let imp = off(u32(opt + (plus ? 112 : 96) + 8)) else { return [] }
    var out: [String] = [], i = imp
    while u32(i + 12) != 0, let n = off(u32(i + 12)) {
        var e = n; while e < d.count && d[e] != 0 { e += 1 }
        out.append(String(decoding: d[n..<e], as: UTF8.self).lowercased()); i += 20
    }
    return out
}
// Executable era: "dos" (plain MZ), "win16" (NE), or "pe" with the subsystem major version the linker stamped
// (4 = Windows 95/NT4 era, 5 = 2000/XP, 6+ = Vista and later). Old ones get a virtual desktop so fullscreen mode switches don't fight Retina.
// `linker` is OptionalHeader.MajorLinkerVersion: 6 = Visual C++ 6 (1998), 7–9 = VC 2002–2008, 10+ = 2010 and later, 2 = GNU ld (MinGW),
// which stamps old subsystem numbers on brand-new programs, so the era rules ignore it.
func exeEra(_ path: String) -> (kind: String, subsystem: Int, linker: Int) {
    guard let d = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe), d.count > 0x40, d[0] == 0x4D, d[1] == 0x5A else { return ("", 0, 0) }
    func u16(_ o: Int) -> Int { o + 2 <= d.count ? Int(d[o]) | Int(d[o+1]) << 8 : 0 }
    let h = u16(0x3C) | u16(0x3E) << 16
    guard h + 4 < d.count else { return ("dos", 0, 0) }
    if d[h] == 0x4E, d[h+1] == 0x45 { return ("win16", 3, 0) }       // "NE"
    if d[h] == 0x50, d[h+1] == 0x45 { return ("pe", u16(h + 24 + 48), h + 26 < d.count ? Int(d[h + 24 + 2]) : 0) } // "PE"
    return ("dos", 0, 0)
}

// DLLs the engine provides itself; anything imported that is neither here, nor beside the exe, nor in system32 is really missing.
let builtinDLLs: Set<String> = {
    let b = ((wineBin as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent + "/lib/wine"
    return Set(["x86_64-windows", "i386-windows"].flatMap { (try? FileManager.default.contentsOfDirectory(atPath: "\(b)/\($0)")) ?? [] }.map { $0.lowercased() })
}()
// Missing DLL -> winetricks verb that supplies it. ponytail: only runtimes Wine has no builtin for; extend when a game asks for more.
let depVerbs = ["mscoree.dll": "dotnet48", "physxloader.dll": "physx", "physxloader64.dll": "physx", "xlive.dll": "gfw",
                "msvcr71.dll": "vcrun2003", "msvcp71.dll": "vcrun2003", "mfc42.dll": "mfc42", "vb6stkit.dll": "vb6run"]
let winetricks = ["/opt/homebrew/bin/winetricks", "/usr/local/bin/winetricks"].first { FileManager.default.fileExists(atPath: $0) }

// Extract the main icon from a Windows .exe (PE resources) and return it as an NSImage.
func exeIcon(_ path: String) -> NSImage? {
    guard let d = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe), d.count > 0x100 else { return nil }
    func u16(_ o: Int) -> Int { o + 2 <= d.count ? Int(d[o]) | Int(d[o+1]) << 8 : 0 }
    func u32(_ o: Int) -> Int { o + 4 <= d.count ? u16(o) | u16(o+2) << 16 : 0 }
    let pe = u32(0x3C)
    guard u32(pe) == 0x4550 else { return nil }
    let nSec = u16(pe + 6), opt = pe + 24
    let plus = u16(opt) == 0x20b
    let resRVA = u32(opt + (plus ? 112 : 96) + 16)
    guard resRVA != 0 else { return nil }
    let secs = opt + u16(pe + 20)
    func off(_ rva: Int) -> Int? {
        for i in 0..<nSec { let s = secs + i * 40
            let va = u32(s + 12), sz = max(u32(s + 8), u32(s + 16))
            if rva >= va && rva < va + sz { return rva - va + u32(s + 20) } }
        return nil
    }
    guard let root = off(resRVA) else { return nil }
    // entries of a resource directory: (id, offset, isDir)
    func entries(_ dir: Int) -> [(Int, Int, Bool)] {
        let n = u16(dir + 12) + u16(dir + 14)
        return (0..<n).map { i in let e = dir + 16 + i * 8; let o = u32(e + 4)
            return (u32(e), root + (o & 0x7fffffff), o & 0x80000000 != 0) }
    }
    // resources of a type: [id: data], first language only
    func res(_ type: Int) -> [Int: Data] {
        var out: [Int: Data] = [:]
        guard let t = entries(root).first(where: { $0.0 == type && $0.2 }) else { return out }
        for n in entries(t.1) where n.2 {
            guard let l = entries(n.1).first, !l.2, let o = off(u32(l.1)) else { continue }
            let sz = u32(l.1 + 4)
            if o + sz <= d.count { out[n.0] = d.subdata(in: o..<o + sz) }
        }
        return out
    }
    let icons = res(3)
    guard let grp = res(14).sorted(by: { $0.key < $1.key }).first?.value, grp.count >= 6 else { return nil }
    func g16(_ o: Int) -> Int { Int(grp[o]) | Int(grp[o+1]) << 8 }
    var best: (w: Int, bits: Int, id: Int)?
    for i in 0..<g16(4) where 6 + i * 14 + 14 <= grp.count {
        let e = 6 + i * 14
        let w = grp[e] == 0 ? 256 : Int(grp[e]), bits = g16(e + 6), id = g16(e + 12)
        if icons[id] != nil, best == nil || (w, bits) > (best!.w, best!.bits) { best = (w, bits, id) }
    }
    guard let b = best, let img = icons[b.id] else { return nil }
    var ico = Data([0, 0, 1, 0, 1, 0])
    ico.append(Data([UInt8(b.w == 256 ? 0 : b.w), UInt8(b.w == 256 ? 0 : b.w), 0, 0, 1, 0, UInt8(b.bits & 255), UInt8(b.bits >> 8)]))
    withUnsafeBytes(of: UInt32(img.count).littleEndian) { ico.append(contentsOf: $0) }
    withUnsafeBytes(of: UInt32(22).littleEndian) { ico.append(contentsOf: $0) }
    ico.append(img)
    return NSImage(data: ico)
}

@MainActor final class Model: ObservableObject {
    @Published var bottles: [String] = []
    @Published var selected = ""
    @Published var programs: [String] = []
    @Published var log = engineOK ? "" : "Wine engine not found at \(wineBin)\n"
    @Published var busy = false
    var icons: [String: NSImage] = [:]
    @Published var hud = false       // MTL_HUD_ENABLED (Metal performance overlay)
    @Published var retina = false    // Wine Mac Driver RetinaMode
    @Published var drivers: Set<String> = []   // enabled renderer folders (DRIVERS= in cosmopolitan.env)
    @Published var autoDrivers = true          // DRIVERS absent or "auto"
    @Published var driverStatus: (Color, String) = (.gray, "")   // traffic light + one-line reason
    @Published var padStatus: (Color, String) = (.gray, "")
    var loading = false
    // green = will work, yellow = will work with a caveat / nothing to test right now, red = broken until fixed.
    func updateStatus() {
        guard !selected.isEmpty else { driverStatus = (.gray, "no bottle"); padStatus = (.gray, "no bottle"); return }
        let list = driverList(launchEnvRaw(), bottle: selected), fm = FileManager.default
        let missing = list.filter { !fm.fileExists(atPath: "\(driversDir)/\($0)/wine") }
        let d3d11 = list.filter { ["dxmt", "dxvk", "dxvk3", "d3dmetal"].contains($0) }
        let icdFile = launchEnv(selected)["VK_DRIVER_FILES"] ?? ""
        let icdLib = ((try? String(contentsOfFile: icdFile, encoding: .utf8)) ?? "").components(separatedBy: "\"library_path\":\"").dropFirst().first?.components(separatedBy: "\"").first ?? ""
        let icd = fm.fileExists(atPath: icdLib)   // the json must exist AND point at a real libMVK.dylib
        if !engineOK { driverStatus = (.red, "Wine engine missing") }
        else if !missing.isEmpty { driverStatus = (.red, "missing: " + missing.joined(separator: ", ")) }
        else if !icd { driverStatus = (.red, "MoltenVK ICD missing (no Vulkan)") }
        else if d3d11.count > 1 { driverStatus = (.yellow, "conflict: " + d3d11.joined(separator: " + ") + " — keep one") }
        else if d3d11.isEmpty { driverStatus = (.yellow, "no Direct3D 10/11 driver enabled") }
        else { driverStatus = (.green, list.joined(separator: " + ")) }
        let bus = regSection("system.reg", "System\\CurrentControlSet\\Services\\winebus")
        let pads = sh("ioreg -r -c IOHIDDevice -l 2>/dev/null | grep -o '\"Product\" = \"[^\"]*\"' | grep -i 'DualSense\\|Wireless Controller\\|Xbox\\|Gamepad' | cut -d'\"' -f4 | sort -u | tr '\\n' ',' | sed 's/,$//'")
        if !bus.contains("\"DisableHidraw\"=dword:00000001") || bus.contains("\"Enable SDL\"=dword:00000000") { padStatus = (.red, "bottle not set for SDL pads → Repair") }
        else if pads.isEmpty { padStatus = (.yellow, "bottle ready, no controller switched on") }
        else { padStatus = (.green, pads) }
    }
    func setDriver(_ d: String, _ on: Bool) {
        if on { drivers.insert(d) } else { drivers.remove(d) }
        autoDrivers = false
        envSet("DRIVERS", drivers.sorted().joined(separator: ","))   // "DRIVERS=" (empty) means none, unlike absent = auto
        updateStatus()
    }
    func setAuto(_ on: Bool) {
        autoDrivers = on
        if on { drivers = Set(autoDriverSet); envSet("DRIVERS", nil) } else { envSet("DRIVERS", drivers.sorted().joined(separator: ",")) }
        updateStatus()
    }
    @Published var template = "auto"
    // "auto": new bottles are win10; each old program gets its own Windows version (win98 / winxp) from its exe header at launch.
    let templates = ["auto", "win11", "win10", "win7", "winxp", "win98", "win95"]
    @Published var driverUpdates = ""   // "dxmt v0.81 available" — filled by the weekly check, applied by Update…
    @Published var readiness: [String: Needs] = [:]   // per-program pre-verification (tile light + tooltip)
    @Published var autostartSteam = false              // AUTOSTART_STEAM=1 in cosmopolitan.env: Steam comes up with the app, with the bottle's drivers
    @Published var batterySaver = false   // 60 fps cap in D3DMetal and DXMT, DXMT renders at 2/3 and MetalFX-upscales: far less GPU work on battery
    @Published var metalFX = false        // D3DM_ENABLE_METALFX: a game's DLSS menu option becomes MetalFX temporal upscaling (D3DMetal, macOS 26+)
    func setBatterySaver(_ on: Bool) {
        envSet("D3DM_MAX_FPS", on ? "60" : nil)
        envSet("DXMT_CONFIG", on ? "d3d11.preferredMaxFrameRate=60;d3d11.metalSpatialUpscaleFactor=1.5" : nil)
    }
    // Stop Steam: ask politely, and if it is still up after 20 s (it sometimes ignores -shutdown), end its processes.
    func steamRunning() -> Bool { !sh("ps -axo command= | grep -c '^C:.Program Files (x86).Steam.steam.exe'").hasPrefix("0") }
    func stopSteam() async {
        wine(selected, ["C:\\Program Files (x86)\\Steam\\steam.exe", "-shutdown"], block: false)
        for _ in 0..<20 { try? await Task.sleep(nanoseconds: 1_000_000_000); if !steamRunning() { break } }
        if steamRunning() { log += "Steam ignored the shutdown request; stopping it.\n"; _ = sh("pkill -f 'steam.exe'; sleep 3; pkill -9 -f 'steamwebhelper|steamservice'; sleep 1") }
        // Let the prefix's wineserver finish tearing down (≤15 s); relaunching into a dying server made Steam fail to create its first window.
        _ = sh("env WINEPREFIX='\(bottlesDir)/\(selected)' perl -e 'alarm 15; exec @ARGV' -- '\((wineBin as NSString).deletingLastPathComponent)/wineserver' -w 2>/dev/null; sleep 1")
    }
    // Steam hands its environment to every game it starts, so a bottle-wide env change needs Steam restarted. Only when no game is running.
    func restartSteamIfIdle() {
        guard let s = programs.first(where: { $0.hasSuffix("/Steam/steam.exe") }), steamRunning(),
              sh("ps -axo command= | grep -c 'steamapps.common'").hasPrefix("0") else { return }
        log += "Restarting Steam so the change reaches games…\n"
        Task { @MainActor in await stopSteam(); launch(s) }
    }
    func autostart() {   // a bottle with Steam gets Steam started with the app (AUTOSTART_STEAM=0 in cosmopolitan.env opts out)
        guard launchEnvRaw()["AUTOSTART_STEAM"] != "0", let s = programs.first(where: { $0.hasSuffix("/Steam/steam.exe") }) else { return }
        launch(s)   // launch() skips it when Steam is already running
    }
    var watchers: [DispatchSourceFileSystemObject] = [], watchedBottle = "", rescanWork: DispatchWorkItem?
    // Watch the bottle's program folders: a finished Steam install or an installer's output shows up without clicking anything.
    func watchBottle() {
        watchers.forEach { $0.cancel() }; watchers = []; watchedBottle = selected
        guard !selected.isEmpty else { return }
        let c = "\(bottlesDir)/\(selected)/drive_c"
        for dir in ["\(c)/Program Files (x86)/Steam/steamapps", "\(c)/Program Files", "\(c)/Program Files (x86)"] {
            let fd = open(dir, O_EVTONLY); guard fd >= 0 else { continue }
            let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
            src.setEventHandler { [weak self] in
                guard let self else { return }
                rescanWork?.cancel()
                let w = DispatchWorkItem { Task { @MainActor in self.scan() } }; rescanWork = w
                DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: w)   // debounce: Steam touches the folder many times per install
            }
            src.setCancelHandler { close(fd) }
            src.resume(); watchers.append(src)
        }
    }

    init() {
        refresh()
        checkDriverUpdates()
        autostart()
        // Pad on/off and driver folders change outside the app; re-check every 5 s (one ioreg call, ~30 ms).
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in Task { @MainActor in self?.updateStatus() } }
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in Task { @MainActor in self?.memoryAdvisor() } }
    }

    func refresh() {
        let all = (try? FileManager.default.contentsOfDirectory(atPath: bottlesDir)) ?? []
        // Safety clones made before Repair (.auto-<bottle>-<date>) stay hidden and are dropped after 30 days.
        for b in all where b.hasPrefix(".auto-") {
            if let m = (try? FileManager.default.attributesOfItem(atPath: "\(bottlesDir)/\(b)"))?[.modificationDate] as? Date, Date().timeIntervalSince(m) > 30 * 86400 { try? FileManager.default.removeItem(atPath: "\(bottlesDir)/\(b)") }
        }
        bottles = all.filter { !$0.hasPrefix(".") }.sorted()
        if !bottles.contains(selected) { selected = bottles.first ?? "" }
        scan()
    }

    // Per-bottle settings: KEY=VALUE lines in <bottle>/cosmopolitan.env.
    var envPath: String { "\(bottlesDir)/\(selected)/cosmopolitan.env" }
    func envSet(_ key: String, _ value: String?) {
        guard !selected.isEmpty else { return }
        var lines = ((try? String(contentsOfFile: envPath, encoding: .utf8)) ?? "").components(separatedBy: "\n")
            .filter { !$0.isEmpty && !$0.hasPrefix(key + "=") }
        if let v = value { lines.append("\(key)=\(v)") }
        try? (lines.joined(separator: "\n") + "\n").write(toFile: envPath, atomically: true, encoding: .utf8)
    }

    func loadSettings() {
        loading = true
        let e = launchEnvRaw()
        hud = e["MTL_HUD_ENABLED"] == "1"
        autostartSteam = e["AUTOSTART_STEAM"] == "1"
        batterySaver = e["D3DM_MAX_FPS"] != nil
        metalFX = e["D3DM_ENABLE_METALFX"] == "1"
        autoDrivers = e["DRIVERS"] == nil || e["DRIVERS"] == "auto"
        drivers = Set(driverList(e, bottle: selected))
        let reg = (try? String(contentsOfFile: "\(bottlesDir)/\(selected)/user.reg", encoding: .utf8)) ?? ""
        let sec = reg.components(separatedBy: "[Software\\\\Wine\\\\Mac Driver]").dropFirst().first?.components(separatedBy: "\n[").first ?? ""
        retina = sec.contains("\"RetinaMode\"=\"y\"")
        loading = false
        updateStatus()
    }
    func launchEnvRaw() -> [String: String] {
        var e: [String: String] = [:]
        for l in ((try? String(contentsOfFile: envPath, encoding: .utf8)) ?? "").components(separatedBy: "\n") {
            let kv = l.split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2 { e[kv[0]] = kv[1] }
        }
        return e
    }

    // Installed programs = non-helper .exe files directly inside each app folder under Program Files.
    func scan() {
        loadSettings()
        programs = []
        guard !selected.isEmpty else { return }
        let c = "\(bottlesDir)/\(selected)/drive_c"
        var found: [String] = []
        for root in ["Program Files", "Program Files (x86)"] {
            guard let apps = try? FileManager.default.contentsOfDirectory(atPath: "\(c)/\(root)") else { continue }
            for app in apps where !app.hasPrefix(".") && !["Common Files", "Internet Explorer", "Windows NT", "Windows Media Player", "Windows Defender", "Microsoft", "Wine", "WindowsApps"].contains(app) {
                let base = "\(c)/\(root)/\(app)"
                let items = (try? FileManager.default.subpathsOfDirectory(atPath: base)) ?? []
                for i in items where i.lowercased().hasSuffix(".exe") && i.split(separator: "/").count == 1 {
                    let n = (i as NSString).lastPathComponent.lowercased()
                    if !skipExes.contains(where: { n.contains($0) }) { found.append("\(base)/\(i)") }
                }
            }
        }
        // Steam library: one entry per appmanifest, pointing at the biggest top-level exe in its install folder.
        let lib = "\(c)/Program Files (x86)/Steam/steamapps"
        for f in (try? FileManager.default.contentsOfDirectory(atPath: lib)) ?? [] where f.hasPrefix("appmanifest_") {
            guard let acf = try? String(contentsOfFile: "\(lib)/\(f)", encoding: .utf8) else { continue }
            func val(_ k: String) -> String { acf.components(separatedBy: "\"\(k)\"").dropFirst().first?.components(separatedBy: "\"").dropFirst().first ?? "" }
            let id = val("appid"), dir = "\(lib)/common/\(val("installdir"))"
            guard id != "228980" else { continue }   // Steamworks Common Redistributables
            // Biggest real exe: top level first; Unreal games keep it in <Game>/Binaries/Win64 with nothing at the top, so fall back to a 4-deep walk.
            func exes(_ depth: Int) -> [String] {
                guard let en = FileManager.default.enumerator(atPath: dir) else { return [] }
                var out: [String] = []
                for case let p as String in en {
                    if en.level > depth || p.hasPrefix("Engine/") || p.lowercased().contains("redist") { en.skipDescendants(); continue }
                    let n = (p as NSString).lastPathComponent.lowercased()
                    if n.hasSuffix(".exe") && !skipExes.contains(where: { n.contains($0) }) { out.append(p) }
                }
                return out
            }
            var found1 = exes(1); if found1.isEmpty { found1 = exes(4) }
            guard let exe = found1.max(by: { a, b in
                let s = { (n: String) in (try? FileManager.default.attributesOfItem(atPath: "\(dir)/\(n)"))?[.size] as? Int ?? 0 }; return s(a) < s(b) }) else { continue }
            steamGames["\(dir)/\(exe)"] = (id, val("name"))
            found.append("\(dir)/\(exe)")
        }
        // Extras from "Find apps" (dropped silently once uninstalled).
        for p in ((try? String(contentsOfFile: "\(bottlesDir)/\(selected)/cosmopolitan.apps", encoding: .utf8)) ?? "").components(separatedBy: "\n")
            where !p.isEmpty && !found.contains(p) && FileManager.default.fileExists(atPath: p) { found.append(p) }
        for p in found where icons[p] == nil { icons[p] = exeIcon(p) }
        programs = found.sorted { ($0 as NSString).lastPathComponent.lowercased() < ($1 as NSString).lastPathComponent.lowercased() }
        verifyAll()
        if watchedBottle != selected { watchBottle(); excludeFromBackups(selected) }
    }

    // Run any executable; `block` locks the UI buttons until it exits.
    func exec(_ path: String, _ args: [String], env: [String: String] = [:], block: Bool = true, exe: String? = nil, then: (@MainActor () -> Void)? = nil) {
        if block { busy = true }
        log += "$ \((path as NSString).lastPathComponent) \(args.joined(separator: " "))\n"
        let started = Date()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.environment = ProcessInfo.processInfo.environment.merging(env) { $1 }
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { h in
            let s = String(decoding: h.availableData, as: UTF8.self)
            if !s.isEmpty { logToFile(s); Task { @MainActor in self.log += s } }
        }
        p.terminationHandler = { t in let code = t.terminationStatus; Task { @MainActor in
            pipe.fileHandleForReading.readabilityHandler = nil
            if block { self.busy = false }
            self.log += code == 0 ? "[done]\n" : "[failed: exit \(code)]\n"
            if let exe, code != 0, Date().timeIntervalSince(started) < 60 { self.triage(exe, code) }   // died right away: look for a known cause
            then?(); self.refresh() } }
        do { try p.run() } catch { log += "Failed: \(error)\n"; busy = false }
    }

    func wine(_ bottle: String, _ args: [String], block: Bool = true, env: [String: String] = [:], drivers: [String]? = nil, exe: String? = nil, then: (@MainActor () -> Void)? = nil) {
        guard engineOK else { log += "Wine engine missing.\n"; return }
        exec(exe.map(loaderNamed) ?? wineBin, args, env: launchEnv(bottle, drivers: drivers).merging(env) { $1 }, block: block, exe: exe, then: then)
    }

    func createBottle(_ name: String, then: (@MainActor () -> Void)? = nil) {
        let t = template == "auto" ? "win10" : template
        try? FileManager.default.createDirectory(atPath: "\(bottlesDir)/\(name)", withIntermediateDirectories: true)
        // mscoree/mshtml off: skips Mono/Gecko download prompts during creation.
        wine(name, ["wineboot", "-u"], env: ["WINEDLLOVERRIDES": "mscoree,mshtml="]) {
            // Controllers via SDL as XInput gamepads (raw HID only reaches DirectInput, and Steam Input can't drive it under Wine).
            self.wine(name, ["reg", "add", "HKLM\\System\\CurrentControlSet\\Services\\winebus", "/v", "DisableHidraw", "/t", "REG_DWORD", "/d", "1", "/f"]) {
                self.wine(name, ["winecfg", "-v", t]) {
                    // Restricted by default: no Z: (whole Mac) drive. Programs see C: only. FULL_DISK=1 in cosmopolitan.env restores Z: for a bottle.
                    try? FileManager.default.removeItem(atPath: "\(bottlesDir)/\(name)/dosdevices/z:")
                    self.log += "Bottle \(name): restricted to C: (no access to the Mac's files). Add FULL_DISK=1 to its cosmopolitan.env to widen it.\n"
                    then?() } } }
    }

    func deleteBottle() {   // to Trash, so it's recoverable
        try? FileManager.default.trashItem(at: URL(fileURLWithPath: "\(bottlesDir)/\(selected)"), resultingItemURL: nil)
        log += "Moved \(selected) to Trash.\n"; refresh()
    }

    // Backup = instant APFS clone (no extra disk space until files change).
    func backupBottle() {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmm"
        exec("/bin/cp", ["-cR", "\(bottlesDir)/\(selected)", "\(bottlesDir)/\(selected)-backup-\(f.string(from: Date()))"])
    }

    func setRetina(_ on: Bool) {
        wine(selected, ["reg", "add", "HKCU\\Software\\Wine\\Mac Driver", "/v", "RetinaMode", "/t", "REG_SZ", "/d", on ? "y" : "n", "/f"])
    }

    func archiveBottle() {
        let p = NSSavePanel(); p.nameFieldStringValue = selected + ".tar"
        if p.runModal() == .OK, let u = p.url { exec("/usr/bin/tar", ["-cf", u.path, "-C", bottlesDir, selected]) }
    }

    func restoreBottle() {
        let p = NSOpenPanel()
        guard p.runModal() == .OK, let u = p.url else { return }
        var name = u.deletingPathExtension().lastPathComponent
        if bottles.contains(name) { name += "-restored" }
        // extract to a hidden temp dir, then rename the single top folder to the target name
        exec("/bin/sh", ["-c", "set -e; t=$(mktemp -d \"$1/.restore.XXXX\"); tar -xf \"$2\" -C \"$t\"; mv \"$t\"/* \"$1/$3\"; rmdir \"$t\"", "sh", bottlesDir, u.path, name])
    }

    // Steam's CEF UI renders black under Wine unless the sandbox and GPU path are off.
    func extraArgs(_ exe: String) -> [String] {
        (exe as NSString).lastPathComponent.lowercased() == "steam.exe" ? ["-no-cef-sandbox", "-cef-disable-gpu", "-cef-disable-gpu-compositing", "-cef-disable-d3d11"] : []
    }

    func winPath(_ exe: String) -> String {
        "C:" + exe.components(separatedBy: "/drive_c")[1].replacingOccurrences(of: "/", with: "\\")
    }

    // Dock shortcut: a tiny .app that runs the program in its bottle. Drag it to the Dock.
    // Dock label: macOS names the process after its executable file. A symlink is forgotten (Wine re-execs through the real path) and a
    // bundle path breaks Steam's first window, but a *copy* of the 27 KB loader named after the program, kept in the engine's bin folder so
    // libraries resolve, survives the re-exec — the CrossOver trick. Children inherit it, so Steam's helpers are "Steam" too.
    func loaderNamed(_ exe: String) -> String {
        let name = appName(exe).replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        guard name != "wine", !name.isEmpty else { return wineBin }
        let copy = (wineBin as NSString).deletingLastPathComponent + "/" + name, fm = FileManager.default
        let fresh = (try? fm.attributesOfItem(atPath: copy))?[.modificationDate] as? Date ?? .distantPast
        let src = (try? fm.attributesOfItem(atPath: wineBin))?[.modificationDate] as? Date ?? .distantPast
        if fresh < src { try? fm.removeItem(atPath: copy); try? fm.copyItem(atPath: wineBin, toPath: copy) }   // refresh after an engine update
        return fm.fileExists(atPath: copy) ? copy : wineBin
    }
    func makeShortcut(_ exe: String, reveal: Bool = true) {
        let name = appName(exe), fm = FileManager.default
        let app = NSHomeDirectory() + "/Applications/Cosmopolitan Apps/\(name).app"
        try? fm.removeItem(atPath: app)
        try? fm.createDirectory(atPath: app + "/Contents/MacOS", withIntermediateDirectories: true)
        try? fm.createDirectory(atPath: app + "/Contents/Resources", withIntermediateDirectories: true)
        let (win, args) = launchCmd(exe)
        let exports = launchEnv(selected).map { "export \($0.key)='\($0.value)'" }.joined(separator: "\n")
        let script = "#!/bin/sh\nps -axo command | grep -v grep | grep -q -F '\(winPath(exe))' && exit 0\n\(exports)\nexec '\(loaderNamed(exe))' '\(win)' \(args.joined(separator: " "))\n"
        fm.createFile(atPath: app + "/Contents/MacOS/launch", contents: Data(script.utf8), attributes: [.posixPermissions: 0o755])
        var icon = ""
        if let t = icons[exe]?.tiffRepresentation, let png = NSBitmapImageRep(data: t)?.representation(using: .png, properties: [:]) {
            let tmp = app + "/Contents/Resources/icon.png"
            try? png.write(to: URL(fileURLWithPath: tmp))
            let sips = Process(); sips.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
            sips.arguments = ["-s", "format", "icns", tmp, "--out", app + "/Contents/Resources/icon.icns"]
            sips.standardOutput = FileHandle.nullDevice; sips.standardError = FileHandle.nullDevice
            try? sips.run(); sips.waitUntilExit()
            try? fm.removeItem(atPath: tmp)
            icon = "<key>CFBundleIconFile</key><string>icon</string>"
        }
        let plist = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict><key>CFBundleName</key><string>\(name)</string><key>CFBundleExecutable</key><string>launch</string><key>CFBundleIdentifier</key><string>local.cosmopolitan.\(name.filter { $0.isLetter || $0.isNumber })</string><key>CFBundlePackageType</key><string>APPL</string><key>LSApplicationCategoryType</key><string>public.app-category.games</string>\(icon)</dict></plist>"   // games category: macOS Game Mode can engage for fullscreen play
        try? plist.write(toFile: app + "/Contents/Info.plist", atomically: true, encoding: .utf8)
        let cs = Process(); cs.executableURL = URL(fileURLWithPath: "/usr/bin/codesign"); cs.arguments = ["--force", "--sign", "-", app]
        try? cs.run(); cs.waitUntilExit()
        guard reveal else { return }
        log += "Shortcut created: \(app) — drag it to the Dock.\n"
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: app)])
    }

    // Automatic: no bottle yet -> create one named after the installer, then run it.
    func install(_ url: URL) {
        let path = url.path
        let go: (String) -> Void = { b in
            self.selected = b
            if path.lowercased().hasSuffix(".msi") { self.wine(b, ["msiexec", "/i", "Z:" + path.replacingOccurrences(of: "/", with: "\\")]) }
            else { let need = self.prepare(path); self.start(need, path, [], exe: path, block: true) }   // installers get the same checks as programs
        }
        if selected.isEmpty {
            let name = url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: " ", with: "_")
            createBottle(name) { go(name) }
        } else { go(selected) }
    }

    // Launch each program once: skip if its Windows path is already a running process.
    func launch(_ exe: String) {
        let win = winPath(exe)
        let ps = Process(); ps.executableURL = URL(fileURLWithPath: "/bin/ps"); ps.arguments = ["-axo", "command"]
        let out = Pipe(); ps.standardOutput = out
        try? ps.run()
        let list = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        if list.components(separatedBy: "\n").contains(where: { $0.hasPrefix(win) }) {
            log += "\((exe as NSString).lastPathComponent) is already running.\n"; return
        }
        let (cmd, args) = launchCmd(exe)
        log += powerHints()
        let need = prepare(exe)
        // A Steam game inherits Steam's environment, so a driver change OR per-game env from Options… needs Steam restarted with it.
        start(need, cmd, args, exe: exe, restartSteam: steamGames[exe] != nil && (need.drivers != nil || !need.env.isEmpty) && list.contains("C:\\Program Files (x86)\\Steam\\steam.exe"))
    }

    // Launch check + the registry it implies (overrides, old-era desktop, Windows version). Returns what start() needs.
    func prepare(_ exe: String) -> Needs {
        let need = launchNeeds(exe)
        log += need.note
        // Community DLL overrides go into the bottle registry (idempotent, same place protonfixes puts them).
        let regEnv = launchEnv(selected).map { "\($0.key)='\($0.value)'" }.joined(separator: " ")
        func reg(_ key: String, _ name: String, _ value: String) { _ = sh("env \(regEnv) '\(wineBin)' reg add '\(key)' /v '\(name)' /t REG_SZ /d '\(value)' /f >/dev/null 2>&1") }
        if !need.overrides.isEmpty {
            let mark = "\(bottlesDir)/\(selected)/options/.overrides-\((exe as NSString).lastPathComponent)"
            if !FileManager.default.fileExists(atPath: mark) { snapshot("before community DLL overrides for \((exe as NSString).lastPathComponent)"); try? FileManager.default.createDirectory(atPath: (mark as NSString).deletingLastPathComponent, withIntermediateDirectories: true); FileManager.default.createFile(atPath: mark, contents: nil) }
            for (dll, mode) in need.overrides { reg("HKCU\\Software\\Wine\\DllOverrides", dll, mode) }
        }
        // Old program: per-exe virtual desktop + Retina off (AppDefaults keys apply however the exe is started, also via Steam).
        // §9.1 Mouse capture for camera-heavy games: Options MOUSE_CAPTURE=1 → Wine keeps the cursor inside the game window.
        if options(exe)["MOUSE_CAPTURE"] == "1" { reg("HKCU\\Software\\Wine\\AppDefaults\\\((exe as NSString).lastPathComponent)\\DirectInput", "MouseWarpOverride", "force") }
        if need.desktop {
            // §7.6 Notch-aware: the virtual desktop never exceeds the area below the notch (safe area), so nothing hides behind it.
            let scr = NSScreen.main, safeW = Int((scr?.frame.width ?? 1280) - (scr?.safeAreaInsets.left ?? 0) - (scr?.safeAreaInsets.right ?? 0)), safeH = Int((scr?.frame.height ?? 960) - (scr?.safeAreaInsets.top ?? 0) - (scr?.safeAreaInsets.bottom ?? 0))
            let want = exeEra(exe).kind == "win16" ? (1024, 768) : (1280, 960)
            let e = (exe as NSString).lastPathComponent, size = "\(min(want.0, safeW))x\(min(want.1, safeH))"
            reg("HKCU\\Software\\Wine\\Explorer\\Desktops", "Cosmopolitan", size)
            reg("HKCU\\Software\\Wine\\AppDefaults\\\(e)\\Explorer", "Desktop", "Cosmopolitan")
            reg("HKCU\\Software\\Wine\\AppDefaults\\\(e)\\Mac Driver", "RetinaMode", "n")
        }
        if !need.winver.isEmpty { reg("HKCU\\Software\\Wine\\AppDefaults\\\((exe as NSString).lastPathComponent)", "Version", need.winver) }
        if let t = tuneUnreal(exe) { log += t }
        // Filesystem access: restricted bottles have no Z:. FULL_DISK=1 in cosmopolitan.env restores it (with a warning); removing the line takes it away again.
        let z = "\(bottlesDir)/\(selected)/dosdevices/z:", full = launchEnvRaw()["FULL_DISK"] == "1"
        if full, !FileManager.default.fileExists(atPath: z) { snapshot("before enabling full disk access"); try? FileManager.default.createSymbolicLink(atPath: z, withDestinationPath: "/"); log += "⚠ \(selected): full disk access enabled (FULL_DISK=1) — programs in this bottle can read and write your files.\n" }
        if !full, FileManager.default.fileExists(atPath: z), launchEnvRaw()["FULL_DISK"] == "0" { try? FileManager.default.removeItem(atPath: z); log += "\(selected): full disk access removed.\n" }
        return need
    }

    // Unreal games: once their own settings file exists, turn VSync off (a frame-rate killer under translation) and start the three
    // heaviest scalability groups at Medium if the game hasn't set any. One-shot, marked in the file; the in-game menu stays in charge afterwards.
    func tuneUnreal(_ exe: String) -> String? {
        // Disabled 2026-10-22: writing a partial [ScalabilityGroups] section made Unreal fall back to defaults for every other group
        // (native resolution, no upscaler) and tanked Dawnwalker to ~10 fps. Graphics settings belong to the game's own menu.
        return nil
        guard exe.contains("/Binaries/Win64/") else { return nil }
        let project = ((exe as NSString).lastPathComponent as NSString).deletingPathExtension.replacingOccurrences(of: "-Win64-Shipping", with: "")
        let ini = "\(bottlesDir)/\(selected)/drive_c/users/\(NSUserName())/AppData/Local/\(project)/Saved/Config/Windows/GameUserSettings.ini"
        // The game rewrites this file and drops comments, so the "done once" marker is a sidecar file, not a line in the ini.
        let marker = "\(bottlesDir)/\(selected)/options/.tuned-\(project)"
        guard var s = try? String(contentsOfFile: ini, encoding: .utf8), !FileManager.default.fileExists(atPath: marker) else { return nil }
        s = s.replacingOccurrences(of: "bUseVSync=True", with: "bUseVSync=False")   // some games re-assert their own VSync setting; harmless if so
        if !s.contains("[ScalabilityGroups]") { s += "\n[ScalabilityGroups]\nsg.ShadowQuality=1\nsg.GlobalIlluminationQuality=1\nsg.ReflectionQuality=1\n" }
        // Fullscreen mode is left alone: under the Mac driver presentation is composited either way (checked with the Metal HUD), so exclusive mode buys nothing.
        try? s.write(toFile: ini, atomically: true, encoding: .utf8)
        // Texture streaming pool: Unreal sizes it from the "VRAM" the translation layer reports, which undersells unified memory.
        // Give it ~1/4.5 of RAM (7 GB on a 32 GB Mac) through the per-user Engine.ini override, which the game does not rewrite.
        let pool = max(3000, Int(ProcessInfo.processInfo.physicalMemory / 1_048_576) * 2 / 9)
        let eng = (ini as NSString).deletingLastPathComponent + "/Engine.ini"
        var e = (try? String(contentsOfFile: eng, encoding: .utf8)) ?? ""
        if !e.contains("r.Streaming.PoolSize") { e += "\n[SystemSettings]\nr.Streaming.PoolSize=\(pool)\n"; try? e.write(toFile: eng, atomically: true, encoding: .utf8) }
        try? FileManager.default.createDirectory(atPath: (marker as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: marker, contents: nil)
        return "Tuned \(project): VSync off, shadows/GI/reflections start at Medium, \(pool / 1000) GB texture pool (change freely in the game's menu).\n"
    }

    // Steam overlay hooks the game's presentation and costs frames under translation; switch it off in Steam's config while Steam is down.
    func tuneSteam() {
        let cfgs = (try? FileManager.default.contentsOfDirectory(atPath: "\(bottlesDir)/\(selected)/drive_c/Program Files (x86)/Steam/userdata")) ?? []
        for u in cfgs {
            let p = "\(bottlesDir)/\(selected)/drive_c/Program Files (x86)/Steam/userdata/\(u)/config/localconfig.vdf"
            guard var s = try? String(contentsOfFile: p, encoding: .utf8), !s.contains("\"EnableGameOverlay\""), let r = s.range(of: "\"system\"\n\t{\n") else { continue }
            s.insert(contentsOf: "\t\t\"EnableGameOverlay\"\t\t\"0\"\n", at: r.upperBound)
            try? s.write(toFile: p, atomically: true, encoding: .utf8)
            logToFile("Steam overlay switched off\n"); log += "Steam overlay switched off (costs frames under translation).\n"
        }
    }

    // Run with everything prepare() found: runtimes first (winetricks), Steam restart if the driver set changed, then the program.
    func start(_ need: Needs, _ cmd: String, _ args: [String], exe: String, block: Bool = false, restartSteam: Bool = false) {
        var go = { self.wine(self.selected, [cmd] + args + need.args, block: block, env: need.env, drivers: need.drivers, exe: exe) }
        focusAutomation(exe); pauseInBackground(exe, anticheat: need.anticheat != nil)
        if steamGames[exe] != nil || exe.hasSuffix("/Steam/steam.exe"), sh("ps -axo command= | grep -c '^C:.Program Files (x86).Steam.steam.exe'").hasPrefix("0") { tuneSteam() }   // Steam is down: safe to edit its config
        // Steam games inherit the env of the *running* Steam, so a per-launch driver change needs Steam restarted with it.
        if restartSteam {
            log += "Restarting Steam so the game gets its drivers…\n"
            let run = go
            go = { Task { @MainActor in await self.stopSteam(); self.tuneSteam(); run() } }
        }
        if need.verbs.isEmpty { go() } else {
            snapshot("before installing \(need.verbs.joined(separator: " "))")
            // Runtime missing: let winetricks fetch it into this bottle first (output streams to the log), then start the program.
            var env = launchEnv(selected); env["WINE"] = wineBin; env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin")
            exec(winetricks!, ["-q"] + need.verbs, env: env) { go() }
        }
    }

    // Launch check: what the exe imports decides the driver set and any runtime to fetch. Nothing is written to the bottle settings.
    struct Needs { var drivers: [String]?; var verbs: [String]; var note: String; var overrides: [(String, String)] = []; var env: [String: String] = [:]; var args: [String] = []; var desktop = false; var winver = ""; var status: Color = .green; var dx12 = false; var anticheat: (Color, String)? = nil }
    func launchNeeds(_ exe: String) -> Needs {
        let name = (exe as NSString).lastPathComponent, dir = (exe as NSString).deletingLastPathComponent, fm = FileManager.default
        var imps = exeImports(exe)
        // Unreal games ship a tiny bootstrap exe; the real one is <Game>/Binaries/Win64/<Game>-Win64-Shipping.exe. Inspect that instead.
        if !imps.contains(where: { $0.hasPrefix("d3d") || $0 == "vulkan-1.dll" || $0 == "opengl32.dll" }), fm.fileExists(atPath: dir + "/Engine"),   // Unreal install root only
           let en = fm.enumerator(atPath: dir), let real = en.compactMap({ $0 as? String }).first(where: { $0.lowercased().hasSuffix("-shipping.exe") || ($0.contains("/Binaries/Win64/") && $0.lowercased().hasSuffix(".exe") && !$0.hasPrefix("Engine/")) }) {
            imps = exeImports("\(dir)/\(real)")
        }
        // Unreal 5 loads its D3D12 RHI at runtime (no import) but ships the Agility SDK beside the exe: Binaries/Win64/D3D12/D3D12Core.dll.
        if !imps.contains("d3d12.dll"), let en = fm.enumerator(atPath: dir) {
            for case let p as String in en {   // stay inside this program: never descend into a Steam library or the Unreal Engine folder
                if en.level > 4 || p.hasPrefix("Engine/") || p.hasPrefix("steamapps") { en.skipDescendants(); continue }
                if p.hasSuffix("D3D12/D3D12Core.dll") { imps.append("d3d12.dll"); break }
            }
        }
        let local = Set(((try? fm.contentsOfDirectory(atPath: dir)) ?? []).map { $0.lowercased() })
        let sys = Set(((try? fm.contentsOfDirectory(atPath: "\(bottlesDir)/\(selected)/drive_c/windows/system32")) ?? []).map { $0.lowercased() })
        let missing = imps.filter { !$0.hasPrefix("api-ms-") && !$0.hasPrefix("ext-ms-") && !builtinDLLs.contains($0) && !local.contains($0) && !sys.contains($0) }
        var parts: [String] = [], drivers: [String]? = nil
        // Era: 9x-era PE (subsystem 4), Win16 and DirectDraw titles get a per-program virtual desktop with Retina off; DOS goes to DOSBox.
        let era = exeEra(exe)
        var desktop = false
        var winver = ""   // Windows version reported to this exe when the picker is on "auto"
        switch era.kind {
        case "dos": parts.append(FileManager.default.fileExists(atPath: "/opt/homebrew/bin/dosbox") ? "DOS program — runs in DOSBox" : "DOS program — brew install dosbox-staging first")
        case "win16": desktop = true; winver = "win98"; parts.append("16-bit Windows program — 1024x768 virtual desktop, Retina off")
        default:
            let msvc = era.linker != 2   // GNU ld stamps subsystem 4/5 on new programs; only trust the number from Microsoft/Borland linkers
            if (era.subsystem > 0 && era.subsystem <= 4 && msvc) || imps.contains("ddraw.dll") { desktop = true; winver = "win98"; parts.append("Windows 9x-era program — 1280x960 virtual desktop, Retina off") }
            else if era.subsystem == 5 && (6...9).contains(era.linker) { winver = "winxp"; parts.append("XP-era program") }   // VC6–VC2008 builds
        }
        if template == "auto", !winver.isEmpty { parts.append("reports Windows as \(winver)") }
        if let gfx = [("d3d12.dll", "Direct3D 12"), ("d3d11.dll", "Direct3D 11"), ("d3d10.dll", "Direct3D 10"), ("d3d9.dll", "Direct3D 9"), ("d3d8.dll", "Direct3D 8"), ("ddraw.dll", "DirectDraw"), ("vulkan-1.dll", "Vulkan"), ("opengl32.dll", "OpenGL")].first(where: { imps.contains($0.0) }) { parts.append(gfx.1) }   // newest API first
        if imps.contains("d3d12.dll") {
            let cur = driverList(launchEnvRaw(), bottle: selected)
            if !d3dmetalInstalled() { parts.append("needs D3DMetal (not installed — Drivers › D3DMetal…)") }
            else if !d3dmetalOK { parts.append("needs D3DMetal — accept Apple's license first (Drivers › D3DMetal…)") }
            else if !cur.contains("d3dmetal") { drivers = cur.filter { !["dxmt", "dxvk", "dxvk3"].contains($0) } + ["d3dmetal"]; parts.append("switching to d3dmetal for this launch") }
        }
        var verbs = Array(Set(missing.compactMap { depVerbs[$0] })).sorted()
        // mscoree.dll is a Wine builtin stub; a .NET app only runs if Wine Mono (engine or bottle) or a real .NET Framework is installed.
        if imps.contains("mscoree.dll") {
            let engine = ((wineBin as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent
            let win = "\(bottlesDir)/\(selected)/drive_c/windows"
            let hasNet = [engine + "/share/wine/mono", win + "/mono", win + "/Microsoft.NET/Framework64/v4.0.30319/clr.dll", win + "/Microsoft.NET/Framework/v4.0.30319/clr.dll"].contains { fm.fileExists(atPath: $0) }
            if hasNet { parts.append(".NET app (Wine Mono present)") } else { verbs.append("dotnet48"); parts.append(".NET app") }
        }
        // Steam game: what Linux players needed (umu-protonfixes) is what we need too, minus Proton-only knobs.
        var n = Needs(drivers: drivers, verbs: [], note: "", desktop: desktop, winver: template == "auto" ? winver : "", dx12: imps.contains("d3d12.dll"))
        // Anti-cheat: local signatures first (works for any program), then the community map for Steam games. Never bypassed — only reported honestly.
        // Scan the game's own root: for a Steam game that is steamapps/common/<Game> (never the whole library), otherwise the exe's folder.
        let gameRoot: String = { if let r = exe.range(of: "/steamapps/common/") { let rest = exe[r.upperBound...]; if let s = rest.firstIndex(of: "/") { return String(exe[..<s]) } }; return dir }()
        var acNames = antiCheatSignatures(in: gameRoot)
        if let g = steamGames[exe] {
            let c = communityFixes(g.id)
            if !c.tier.isEmpty { parts.append("ProtonDB \(c.tier)") }
            acNames += c.anticheat.filter { !acNames.contains($0) }
            // Highball (CC0) curated backend per title wins over import-based guessing, when that driver is installed and allowed.
            let map = ["d3dmetal": autoDriverSetDX12, "dxmt": autoDriverSet, "dxvk": ["dxvk", "cnc_ddraw"], "dxvk-moltenvk": ["dxvk", "cnc_ddraw"], "wined3d": ["cnc_ddraw"]]
            if let set = map[c.renderer], set.allSatisfy({ fm.fileExists(atPath: "\(driversDir)/\($0)/wine") }), !(c.renderer == "d3dmetal" && !d3dmetalOK) {
                parts.append("Highball \(c.hbStatus): \(c.renderer)")
                // Only switch when the current set cannot serve the recommendation: d3dmetal already covers a "dxmt" (D3D11) title, so no
                // restart ping-pong between a DX12 game and a DX11 game in the same bottle.
                let cur = Set(driverList(launchEnvRaw(), bottle: selected))
                let served = cur.isSuperset(of: set) || (c.renderer == "dxmt" && cur.contains("d3dmetal"))
                if !served { drivers = set; n.drivers = set }
            } else if !c.renderer.isEmpty { parts.append("Highball \(c.hbStatus): \(c.renderer)" + (c.renderer == "d3dmetal" && !d3dmetalOK ? " (license not accepted)" : "")) }
            verbs += c.verbs.filter { !verbs.contains($0) }; n.overrides = c.overrides; n.env = c.env; n.args = c.args
            if !(c.verbs.isEmpty && c.overrides.isEmpty && c.env.isEmpty && c.args.isEmpty) { parts.append("applying community fixes" + (c.overrides.isEmpty ? "" : " (overrides: " + c.overrides.map { "\($0.0)=\($0.1)" }.joined(separator: ", ") + ")") + (c.args.isEmpty ? "" : " args " + c.args.joined(separator: " "))) }
            if !c.launchArgs.isEmpty { n.args += c.launchArgs.split(separator: " ").map(String.init) }
        }
        if let v = antiCheatVerdict(acNames) { n.anticheat = v; parts.append(v.1) }
        // §8.2 Untrusted executable: not installed by a store client. Warn, never block.
        if steamGames[exe] == nil, !exe.hasSuffix("/Steam/steam.exe"), !exe.contains("/drive_c/windows/"), !exe.contains("/Program Files/Windows NT/") {
            parts.append("not installed through a store — run only if you trust where it came from")
        }
        // AVX (§7.2/§4.3): known from the cached disassembly count; Rosetta advertises AVX only to programs that have AVX code.
        if let c = avxCount(exe), c > 500 { n.env["ROSETTA_ADVERTISE_AVX"] = "1"; parts.append("uses AVX (Rosetta AVX on)") }
        else if avxCount(exe) == nil, era.kind == "pe" { parts.append("AVX scan pending") }
        // Per-program options (right-click → Options…): ARGS, DRIVERS, any other KEY=VALUE becomes environment. They win over detection.
        let o = options(exe)
        if let a = o["ARGS"], !a.isEmpty { n.args += a.split(separator: " ").map(String.init) }
        if let d = o["DRIVERS"], !d.isEmpty { drivers = d.split(separator: ",").map(String.init); n.drivers = drivers }
        for (k, v) in o where !["ARGS", "DRIVERS", "FOCUS_SHORTCUT", "PAUSE_IN_BACKGROUND", "MOUSE_CAPTURE"].contains(k) { n.env[k] = v }
        // §7.10 Locale: LANG=ja_JP.UTF-8 (etc.) reaches Wine as-is; CJK locales also get the matching fonts so old games don't show boxes.
        if let l = o["LANG"], ["ja", "zh", "ko"].contains(where: { l.hasPrefix($0) }), !verbs.contains("cjkfonts") { verbs.append("cjkfonts"); parts.append("locale \(l) + CJK fonts") }
        if !o.isEmpty { parts.append("custom options: " + o.keys.sorted().joined(separator: " ")) }
        let unknown = missing.filter { depVerbs[$0] == nil }
        if !verbs.isEmpty { parts.append(winetricks == nil ? "needs \(verbs.joined(separator: " ")) — brew install winetricks to fetch automatically" : "fetching \(verbs.joined(separator: " ")) via winetricks") }
        if !unknown.isEmpty { parts.append("missing DLLs: " + unknown.joined(separator: ", ")) }
        n.note = imps.isEmpty && parts.isEmpty ? "" : "Launch check \(name): " + (imps.isEmpty ? "" : "\(imps.count) DLLs") + (parts.isEmpty ? ", all available" : (imps.isEmpty ? "" : " — ") + parts.joined(separator: "; ")) + "\n"
        n.verbs = winetricks == nil ? [] : verbs
        // Tile light: red = will not start as is, yellow = starts after automatic work or with a caveat, green = ready.
        let red = !unknown.isEmpty || (!verbs.isEmpty && winetricks == nil) || n.anticheat?.0 == .red || parts.contains { $0.contains("not installed") || $0.contains("brew install") || $0.contains("accept Apple's license") }
        let yellow = !verbs.isEmpty || drivers != nil || desktop || n.anticheat != nil || parts.contains { $0.contains("ProtonDB silver") || $0.contains("ProtonDB bronze") || $0.contains("ProtonDB borked") || $0.contains("ProtonDB pending") }
        n.status = red ? .red : yellow ? .yellow : .green
        return n
    }

    // Pre-verification: run the launch check for every tile after a scan, so problems show before anyone clicks Play.
    func verifyAll() {
        let bottle = selected
        Task { @MainActor in
            for p in programs where bottle == selected {
                noteExeChange(p); readiness[p] = launchNeeds(p); await Task.yield()
            }
            scanAVX(programs)   // background disassembly for exes not scanned yet; tiles update as results arrive
            // Bottle-wide DirectX 12 need: flip the marker, re-check the tiles against the new set, and restart Steam so games started from inside it match.
            let needs12 = programs.contains { readiness[$0]?.dx12 == true }, marker = dx12Marker(selected)
            if needs12 != FileManager.default.fileExists(atPath: marker), bottle == selected {
                if needs12 { FileManager.default.createFile(atPath: marker, contents: nil) } else { try? FileManager.default.removeItem(atPath: marker) }
                log += needs12 ? "A Direct3D 12 game is installed: this bottle now runs d3dmetal for Direct3D 10/11/12.\n" : "No Direct3D 12 game left: back to dxmt for Direct3D 10/11.\n"
                loadSettings(); for p in programs { readiness[p] = launchNeeds(p) }
                if let s = programs.first(where: { $0.hasSuffix("/Steam/steam.exe") }), steamRunning() {
                    log += "Restarting Steam with the new driver set…\n"
                    await stopSteam(); launch(s)
                }
            }
            // A missing driver folder we can fetch ourselves (dxmt/dxvk): fetch it instead of leaving a red light.
            if driverStatus.1.hasPrefix("missing:"), Model.driverSources.contains(where: { driverStatus.1.contains($0.0) }), !busy { updateDrivers() }
        }
    }

    // Per-program options live in <bottle>/options/<exe>.env as KEY=VALUE lines; the raw text is what the Options… sheet edits.
    func optionsPath(_ exe: String) -> String { "\(bottlesDir)/\(selected)/options/\((exe as NSString).lastPathComponent).env" }
    func options(_ exe: String) -> [String: String] {
        var o: [String: String] = [:]
        for l in ((try? String(contentsOfFile: optionsPath(exe), encoding: .utf8)) ?? "").components(separatedBy: "\n") where !l.hasPrefix("#") {
            let kv = l.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if kv.count == 2 { o[kv[0]] = kv[1] }
        }
        return o
    }
    func saveOptions(_ exe: String, _ text: String) {
        try? FileManager.default.createDirectory(atPath: (optionsPath(exe) as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try? text.write(toFile: optionsPath(exe), atomically: true, encoding: .utf8)
        readiness[exe] = launchNeeds(exe)
    }
    static let optionsTemplate = """
    # One setting per line. Lines starting with # are ignored.
    # ARGS=-dx11 -windowed          extra command-line arguments
    # DRIVERS=dxmt,d9vk             driver set for this program (overrides Auto)
    # LANG=ja_JP.UTF-8              run in another locale; ja/zh/ko also install matching fonts
    # MOUSE_CAPTURE=1               keep the cursor inside the game window (camera-heavy games)
    # FOCUS_SHORTCUT=Gaming         run this macOS Shortcut when the game starts and when it exits
    # PAUSE_IN_BACKGROUND=1         suspend the game while another app is in front (single-player only)
    # ROSETTA_ADVERTISE_AVX=0       force AVX off/on for this program (auto-detected otherwise)
    # WINEDLLOVERRIDES=xaudio2_7=n  any other KEY=VALUE becomes an environment variable

    """

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

    // Community knowledge per Steam AppID, cached 7 days in <bottle>/fixes: ProtonDB tier (expectation), umu-protonfixes (known fixes;
    // calls that translate to plain Wine: protontricks, winedll_override, set_environment, append_argument) and Highball (CC0: curated
    // renderer per title, anti-cheat map, launch args). Highball's status values: verified-local, reported-upstream, community, blocked-anticheat.
    func communityFixes(_ appid: String) -> (tier: String, verbs: [String], overrides: [(String, String)], env: [String: String], args: [String], renderer: String, hbStatus: String, anticheat: [String], launchArgs: String) {
        let dir = "\(bottlesDir)/\(selected)/fixes", fm = FileManager.default
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        func cached(_ name: String, _ url: String) -> String {
            let p = "\(dir)/\(name)"
            if let m = (try? fm.attributesOfItem(atPath: p))?[.modificationDate] as? Date, Date().timeIntervalSince(m) < 7 * 86400 { return (try? String(contentsOfFile: p, encoding: .utf8)) ?? "" }
            _ = sh("curl -s -m 6 -o '\(p)' -w '%{http_code}' '\(url)' | grep -q '^200$' || : > '\(p)'")   // 404 = no fix needed; empty file remembers that
            return (try? String(contentsOfFile: p, encoding: .utf8)) ?? ""
        }
        let db = cached("\(appid).json", "https://www.protondb.com/api/v1/reports/summaries/\(appid).json")
        let tier = db.components(separatedBy: "\"tier\": \"").dropFirst().first?.components(separatedBy: "\"").first ?? ""
        let total = db.components(separatedBy: "\"total\": ").dropFirst().first?.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let fix = cached("\(appid).py", "https://raw.githubusercontent.com/Open-Wine-Components/umu-protonfixes/master/gamefixes-steam/\(appid).py")
        func calls(_ fn: String) -> [[String]] {   // util.fn('a', 'b') -> ["a", "b"]
            let re = try! NSRegularExpression(pattern: "util\\.\(fn)\\(([^)]*)\\)")
            return re.matches(in: fix, range: NSRange(fix.startIndex..., in: fix)).map { m in
                String(fix[Range(m.range(at: 1), in: fix)!]).split(separator: ",").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " '\"")) } }
        }
        let modes = ["n": "native", "b": "builtin", "n,b": "native,builtin", "b,n": "builtin,native", "": ""]
        let overrides = calls("winedll_override").filter { $0.count >= 2 }.compactMap { c in modes[c.dropFirst().joined(separator: ",")].map { (c[0], $0) } }
        var env: [String: String] = [:]
        for c in calls("set_environment") where c.count == 2 && !c[0].hasPrefix("PROTON_") && !c[0].hasPrefix("DXVK_") { env[c[0]] = c[1] }
        // Highball: gethighball.com/data/steam/<appid>.json (404 = unknown title, cached as empty)
        let hb = cached("\(appid).highball.json", "https://gethighball.com/data/steam/\(appid).json")
        func field(_ k: String, in t: String) -> String { t.components(separatedBy: "\"\(k)\": \"").dropFirst().first?.components(separatedBy: "\"").first ?? "" }
        let game = hb.components(separatedBy: "\"game\": {").dropFirst().first ?? ""
        let renderer = field("renderer", in: game).lowercased(), hbStatus = field("status", in: game), launchArgs = field("launchArgs", in: game)
        var ac: [String] = []
        if let a = game.components(separatedBy: "\"anticheat\": {").dropFirst().first?.components(separatedBy: "}").first, let list = a.components(separatedBy: "\"anticheats\": [").dropFirst().first?.components(separatedBy: "]").first {
            ac = list.components(separatedBy: "\"").enumerated().filter { $0.offset % 2 == 1 }.map { $0.element }
        }
        if hbStatus == "blocked-anticheat", ac.isEmpty { ac = ["kernel anti-cheat (Highball blocklist)"] }
        return (tier.isEmpty ? "" : "\(tier) (\(total) reports)", calls("protontricks").compactMap { $0.first }, overrides, env, calls("append_argument").compactMap { $0.first }, renderer, hbStatus, ac, launchArgs)
    }

    // D3DMetal: Apple's proprietary toolkit. Never auto-fetched from anyone but Apple's own download (the user picks the folder), gated on
    // Apple's license, removable. Files are copied under Application Support, never into the app bundle, never modified.
    func acceptD3DMetal() {
        let h = licenseHash(); guard d3dmetalInstalled(), !h.isEmpty else { log += "D3DMetal: not fully installed or Apple's License file missing; nothing accepted.\n"; return }
        let f = ISO8601DateFormatter(); try? "{\"accepted\":\"\(f.string(from: Date()))\",\"sha256\":\"\(h)\"}".write(toFile: d3dmetalAcceptFile, atomically: true, encoding: .utf8)
        d3dmetalOK = checkD3DMetalAccepted(); log += d3dmetalOK ? "D3DMetal: Apple's license accepted; Direct3D 12 games can use it now.\n" : "D3DMetal: could not record acceptance.\n"
        loadSettings(); verifyAll()
    }
    func removeD3DMetal() {
        try? FileManager.default.removeItem(atPath: driversDir + "/d3dmetal"); try? FileManager.default.removeItem(atPath: d3dmetalAcceptFile)
        d3dmetalOK = false; log += "D3DMetal removed and license acceptance withdrawn.\n"; loadSettings(); verifyAll()
    }
    func installD3DMetal(from picked: String) {
        // Accepts Apple's GPTK .dmg (mounted read-only here, detached afterwards), a mounted volume, or an extracted folder.
        var root = picked, mount = ""
        if picked.lowercased().hasSuffix(".dmg") {
            mount = NSTemporaryDirectory() + "cosmo-gptk-\(ProcessInfo.processInfo.processIdentifier)"
            let r = sh("mkdir -p '\(mount)' && hdiutil attach -nobrowse -readonly -noverify -mountpoint '\(mount)' '\(picked)' 2>&1 | tail -1")
            guard FileManager.default.fileExists(atPath: mount), !r.contains("failed") else { log += "D3DMetal: could not mount \(picked): \(r)\n"; return }
            root = mount
        }
        defer { if !mount.isEmpty { _ = sh("hdiutil detach '\(mount)' -quiet; rmdir '\(mount)' 2>/dev/null") } }
        // Find external/D3DMetal.framework and the sibling wine/ folder; Apple's License.pdf sits at the image root, License.rtf in the redist folder.
        guard let en = FileManager.default.enumerator(atPath: root) else { return }
        var ext = "", lic: [String] = []
        for case let p as String in en {
            if en.level > 6 { en.skipDescendants(); continue }
            if p.hasSuffix("external/D3DMetal.framework") { ext = "\(root)/\((p as NSString).deletingLastPathComponent)" }
            if ["License.pdf", "License.rtf", "Read Me.rtf", "Acknowledgements.rtf"].contains((p as NSString).lastPathComponent) { lic.append("\(root)/\(p)") }
        }
        guard !ext.isEmpty else { log += "D3DMetal: no external/D3DMetal.framework found under \(picked)\n"; return }
        guard lic.contains(where: { $0.hasSuffix("License.pdf") || $0.hasSuffix("License.rtf") }) else { log += "D3DMetal: Apple's License file not found in this download; refusing to install without it.\n"; return }
        let lib = (ext as NSString).deletingLastPathComponent, dst = driversDir + "/d3dmetal"
        _ = sh("rm -rf '\(dst)'; mkdir -p '\(dst)' && cp -R '\(ext)' '\(dst)/external' && cp -R '\(lib)/wine' '\(dst)/wine'")   // copied as-is, never modified
        for f in lic { _ = sh("cp '\(f)' '\(dst)/' 2>/dev/null") }
        d3dmetalOK = false; try? FileManager.default.removeItem(atPath: d3dmetalAcceptFile)
        log += d3dmetalInstalled() ? "D3DMetal installed from \(picked) into \(dst). Read and accept Apple's license to enable it.\n" : "D3DMetal: copy incomplete (need lib/external, lib/wine and the License file); nothing enabled.\n"
        updateStatus()
    }
}

// Display name = the program folder under Program Files, or the Steam library name for steamapps games.
var steamGames: [String: (id: String, name: String)] = [:]   // exe path -> appid/name from appmanifest_*.acf
func appName(_ p: String) -> String { steamGames[p]?.name ?? ((p as NSString).deletingLastPathComponent as NSString).lastPathComponent }
// Steam games must start through Steam (DRM); everything else runs directly.
extension Model {
    func launchCmd(_ exe: String) -> (String, [String]) {
        if let g = steamGames[exe], let r = exe.range(of: "/steamapps/") {
            let steam = String(exe[..<r.lowerBound]) + "/steam.exe"
            return (winPath(steam), extraArgs(steam) + ["-applaunch", g.id])
        }
        return (winPath(exe), extraArgs(exe))
    }

    // Troubleshooting: every check is something that actually broke while bringing Steam up on this engine.
    func sh(_ cmd: String) -> String { shell(cmd) }
    func regSection(_ file: String, _ key: String) -> String {
        let reg = (try? String(contentsOfFile: "\(bottlesDir)/\(selected)/\(file)", encoding: .utf8)) ?? ""
        return reg.components(separatedBy: "[\(key.replacingOccurrences(of: "\\", with: "\\\\"))]").dropFirst().first?.components(separatedBy: "\n[").first ?? ""
    }
    func troubleshoot() {
        var out = "── Troubleshooting ──\n"
        func check(_ ok: Bool, _ what: String, _ fix: String = "") { out += (ok ? "✓ " : "✗ ") + what + (ok || fix.isEmpty ? "" : "  →  \(fix)") + "\n" }
        let engine = ((wineBin as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent   // wswine.bundle
        let v = sh("'\(wineBin)' --version 2>&1")
        check(v.hasPrefix("wine-"), "Wine engine runs (\(v.prefix(40)))", "engine folder damaged; re-copy the Sikarugir engine")
        let icd = launchEnv(selected)["VK_DRIVER_FILES"] ?? ""
        let lib = sh("sed -n 's/.*\"library_path\" *: *\"\\([^\"]*\\)\".*/\\1/p' '\(icd)'")
        check(FileManager.default.fileExists(atPath: lib.hasPrefix("/") ? lib : (icd as NSString).deletingLastPathComponent + "/" + lib), "MoltenVK ICD present (Vulkan for DXVK)", "MoltenVK_icd.json must point at libMVK.dylib")
        let unix = engine + "/lib/wine/x86_64-unix"
        let sdl = sh("ls '\(unix)' | grep -c '^libSDL3'")
        check(FileManager.default.fileExists(atPath: unix + "/libSDL2-2.0.0.dylib") && sdl != "0", "SDL2 + SDL3 beside the engine (controllers)", "copy libSDL3*.dylib next to libSDL2-2.0.0.dylib")
        let gstMissing = sh("cd '\(unix)' && otool -L winegstreamer.so winedmo.so | awk '/@rpath/{print $1}' | sed 's|@rpath/||' | while read x; do [ -e \"$x\" ] || echo \"$x\"; done | wc -l | tr -d ' '")
        check(gstMissing == "0" && FileManager.default.fileExists(atPath: support + "/engines/gstreamer/GStreamer.framework/Versions/1.0/lib/gstreamer-1.0"), "Video/audio codecs (GStreamer) reachable — cutscenes and store videos", "Update… re-links GStreamer from the Sikarugir template")
        for d in driverList(launchEnvRaw(), bottle: selected) {
            check(FileManager.default.fileExists(atPath: "\(driversDir)/\(d)/wine"), "Driver \(d) installed", "drop the renderer folder into engines/renderer")
        }
        if !selected.isEmpty {
            check(regSection("system.reg", "System\\CurrentControlSet\\Services\\winebus").contains("\"DisableHidraw\"=dword:00000001"), "DualSense via SDL (winebus DisableHidraw=1)", "Repair")
            let dpi = regSection("user.reg", "Control Panel\\Desktop")
            check(!dpi.contains("\"LogPixels\"") || dpi.contains("\"LogPixels\"=dword:00000060"), "Bottle DPI is 96 (window sizes)", "Repair")
            let steam = FileManager.default.fileExists(atPath: "\(bottlesDir)/\(selected)/drive_c/Program Files (x86)/Steam/steam.exe")
            if steam {
                check(regSection("user.reg", "Software\\Wine\\AppDefaults\\steam.exe\\DllOverrides").contains("\"xinput1_4\"=\"\""), "Steam Input can't grab the controller (steam.exe xinput disabled)", "Repair")
                check(regSection("user.reg", "Software\\Wine\\AppDefaults\\steamwebhelper.exe\\DllOverrides").contains("\"dxgi\"=\"builtin\""), "steamwebhelper uses builtin dxgi (no crash)", "Repair")
            }
        }
        let servers = sh("ps -axo command | grep -c '[w]ineserver'")
        check(servers == "0" || servers == "1", "One wineserver (\(servers) running)", "two Wine builds share a prefix, or orphans; Repair kills all Wine processes")
        let foreign = sh("ps -axo comm= | grep -v -F '\(engine)' | grep -c 'wine.*-preloader$\\|/wineserver$\\|/wine64$\\|/wine$'")   // binary paths only, not shell command lines
        check(foreign == "0", "No other Wine build running", "quit CrossOver/Whisky/other Wine first (version mismatch)")
        let pad = sh("ioreg -r -c IOHIDDevice -l 2>/dev/null | grep -o '\"Product\" = \"[^\"]*\"' | grep -c -i 'DualSense\\|Wireless Controller\\|Xbox\\|Gamepad'")   // only devices that are on and connected show up here
        check(pad != "0", "Game controller connected and turned on", "press PS/Xbox button or pair it in Bluetooth settings; Wine only sees it once macOS does")
        let free = sh("df -g \"$HOME\" | awk 'NR==2{print $4}'")
        check((Int(free) ?? 0) > 10, "Disk space (\(free) GB free)", "free up space; Steam downloads fail silently when full")
        let log = (try? String(contentsOfFile: logPath, encoding: .utf8)) ?? ""
        for (s, hint) in Model.logSigns where log.contains(s) { out += "! log contains \"\(s)\": \(hint)\n" }
        out += "──\n"
        logToFile(out); self.log += out
    }
    // Known failure signatures in the log and what they mean. Used by Troubleshoot and by crash triage.
    static let logSigns = ["version mismatch": "two Wine builds touched this bottle → Repair, then relaunch",
                           "dx11 device creation fail": "no D3D11 driver reached the game → check Drivers (dxmt on)",
                           "DirectX 12 is not supported": "game needs d3dmetal; start it from Cosmopolitan so Steam is restarted with it",
                           "Failed to dlopen D3DMetal": "D3DMetal framework path wrong or files missing → Update… re-syncs d3dmetal",
                           "Failed loading SDL3": "SDL3 missing beside the engine",
                           "detached already": "Wine 11.x Mac driver bug; this engine must stay 10.0",
                           "Library not loaded": "a dylib the engine needs is missing (see the line above it in the log)",
                           "c000001d": "Illegal instruction → the program needs AVX; Rosetta AVX is switched on for it",
                           "Illegal instruction": "Illegal instruction → the program needs AVX; Rosetta AVX is switched on for it"]
    // Crash triage: a program that dies within a minute gets the recent log matched against the signatures and the known fix applied.
    func triage(_ exe: String, _ code: Int32) {
        let name = (exe as NSString).lastPathComponent, fm = FileManager.default
        let tail = String(((try? String(contentsOfFile: logPath, encoding: .utf8)) ?? "").suffix(20000))
        let hits = Model.logSigns.filter { tail.contains($0.key) }
        var out = "⚠ \(name) exited almost immediately (code \(code)).\n"
        for (s, hint) in hits { out += "  • \"\(s)\": \(hint)\n" }
        if hits["version mismatch"] != nil { out += "  → running Repair\n"; log += out; repair(); return }
        if hits["c000001d"] != nil || hits["Illegal instruction"] != nil {   // §4.3: enable AVX for this program after an illegal-instruction crash
            var t = (try? String(contentsOfFile: optionsPath(exe), encoding: .utf8)) ?? Model.optionsTemplate
            if !t.contains("ROSETTA_ADVERTISE_AVX") { t += "\nROSETTA_ADVERTISE_AVX=1\n"; saveOptions(exe, t) }
            out += "  → ROSETTA_ADVERTISE_AVX=1 saved in this program's Options. Try again.\n"; log += out; return
        }
        // A driver updated in the last 7 days is the prime suspect: roll it back and keep the new one aside.
        for d in (try? fm.contentsOfDirectory(atPath: driversDir)) ?? [] where d.hasSuffix(".old") {
            let name = String(d.dropLast(4)), cur = "\(driversDir)/\(name)"
            if let m = (try? fm.attributesOfItem(atPath: cur))?[.modificationDate] as? Date, Date().timeIntervalSince(m) < 7 * 86400 {
                _ = sh("rm -rf '\(cur).bad'; mv '\(cur)' '\(cur).bad' && mv '\(driversDir)/\(d)' '\(cur)'")
                out += "  → driver \(name) was updated recently; rolled back to the previous version (new one kept as \(name).bad). Try again.\n"
                log += out; updateStatus(); return
            }
        }
        log += out
        if hits.isEmpty { log += "  → no known signature; running Troubleshoot\n"; troubleshoot() }
        explainCrash(name, tail)
    }

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

    // Find apps: every folder under C: that holds a real exe, not just Program Files. Results persist in <bottle>/cosmopolitan.apps.
    func findApps() {
        guard !selected.isEmpty else { return }
        let c = "\(bottlesDir)/\(selected)/drive_c", fm = FileManager.default
        let skipDirs = ["windows", "common files", "programdata", "temp", "steamapps", "redist", "_commonredist", "directx", "vcredist", "microsoft", "internet explorer", "windows nt", "windows media player", "windows defender", "wine", "windowsapps", "bin", "cache"]
        var best: [String: (String, Int)] = [:]   // folder -> (largest exe, size)
        guard let en = fm.enumerator(at: URL(fileURLWithPath: c), includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]) else { return }
        for case let u as URL in en {
            let rv = try? u.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey, .isSymbolicLinkKey])
            if rv?.isSymbolicLink == true { en.skipDescendants(); continue }   // users/*/Desktop etc. point at the Mac home
            if rv?.isDirectory == true {
                let n = u.lastPathComponent.lowercased()
                if en.level > 5 || skipDirs.contains(where: { n.hasPrefix($0) }) { en.skipDescendants() }   // prefix: "Microsoft GameInput", "DirectX Redist"…
                continue
            }
            let n = u.lastPathComponent.lowercased()
            guard n.hasSuffix(".exe"), !skipExes.contains(where: { n.contains($0) }) else { continue }
            let dir = u.deletingLastPathComponent().path, size = rv?.fileSize ?? 0
            if size > (best[dir]?.1 ?? 0) { best[dir] = (u.path, size) }
        }
        let new = best.values.map { $0.0 }.filter { !programs.contains($0) }.sorted()
        let listPath = "\(bottlesDir)/\(selected)/cosmopolitan.apps"
        let old = ((try? String(contentsOfFile: listPath, encoding: .utf8)) ?? "").components(separatedBy: "\n").filter { !$0.isEmpty }
        try? Set(old + new).sorted().joined(separator: "\n").write(toFile: listPath, atomically: true, encoding: .utf8)
        let out = "Find apps: \(new.count) new program(s)\n" + new.map { "  C:" + $0.dropFirst(c.count).replacingOccurrences(of: "/", with: "\\") + "\n" }.joined()
        logToFile(out); log += out
        scan()
    }

    // Driver updates from upstream GitHub releases. D3DMetal is Apple's and only ships with the Sikarugir template (brew upgrade), so it's not here.
    // ponytail: "installed" = the version file mentions the release tag; the Sikarugir builds carry extra commits on top of a tag.
    nonisolated static let driverSources = [("dxmt", "3Shain/dxmt", "-builtin.tar.gz"), ("dxvk", "Gcenx/DXVK-macOS", "-builtin.tar.gz")]
    nonisolated static func latestDriverTags() -> [(name: String, tag: String, url: String, installed: String)] {
        Model.driverSources.compactMap { name, repo, suffix in
            let j = shell("curl -s -m 8 https://api.github.com/repos/\(repo)/releases/latest")
            guard let tag = j.components(separatedBy: "\"tag_name\": \"").dropFirst().first?.components(separatedBy: "\"").first,
                  let url = j.components(separatedBy: "\"browser_download_url\": \"").dropFirst().map({ $0.components(separatedBy: "\"")[0] }).first(where: { $0.hasSuffix(suffix) }) else { return nil }
            let installed = ((try? String(contentsOfFile: "\(driversDir)/\(name)/version", encoding: .utf8)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return (name, tag, url, installed)
        }
    }
    nonisolated static func isCurrent(_ d: (name: String, tag: String, url: String, installed: String)) -> Bool {
        let num = d.tag.components(separatedBy: CharacterSet(charactersIn: "-_")).first ?? d.tag   // "v1.10.3-20230507-repack" -> "v1.10.3"
        return d.installed.contains(num)
    }
    // All the work, off the main thread. Returns the log text. Previous versions are kept as <name>.old for a manual swap back.
    nonisolated static func performUpdate() -> String {
        var out = ""
        let list = latestDriverTags()
        if list.isEmpty { out += "Driver update: could not reach GitHub.\n" }
        for d in list {
            if isCurrent(d) { out += "✓ \(d.name) is current (\(d.installed), upstream \(d.tag))\n"; continue }
            out += "↓ \(d.name) \(d.tag) — downloading…\n"
            let tmp = NSTemporaryDirectory() + "cosmo-\(d.name)-\(d.tag)"; _ = shell("rm -rf '\(tmp)'; mkdir -p '\(tmp)'")
            let found = shell("cd '\(tmp)' && curl -sL -m 300 -o pkg.tar.gz '\(d.url)' && tar xzf pkg.tar.gz && find . -type d -name x86_64-windows | head -1")
            guard !found.isEmpty else { out += "✗ \(d.name): download or unpack failed\n"; continue }
            let src = (tmp + "/" + found) as NSString   // …/x86_64-windows -> its parent is the new 'wine' dir
            let dst = "\(driversDir)/\(d.name)"
            _ = shell("rm -rf '\(dst).old'; mv '\(dst)' '\(dst).old' 2>/dev/null; mkdir -p '\(dst)' && cp -R '\(src.deletingLastPathComponent)/.' '\(dst)/wine/' && printf '%s\\n' '\(d.tag)' > '\(dst)/version'; rm -rf '\(tmp)'")
            if FileManager.default.fileExists(atPath: dst + "/wine/x86_64-windows") { out += "✓ \(d.name) updated to \(d.tag) (previous kept as \(d.name).old)\n" }
            else { _ = shell("rm -rf '\(dst)'; mv '\(dst).old' '\(dst)'"); out += "✗ \(d.name): install failed, previous version restored\n" }
        }
        _ = shell("find '\(driversDir)' -maxdepth 1 -name '*.old' -mtime +7 -exec rm -rf {} +")   // rollbacks older than a week are no longer useful
        // Newest Sikarugir template (carries D3DMetal and the engine's dylibs): fetch it ourselves if the Creator app hasn't.
        let tpl = NSHomeDirectory() + "/Library/Application Support/Sikarugir/Template"
        let newestTpl = shell("curl -s -m 8 https://sikarugir-app.github.io/Template/NewestVersion.txt").trimmingCharacters(in: .whitespacesAndNewlines)
        if newestTpl.hasPrefix("Template-"), !FileManager.default.fileExists(atPath: "\(tpl)/\(newestTpl).app") {
            out += "↓ Sikarugir \(newestTpl) — downloading…\n"
            let r = shell("mkdir -p '\(tpl)' && cd '\(tpl)' && curl -sL -m 600 -o '\(newestTpl).tar.xz' 'https://github.com/Sikarugir-App/Template/releases/download/v1.0/\(newestTpl).tar.xz' && tar xf '\(newestTpl).tar.xz' && rm -f '\(newestTpl).tar.xz' && ls -d \(newestTpl)*.app | head -1")
            out += r.hasSuffix(".app") ? "✓ \(newestTpl) installed\n" : "✗ \(newestTpl): download failed\n"
        }
        // Newest Sikarugir Wine engine: downloaded and prepared side by side, never switched automatically
        // (Wine 11.x still renders Steam black on macOS 27; switching is a tested, manual step).
        let newestEng = shell("curl -s -m 8 https://sikarugir-app.github.io/Engines/EngineList.txt | grep '^WS12WineSikarugir' | head -1")
        if !newestEng.isEmpty, !FileManager.default.fileExists(atPath: "\(support)/engines/\(newestEng)") {
            out += "↓ engine \(newestEng) — fetching…\n"
            let local = NSHomeDirectory() + "/Library/Application Support/Sikarugir/Engines/\(newestEng).tar.xz"
            let dst = "\(support)/engines/\(newestEng)"
            let get = FileManager.default.fileExists(atPath: local) ? "cp '\(local)' eng.tar.xz" : "curl -sL -m 900 -o eng.tar.xz 'https://github.com/Sikarugir-App/Engines/releases/download/v1.0/\(newestEng).tar.xz'"
            _ = shell("mkdir -p '\(dst)' && cd '\(dst)' && \(get) && tar xf eng.tar.xz && rm -f eng.tar.xz")
            if FileManager.default.fileExists(atPath: dst + "/wswine.bundle/bin/wine") { out += prepareEngine(dst + "/wswine.bundle") + "✓ engine \(newestEng) ready at \(dst) (not active; current engine unchanged)\n" }
            else { _ = shell("rm -rf '\(dst)'"); out += "✗ engine \(newestEng): download failed\n" }
        }
        // D3DMetal is Apple's and is never fetched or synced automatically (license rule): the user installs it from Apple's own download via Drivers › D3DMetal….
        out += FileManager.default.fileExists(atPath: driversDir + "/d3dmetal/wine") ? (d3dmetalOK ? "✓ d3dmetal present, Apple's license accepted\n" : "• d3dmetal present, Apple's license not accepted yet (Drivers › D3DMetal…)\n") : "• d3dmetal not installed (optional, needed for Direct3D 12)\n"
        FileManager.default.createFile(atPath: support + "/.driver-check", contents: nil)
        return out
    }
    // Shell snippet: clone the template's GStreamer.framework once, then symlink the media modules' missing @rpath libs to it.
    // Symlinks (not copies) so plugins and winegstreamer share one loaded copy of each library.
    nonisolated static func linkGStreamer(unix: String, templateFrameworks fw: String) -> String {
        let g = support + "/engines/gstreamer/GStreamer.framework", gl = g + "/Versions/1.0/lib"
        return "mkdir -p '\(support)/engines/gstreamer'; [ -d '\(g)' ] || cp -cR '\(fw)/GStreamer.framework' '\(g)'; cd '\(unix)' && for f in winegstreamer.so winedmo.so; do otool -L $f | awk '/@rpath/{print $1}' | sed 's|@rpath/||' | while read x; do [ -e \"$x\" ] || { [ -e '\(gl)/'\"$x\" ] && ln -s '\(gl)/'\"$x\" \"$x\"; }; done; done; true"
    }
    // Sikarugir engines aren't self-contained: give a freshly unpacked one the same fix-ups the working 10.0_8 engine has.
    nonisolated static func prepareEngine(_ e: String) -> String {
        let tpl = NSHomeDirectory() + "/Library/Application Support/Sikarugir/Template"
        guard let t = ((try? FileManager.default.contentsOfDirectory(atPath: tpl)) ?? []).filter({ $0.hasPrefix("Template-") }).sorted(by: { $0.compare($1, options: .numeric) == .orderedDescending }).first else { return "✗ no Sikarugir template on disk; engine left unprepared\n" }
        let fw = "\(tpl)/\(t)/Contents/Frameworks", unix = "\(e)/lib/wine/x86_64-unix"
        _ = shell("cp -cR '\(fw)'/*.dylib '\(unix)/' 2>/dev/null; cp -c '\(fw)/libinotify.0.dylib' '\(e)/bin/inotify.dylib'")
        _ = shell(linkGStreamer(unix: unix, templateFrameworks: fw))
        // wineserver has no header padding for add_rpath; a same-or-shorter -change is the only option, and DYLD_* never reaches it.
        _ = shell("install_name_tool -change @rpath/libinotify.0.dylib @executable_path/inotify.dylib '\(e)/bin/wineserver' 2>/dev/null; codesign --force -s - '\(e)/bin/wineserver' 2>/dev/null")
        let icd = "{\"file_format_version\":\"1.0.0\",\"ICD\":{\"library_path\":\"\(unix)/libMVK.dylib\",\"api_version\":\"1.4.0\",\"is_portability_driver\":false}}"
        try? icd.write(toFile: "\(e)/MoltenVK_icd.json", atomically: true, encoding: .utf8)
        FileManager.default.createFile(atPath: "\(e)/dxmt_extescape", contents: nil)
        let v = shell("'\(e)/bin/wine' --version 2>&1 | head -1")
        return v.hasPrefix("wine-") ? "  prepared (\(v), dylibs from \(t))\n" : "  prepared, but wine --version failed: \(v.prefix(80))\n"
    }
    // Weekly, in the background, no clicking: a newer release is installed as soon as it's found.
    func checkDriverUpdates() {
        let stamp = support + "/.driver-check"
        if let m = (try? FileManager.default.attributesOfItem(atPath: stamp))?[.modificationDate] as? Date, Date().timeIntervalSince(m) < 7 * 86400 { return }
        updateDrivers()
    }
    func updateDrivers() {
        guard !busy else { return }
        busy = true; driverUpdates = "checking upstream…"
        Task.detached {
            let out = Model.performUpdate()
            await MainActor.run { logToFile(out); self.log += out; self.busy = false; self.driverUpdates = ""; self.updateStatus() }
        }
    }

    // §7.4 APFS snapshots: a copy-on-write clone of the bottle (seconds, ~0 bytes) before anything that writes into it beyond a plain launch.
    // Hidden from the bottle list (.auto-…), pruned after 30 days; Snapshots… lists them and rolls back in seconds.
    @discardableResult func snapshot(_ reason: String) -> String? {
        guard !selected.isEmpty else { return nil }
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"
        let bak = "\(bottlesDir)/.auto-\(selected)-\(f.string(from: Date()))"
        _ = sh("cp -cR '\(bottlesDir)/\(selected)' '\(bak)' && printf '%s' '\(reason)' > '\(bak)/.snapshot-reason'")
        log += "Snapshot (\(reason)): \((bak as NSString).lastPathComponent)\n"; return bak
    }
    func snapshots() -> [(path: String, when: String, reason: String)] {
        ((try? FileManager.default.contentsOfDirectory(atPath: bottlesDir)) ?? []).filter { $0.hasPrefix(".auto-\(selected)-") }.sorted(by: >).map { n in
            let p = "\(bottlesDir)/\(n)", stamp = String(n.dropFirst(".auto-\(selected)-".count))
            return (p, stamp, (try? String(contentsOfFile: p + "/.snapshot-reason", encoding: .utf8)) ?? "backup")
        }
    }
    func rollback(to snap: String) {
        busy = true
        Task { @MainActor in
            if steamRunning() { await stopSteam() }
            _ = sh("pkill -9 -f '\\.exe'; env WINEPREFIX='\(bottlesDir)/\(selected)' perl -e 'alarm 10; exec @ARGV' -- '\((wineBin as NSString).deletingLastPathComponent)/wineserver' -w 2>/dev/null")
            let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"
            let aside = "\(bottlesDir)/.auto-\(selected)-\(f.string(from: Date()))"
            _ = sh("mv '\(bottlesDir)/\(selected)' '\(aside)' && printf 'state before rollback' > '\(aside)/.snapshot-reason' && cp -cR '\(snap)' '\(bottlesDir)/\(selected)' && rm -f '\(bottlesDir)/\(selected)/.snapshot-reason'")
            log += "Rolled back \(selected) to \((snap as NSString).lastPathComponent); the previous state is kept as a snapshot too.\n"
            busy = false; refresh()
        }
    }

    // §7.2 / §4.3 AVX: Rosetta hides AVX unless asked. Disassemble the exe once (llvm-objdump reads PE) and count ymm-register uses;
    // a real count means the game has AVX code paths, so ROSETTA_ADVERTISE_AVX=1 goes into its launch. Cached per exe; ~25 s for a 25 MB exe.
    func avxCache(_ exe: String) -> String { "\(bottlesDir)/\(selected)/options/.avx-\((exe as NSString).lastPathComponent)" }
    func avxCount(_ exe: String) -> Int? { Int(((try? String(contentsOfFile: avxCache(exe), encoding: .utf8)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) }
    func scanAVX(_ exes: [String]) {
        let todo = exes.filter { avxCount($0) == nil && exeEra($0).kind == "pe" }
        guard !todo.isEmpty else { return }
        let caches = Dictionary(uniqueKeysWithValues: todo.map { ($0, avxCache($0)) })
        Task.detached(priority: .background) {
            for exe in todo {
                let n = shell("xcrun llvm-objdump -d --no-show-raw-insn '\(exe)' 2>/dev/null | grep -c ymm")
                try? FileManager.default.createDirectory(atPath: (caches[exe]! as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
                try? n.write(toFile: caches[exe]!, atomically: true, encoding: .utf8)
                await MainActor.run { self.readiness[exe] = self.launchNeeds(exe) }
            }
        }
    }

    // §9.3 Import: bottles from Whisky, CrossOver and Sikarugir wrappers. Originals are never touched: the prefix is APFS-cloned in.
    func importableBottles() -> [(label: String, path: String)] {
        let h = NSHomeDirectory(), fm = FileManager.default
        var out: [(String, String)] = []
        for dir in ["\(h)/Library/Containers/com.isaacmarovitz.Whisky/Bottles", "\(h)/Library/Application Support/com.isaacmarovitz.Whisky/Bottles"] {
            for b in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] where fm.fileExists(atPath: "\(dir)/\(b)/drive_c") {
                let name = (try? String(contentsOfFile: "\(dir)/\(b)/Metadata.plist", encoding: .utf8))?.components(separatedBy: "<key>Name</key>").dropFirst().first?.components(separatedBy: "<string>").dropFirst().first?.components(separatedBy: "</string>").first ?? b
                out.append(("Whisky: \(name)", "\(dir)/\(b)")) }
        }
        let cx = "\(h)/Library/Application Support/CrossOver/Bottles"
        for b in (try? fm.contentsOfDirectory(atPath: cx)) ?? [] where fm.fileExists(atPath: "\(cx)/\(b)/drive_c") { out.append(("CrossOver: \(b)", "\(cx)/\(b)")) }
        for root in ["\(h)/Applications/Sikarugir", "/Applications/Sikarugir", "\(h)/Applications"] {
            for a in (try? fm.contentsOfDirectory(atPath: root)) ?? [] where a.hasSuffix(".app") && fm.fileExists(atPath: "\(root)/\(a)/Contents/SharedSupport/prefix/drive_c") { out.append(("Sikarugir: \((a as NSString).deletingPathExtension)", "\(root)/\(a)/Contents/SharedSupport/prefix")) }
        }
        return out
    }
    func importBottle(_ src: String, as name: String) {
        let safe = name.replacingOccurrences(of: "/", with: "-"), dst = "\(bottlesDir)/\(safe)"
        guard !FileManager.default.fileExists(atPath: dst) else { log += "Import: a bottle named \(safe) already exists.\n"; return }
        busy = true; log += "Importing \(src) → \(safe) (APFS clone, original untouched)…\n"
        Task.detached {
            let r = shell("cp -cR '\(src)' '\(dst)' 2>&1 | tail -1; rm -f '\(dst)/dosdevices/z:'")   // imported bottles start restricted too
            await MainActor.run { self.busy = false; self.log += r.isEmpty ? "Imported \(safe). Controller defaults apply on first Repair.\n" : "Import: \(r)\n"; self.refresh(); self.selected = safe; self.scan() }
        }
    }

    // ── P2 ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
    // §8.5 Time Machine + Spotlight: game binaries and the Windows folder are excluded (re-downloadable), saves under users/ stay backed up.
    func excludeFromBackups(_ bottle: String) {
        let root = "\(bottlesDir)/\(bottle)", mark = root + "/.backup-exclusions-set"
        guard !FileManager.default.fileExists(atPath: mark), FileManager.default.fileExists(atPath: root + "/drive_c") else { return }
        for d in ["drive_c/Program Files", "drive_c/Program Files (x86)", "drive_c/windows", "drive_c/ProgramData"] where FileManager.default.fileExists(atPath: "\(root)/\(d)") { _ = sh("tmutil addexclusion '\(root)/\(d)' 2>/dev/null") }
        FileManager.default.createFile(atPath: root + "/.metadata_never_index", contents: nil)   // Spotlight: never index a bottle
        FileManager.default.createFile(atPath: mark, contents: nil)
        log += "\(bottle): program folders excluded from Time Machine, bottle hidden from Spotlight; saves under users/ stay backed up.\n"
    }
    // §6.3 Power and thermal hints, logged at launch when they would change the experience.
    func powerHints() -> String {
        var out = ""
        if sh("pmset -g | grep -i lowpowermode | awk '{print $2}'") == "1" { out += "⚠ Low Power Mode is on: expect lower frame rates (System Settings › Battery).\n" }
        if let l = Int(sh("pmset -g therm 2>/dev/null | awk '/CPU_Speed_Limit/{print $3}'")), l < 100 { out += "⚠ Thermal pressure: CPU limited to \(l)% right now; let the Mac cool or lower settings.\n" }
        if sh("pmset -g batt | head -1").contains("Battery Power") { out += "On battery: 60 fps cap and lighter rendering are active automatically.\n" }
        return out
    }
    // §7.3 Game updates: remember each exe's size+mtime; a change means the game updated → re-check and say so (a snapshot taken by the next risky step protects the rest).
    func noteExeChange(_ exe: String) {
        let f = "\(bottlesDir)/\(selected)/options/.exe-\((exe as NSString).lastPathComponent)"
        guard let a = try? FileManager.default.attributesOfItem(atPath: exe) else { return }
        let sig = "\(a[.size] ?? 0)|\((a[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)"
        let old = (try? String(contentsOfFile: f, encoding: .utf8)) ?? ""
        try? FileManager.default.createDirectory(atPath: (f as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try? sig.write(toFile: f, atomically: true, encoding: .utf8)
        if !old.isEmpty, old != sig { log += "\(appName(exe)) was updated — launch check and AVX scan run again. If it broke, Snapshots… has the state before the last change.\n"; try? FileManager.default.removeItem(atPath: avxCache(exe)) }
    }
    // §8.12 Bug report: everything a maintainer needs, with the username and home folder stripped, on the clipboard.
    func copyBugReport() {
        let home = NSHomeDirectory(), user = NSUserName()
        var r = "## Cosmopolitan bug report\n"
        r += "- App: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "?") (\(Bundle.main.infoDictionary?["CFBundleVersion"] ?? "?"))\n"
        r += "- Mac: \(sh("sysctl -n machdep.cpu.brand_string")), \(ProcessInfo.processInfo.physicalMemory / 1_073_741_824) GB, macOS \(ProcessInfo.processInfo.operatingSystemVersionString)\n"
        r += "- Engine: \(sh("'\(wineBin)' --version 2>/dev/null")); drivers: \(driverList(launchEnvRaw(), bottle: selected).joined(separator: "+")); D3DMetal accepted: \(d3dmetalOK)\n"
        r += "- Bottle: \(selected); programs: \(programs.map { appName($0) + " [" + (readiness[$0]?.note.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") + "]" }.joined(separator: "; "))\n"
        r += "- Status: \(driverStatus.1) / \(padStatus.1)\n\n### Log (last 200 lines)\n```\n"
        r += log.components(separatedBy: "\n").suffix(200).joined(separator: "\n") + "\n```\n"
        r = r.replacingOccurrences(of: home, with: "~").replacingOccurrences(of: user, with: "<user>")
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(r, forType: .string)
        log += "Bug report copied to the clipboard (paths and username removed). Paste it into a GitHub issue.\n"
    }
    // §7.1 "Will it run?" — a verdict for THIS Mac from Highball + ProtonDB + the anti-cheat map, before buying.
    func willItRun(_ link: String) -> String {
        guard let id = link.components(separatedBy: "/app/").dropFirst().first?.components(separatedBy: "/").first ?? (Int(link) != nil ? link : nil) else { return "Paste a Steam store link (…/app/<id>/…) or an app id.\n" }
        let c = communityFixes(id)
        let hb = sh("curl -s -m 8 'https://gethighball.com/data/steam/\(id).json'")
        let title = hb.components(separatedBy: "\"title\": \"").dropFirst().first?.components(separatedBy: "\"").first ?? "App \(id)"
        var v = "Will it run? \(title) on \(sh("sysctl -n machdep.cpu.brand_string")), \(ProcessInfo.processInfo.physicalMemory / 1_073_741_824) GB, macOS \(ProcessInfo.processInfo.operatingSystemVersionString):\n"
        if let ac = antiCheatVerdict(c.anticheat) { v += "  • \(ac.1)\n" }
        if c.hbStatus == "blocked-anticheat" || antiCheatVerdict(c.anticheat)?.0 == .red { return v + "  → No. Kernel anti-cheat cannot run under any Wine on a Mac; consider cloud gaming or a native Mac version.\n" }
        if !c.hbStatus.isEmpty { v += "  • Highball: \(c.hbStatus)\(c.renderer.isEmpty ? "" : ", runs through \(c.renderer)")\n" }
        if !c.tier.isEmpty { v += "  • ProtonDB (Linux, indicative): \(c.tier)\n" }
        if c.renderer == "d3dmetal" { v += d3dmetalOK ? "  • Needs Direct3D 12 → D3DMetal (accepted) ✓\n" : "  • Needs Direct3D 12 → D3DMetal: install from Apple and accept its license first\n" }
        let good = ["verified-local", "reported-upstream", "community"].contains(c.hbStatus) || ["platinum", "gold"].contains(where: { c.tier.hasPrefix($0) })
        v += good ? "  → Likely yes" : (c.hbStatus.isEmpty && c.tier.isEmpty ? "  → Unknown: no reports yet; the launch check will tell once installed" : "  → Doubtful: weak reports")
        return v + (c.anticheat.isEmpty ? "" : " (offline/single-player)") + ".\n"
    }

    // §8.8 Memory-pressure advisor: while a game runs, warn (at most every 10 min) when macOS is low on memory or swapping hard.
    var lastMemWarn = Date.distantPast
    func memoryAdvisor() {
        guard Date().timeIntervalSince(lastMemWarn) > 600, !sh("ps -axo command= | grep -c 'steamapps.common\\|Program Files.*\\.exe'").hasPrefix("0") else { return }
        let level = Int(sh("sysctl -n kern.memorystatus_level")) ?? 100
        let swap = Double(sh("sysctl -n vm.swapusage | sed -E 's/.*used = ([0-9.]+)M.*/\\1/'")) ?? 0
        if level < 20 || swap > 4096 {
            lastMemWarn = Date()
            log += "⚠ Memory pressure while a game runs (free level \(level)%, swap \(Int(swap / 1024)) GB): close other apps or lower texture quality; stutter and long loads come from swapping.\n"
        }
    }
    // Run something when a program's process is gone (polled; Steam games are started by Steam, so we can't wait on a child).
    func whenExits(_ exe: String, _ then: @escaping @MainActor () -> Void) {
        let name = (exe as NSString).lastPathComponent
        Task { @MainActor in
            for _ in 0..<30 { try? await Task.sleep(nanoseconds: 2_000_000_000); if !sh("pgrep -f '\(name)' | wc -l").hasPrefix("0") { break } }   // wait up to 60 s for it to appear
            while !sh("pgrep -f '\(name)' | wc -l").hasPrefix("0") { try? await Task.sleep(nanoseconds: 10_000_000_000) }
            then()
        }
    }
    // §9.8 Focus automation: Options FOCUS_SHORTCUT=<Shortcut name> runs that Shortcut when the game starts and again when it exits (make it a toggle).
    func focusAutomation(_ exe: String) {
        guard let s = options(exe)["FOCUS_SHORTCUT"], !s.isEmpty else { return }
        _ = sh("shortcuts run '\(s)' >/dev/null 2>&1 &"); log += "Focus: ran Shortcut “\(s)”; runs again when \(appName(exe)) exits.\n"
        whenExits(exe) { _ = self.sh("shortcuts run '\(s)' >/dev/null 2>&1 &"); self.log += "Focus: ran Shortcut “\(s)” (game exited).\n" }
    }
    // §9.9 Pause in background: Options PAUSE_IN_BACKGROUND=1 suspends the game's process while another app is frontmost (SIGSTOP/SIGCONT).
    // Refused for anti-cheat and online-flagged games; the game must be a single-player title you tested this with.
    var pauseObservers: [NSObjectProtocol] = []
    func pauseInBackground(_ exe: String, anticheat: Bool) {
        guard options(exe)["PAUSE_IN_BACKGROUND"] == "1" else { return }
        guard !anticheat else { log += "Pause in background ignored for \(appName(exe)): anti-cheat present.\n"; return }
        let name = (exe as NSString).lastPathComponent
        let nc = NSWorkspace.shared.notificationCenter
        let o = nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let self, let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pids = sh("pgrep -f '\(name)'").split(separator: "\n").joined(separator: " ")
            guard !pids.isEmpty else { return }
            let isGame = app.executableURL?.path.contains("/wswine.bundle/") == true || app.localizedName == self.appName(exe)
            _ = sh("kill -\(isGame ? "CONT" : "STOP") \(pids) 2>/dev/null")
        }
        pauseObservers.append(o); log += "Pause in background armed for \(appName(exe)).\n"
        whenExits(exe) { NSWorkspace.shared.notificationCenter.removeObserver(o); self.pauseObservers.removeAll { $0 === o } }
    }
    // §7.5 On-device crash explainer (Apple Intelligence Macs only): plain-language reading of the last log lines, nothing leaves the Mac.
    func explainCrash(_ name: String, _ tail: String) {
        if #available(macOS 26, *) {
            let model = SystemLanguageModel.default
            guard case .available = model.availability else { return }
            Task { @MainActor in
                do {
                    let session = LanguageModelSession(instructions: "You explain Wine/translation-layer logs for a Mac user in two short plain sentences: what most likely went wrong and one concrete thing to try. No code.")
                    let r = try await session.respond(to: "Program \(name) exited right after starting. Log tail:\n\(tail.suffix(3000))")
                    log += "On-device explanation: \(r.content)\n"
                } catch { log += "On-device explanation unavailable: \(error.localizedDescription)\n" }
            }
        }
    }

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

struct ContentView: View {
    @StateObject var m = Model()
    @State var newName = ""
    @State var confirmDelete = false
    @State var optExe: String? = nil
    @State var optText = ""
    @State var showD3DM = false
    @State var licRead = false
    @State var showTerms = !termsAccepted()
    @State var showSnaps = false
    @State var showWIR = false
    @State var wirLink = ""
    @State var showImport = false
    @State var rollbackTarget: String? = nil
    var body: some View {
        HSplitView {
            VStack(alignment: .leading) {
                Text("Bottles").font(.headline)
                List(m.bottles, id: \.self, selection: Binding(get: { m.selected }, set: { m.selected = $0; m.scan() })) { Text($0).tag($0) }
                HStack {
                    TextField("new bottle", text: $newName)
                    Button("Create") { m.createBottle(newName); newName = "" }.disabled(newName.isEmpty || m.busy)
                }
                HStack {
                    Button("Backup") { m.backupBottle() }.disabled(m.selected.isEmpty || m.busy)
                    Button("Archive") { m.archiveBottle() }.disabled(m.selected.isEmpty || m.busy)
                    Button("Restore") { m.restoreBottle() }.disabled(m.busy)
                    Button("Delete…", role: .destructive) { confirmDelete = true }.disabled(m.selected.isEmpty || m.busy)
                }
                HStack {
                    Button("Snapshots…") { showSnaps = true }.controlSize(.small).disabled(m.selected.isEmpty)
                        .help("APFS clones taken before Repair, runtime installs, overrides and access changes. Roll back in seconds.")
                    Button("Import…") { showImport = true }.controlSize(.small)
                        .help("Bring in bottles from Whisky, CrossOver or Sikarugir wrappers as APFS clones. Originals are never modified.")
                }
                HStack {
                    // Kernel anti-cheat (Call of Duty, Valorant, Fortnite…) can't run on a Mac in any form; the anti-cheat runs on the streaming server instead.
                    Button("Cloud…") {
                        if let gfn = ["/Applications/GeForceNOW.app", "/Applications/NVIDIA GeForce NOW.app"].first(where: { FileManager.default.fileExists(atPath: $0) }) { NSWorkspace.shared.open(URL(fileURLWithPath: gfn)) }
                        else { NSWorkspace.shared.open(URL(string: "https://play.geforcenow.com")!) }
                        NSWorkspace.shared.open(URL(string: "https://www.xbox.com/play")!)
                        m.log += "Cloud: GeForce NOW (own the game on Battle.net/Steam) and Xbox Cloud Gaming (Game Pass Ultimate) stream Call of Duty to this Mac; the DualSense works over Bluetooth.\n"
                    }.controlSize(.small).help("Anti-cheat games (Call of Duty, Valorant, Fortnite) via GeForce NOW or Xbox Cloud Gaming.")
                }
                Divider()
                Text("Automatic").font(.headline)
                Text("Windows version per program · drivers per program · runtimes and community fixes on launch · Steam starts with the app · msync · MetalFX via a game's DLSS option · 60 fps cap and lighter rendering while on battery")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Metal performance HUD", isOn: $m.hud).disabled(m.selected.isEmpty)
                    .onChange(of: m.hud) { _, v in if !m.loading { m.envSet("MTL_HUD_ENABLED", v ? "1" : nil); m.restartSteamIfIdle() } }
                Divider()
                HStack {
                    Circle().fill(m.driverStatus.0).frame(width: 10, height: 10)
                    Text("Drivers").font(.headline); Spacer()
                    Button("D3DMetal…") { showD3DM = true }.controlSize(.small)
                        .help("Apple's Game Porting Toolkit for Direct3D 12: install from Apple's download, read and accept Apple's license, or remove it.")
                    Button("Update…") { m.updateDrivers() }.controlSize(.small).disabled(m.busy)
                        .help("Runs the weekly driver update now: DXMT and DXVK from their GitHub releases, D3DMetal from the newest Sikarugir template. Previous versions are kept as .old.")
                    Button("Folder…") { NSWorkspace.shared.open(URL(fileURLWithPath: driversDir)) }.controlSize(.small)
                }
                Text(m.driverStatus.1 + (m.driverUpdates.isEmpty ? "" : " · " + m.driverUpdates)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                HStack {
                    Circle().fill(m.padStatus.0).frame(width: 10, height: 10)
                    Text("Controller").font(.headline)
                    Text(m.padStatus.1).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                ForEach(installedDrivers(), id: \.self) { d in   // read-only: the launch check picks per program
                    Label(driverLabel(d), systemImage: m.drivers.contains(d) ? "checkmark.circle.fill" : "circle")
                        .font(.caption).foregroundStyle(m.drivers.contains(d) ? .primary : .secondary).padding(.leading, 4)
                }
                Text("Chosen from what is installed: dxmt for Direct3D 10/11 bottles, d3dmetal as soon as a Direct3D 12 game is present (Steam is restarted automatically).")
                    .font(.caption).foregroundStyle(.secondary)
            }.frame(minWidth: 200, maxWidth: 340).padding()
            VStack(alignment: .leading) {
                HStack {
                    Text("Programs in \(m.selected)").font(.headline)
                    Spacer()
                    Button("Find apps") { m.findApps() }.disabled(m.selected.isEmpty || m.busy)
                        .help("Searches the whole C: drive of this bottle for programs the normal scan missed.")
                    Button("Run .exe / .msi…") { pick() }.disabled(m.busy)
                }
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 16)], spacing: 16) {
                        ForEach(m.programs, id: \.self) { p in
                            Button { m.launch(p) } label: {
                                VStack {
                                    Image(nsImage: m.icons[p] ?? NSWorkspace.shared.icon(for: .applicationBundle))
                                        .resizable().interpolation(.high).frame(width: 64, height: 64)
                                        .overlay(alignment: .topTrailing) {   // pre-verification light; hover for the reason
                                            if let r = m.readiness[p] { Circle().fill(r.status).frame(width: 12, height: 12).overlay(Circle().stroke(.black.opacity(0.4))).offset(x: 4, y: -4) }
                                        }
                                    Text(appName(p)).font(.caption).lineLimit(2).multilineTextAlignment(.center)
                                }.frame(width: 100).padding(.vertical, 6).contentShape(Rectangle())
                            }.buttonStyle(.plain).disabled(m.busy)
                            .help(m.readiness[p]?.note.trimmingCharacters(in: .whitespacesAndNewlines) ?? "checking…")
                            .contextMenu {
                                Button("Check requirements") { m.readiness[p] = m.launchNeeds(p); m.log += m.readiness[p]?.note ?? ""; if m.readiness[p]?.note.isEmpty ?? true { m.log += "\(appName(p)): nothing special needed.\n" } }
                                Button("Options…") { optText = (try? String(contentsOfFile: m.optionsPath(p), encoding: .utf8)) ?? Model.optionsTemplate; optExe = p }
                                Button("Create Dock shortcut") { m.makeShortcut(p) }
                            }
                        }
                    }.padding(8)
                }
                HStack {
                    Text("Drop an installer anywhere in this window — a bottle is created automatically if needed.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Will it run?…") { showWIR = true }.controlSize(.small)
                        .help("Paste a Steam store link: verdict for this Mac from Highball, ProtonDB and the anti-cheat map, before you buy.")
                    Button("Bug report") { m.copyBugReport() }.controlSize(.small)
                        .help("Copies a report with log, engine, drivers and Mac details to the clipboard, with your username and home folder removed.")
                    Button("Input check") { m.inputCheck() }.controlSize(.small).disabled(m.selected.isEmpty || m.busy)
                        .help("Checks controller + keyboard from macOS through Wine, then opens Wine's Game Controllers panel for a live test.")
                    Button("Troubleshoot") { m.troubleshoot() }.controlSize(.small)
                    Button("Repair") { m.repair() }.controlSize(.small).disabled(m.selected.isEmpty || m.busy)
                        .help("Kills stuck Wine processes and restores the bottle defaults: SDL controllers, 96 DPI, Steam overrides.")
                }
                ScrollView { Text(m.log).font(.system(.caption, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }
                    .frame(height: 160).background(.black.opacity(0.08))
            }.padding()
        }
        .frame(minWidth: 760, minHeight: 700)
        .sheet(isPresented: $showWIR) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Will it run on this Mac?").font(.headline)
                TextField("https://store.steampowered.com/app/3751260/… or an app id", text: $wirLink).textFieldStyle(.roundedBorder).frame(width: 520)
                Text("Checks Highball's curated data, the anti-cheat map and ProtonDB for your chip, memory and macOS version. The verdict appears in the log pane.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack { Spacer(); Button("Close") { showWIR = false }.keyboardShortcut(.cancelAction); Button("Check") { m.log += m.willItRun(wirLink); showWIR = false }.keyboardShortcut(.defaultAction).disabled(wirLink.isEmpty) }
            }.padding()
        }
        .sheet(isPresented: $showSnaps) {
            let snaps = m.snapshots()
            VStack(alignment: .leading, spacing: 8) {
                Text("Snapshots of \(m.selected)").font(.headline)
                Text("APFS clones: made in seconds, cost almost no disk, removed after 30 days. Rolling back swaps the bottle for the snapshot and keeps the current state as a snapshot too.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if snaps.isEmpty { Text("No snapshots yet. One is taken automatically before Repair, runtime installs, DLL overrides and access changes; Backup makes one on demand.").font(.callout) }
                ScrollView { VStack(alignment: .leading, spacing: 4) { ForEach(snaps, id: \.path) { s in
                    HStack { Text(s.when).font(.system(.caption, design: .monospaced)); Text(s.reason).font(.caption).lineLimit(1); Spacer()
                        Button("Roll back…") { rollbackTarget = s.path }.controlSize(.small).disabled(m.busy)
                        Button("Delete") { try? FileManager.default.removeItem(atPath: s.path); m.refresh() }.controlSize(.small) }
                } } }.frame(width: 560, height: 200)
                HStack { Spacer(); Button("Close") { showSnaps = false }.keyboardShortcut(.cancelAction) }
            }.padding()
            .confirmationDialog("Roll back \(m.selected) to this snapshot? Programs in the bottle are stopped first.", isPresented: Binding(get: { rollbackTarget != nil }, set: { if !$0 { rollbackTarget = nil } })) {
                Button("Roll back", role: .destructive) { if let t = rollbackTarget { m.rollback(to: t) }; rollbackTarget = nil; showSnaps = false }
            }
        }
        .sheet(isPresented: $showImport) {
            let found = m.importableBottles()
            VStack(alignment: .leading, spacing: 8) {
                Text("Import bottles").font(.headline)
                Text("Found on this Mac from Whisky, CrossOver and Sikarugir wrappers. Importing clones the prefix (APFS, seconds, originals untouched) into Cosmopolitan as a restricted bottle.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if found.isEmpty { Text("Nothing to import: no Whisky, CrossOver or Sikarugir bottles were found.").font(.callout) }
                ForEach(found, id: \.path) { b in
                    HStack { Text(b.label); Spacer(); Button("Import") { m.importBottle(b.path, as: String(b.label.split(separator: ":").last!).trimmingCharacters(in: .whitespaces)); showImport = false }.controlSize(.small).disabled(m.busy) }
                }
                HStack { Spacer(); Button("Close") { showImport = false }.keyboardShortcut(.cancelAction) }
            }.padding().frame(width: 520)
        }
        .sheet(isPresented: $showTerms) {   // first run (or changed terms): nothing else until Accept; Quit exits the app
            VStack(alignment: .leading, spacing: 10) {
                Text("Cosmopolitan — Terms of Use and Notices").font(.headline)
                ScrollView { Text((try? String(contentsOfFile: termsPath, encoding: .utf8)) ?? "TERMS.txt missing from the app bundle.").font(.system(.body, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }
                    .frame(width: 640, height: 380).border(.secondary.opacity(0.4))
                HStack {
                    Button("Quit") { NSApp.terminate(nil) }.keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Accept") { acceptTerms(); showTerms = false }.keyboardShortcut(.defaultAction).disabled(termsPath.isEmpty)
                }
            }.padding().interactiveDismissDisabled()
        }
        .sheet(isPresented: $showD3DM) {
            let installed = d3dmetalInstalled(), lic = d3dmetalLicenseFile()
            VStack(alignment: .leading, spacing: 10) {
                Text("D3DMetal — Apple Game Porting Toolkit").font(.headline)
                Text("D3DMetal translates Direct3D 12 (and 11) to Metal. It is Apple's proprietary software under Apple's own license: not part of Cosmopolitan, obtained by you from Apple, copied unmodified into Application Support, never sold. Status: " + (!installed ? "not installed" : d3dmetalOK ? "installed, license accepted" : "installed, license NOT accepted — Direct3D 12 games will not use it until you accept"))
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Apple's download page") { NSWorkspace.shared.open(URL(string: "https://developer.apple.com/games/game-porting-toolkit/")!) }
                    Button("Install from Apple's download…") {
                        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = true; p.allowedContentTypes = [.folder, .diskImage]
                        p.message = "Choose the Game Porting Toolkit .dmg, its mounted volume, or the extracted folder"
                        if p.runModal() == .OK, let u = p.url { m.installD3DMetal(from: u.path); licRead = false }
                    }
                }
                if installed, !d3dmetalOK, let lic {   // the license itself, from the user's download, shown unmodified before Accept can be clicked
                    LicenseView(path: lic).frame(height: 300).border(.secondary.opacity(0.4))
                    Toggle("I have read Apple's Software License Agreement for Game Porting Toolkit", isOn: $licRead)
                }
                HStack {
                    Button("I accept Apple's license") { m.acceptD3DMetal(); showD3DM = false }.disabled(!installed || d3dmetalOK || !licRead)
                    Button("Remove D3DMetal", role: .destructive) { m.removeD3DMetal(); showD3DM = false }.disabled(!FileManager.default.fileExists(atPath: driversDir + "/d3dmetal"))
                    Spacer(); Button("Close") { showD3DM = false }.keyboardShortcut(.cancelAction)
                }
                Text("Without D3DMetal, games fall back to DXMT (Direct3D 10/11), DXVK or Wine's own Direct3D; Direct3D 12-only games cannot run. Details in THIRD_PARTY_NOTICES.md.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding().frame(width: 600)
        }
        .sheet(isPresented: Binding(get: { optExe != nil }, set: { if !$0 { optExe = nil } })) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Options for \(appName(optExe ?? ""))").font(.headline)
                TextEditor(text: $optText).font(.system(.body, design: .monospaced)).frame(width: 520, height: 180)
                Text("Applies to the next launch. Empty file = fully automatic.").font(.caption).foregroundStyle(.secondary)
                HStack { Spacer(); Button("Cancel") { optExe = nil }; Button("Save") { if let e = optExe { m.saveOptions(e, optText) }; optExe = nil }.keyboardShortcut(.defaultAction) }
            }.padding()
        }
        .confirmationDialog("Delete bottle \"\(m.selected)\" and everything in it?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { m.deleteBottle() }
        }
        .onOpenURL { url in   // §7.7 Shortcuts / Siri: a Shortcut that opens cosmopolitan://launch?name=Steam (Siri runs Shortcuts by name)
            guard url.scheme == "cosmopolitan", url.host == "launch", let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "name" })?.value else { return }
            if let p = m.programs.first(where: { appName($0).localizedCaseInsensitiveCompare(q) == .orderedSame }) ?? m.programs.first(where: { appName($0).localizedCaseInsensitiveContains(q) }) { m.launch(p) }
            else { m.log += "Shortcut asked for “\(q)”: no such program in \(m.selected).\n" }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { ps in
            ps.first?.loadItem(forTypeIdentifier: "public.file-url") { d, _ in
                if let d = d as? Data, let u = URL(dataRepresentation: d, relativeTo: nil) { Task { @MainActor in m.install(u) } } }
            return true }
    }
    func pick() {
        let p = NSOpenPanel(); p.allowedContentTypes = ["exe", "msi"].compactMap { UTType(filenameExtension: $0) }
        if p.runModal() == .OK, let u = p.url { m.install(u) }
    }
}

@main struct CosmopolitanApp: App {
    // Terminal use: Cosmopolitan.app/Contents/MacOS/Cosmopolitan --troubleshoot [bottle] | --repair [bottle]  (same code as the buttons)
    init() {
        let a = CommandLine.arguments
        let modes = ["--troubleshoot", "--repair", "--input", "--find", "--status", "--check", "--update", "--launch", "--tune", "--tunesteam", "--newbottle", "--accept-d3dmetal", "--snapshot", "--rollback", "--importables", "--import", "--willitrun", "--bugreport", "--hints"]   // --launch <bottle> <exe> [seconds]   // --check <bottle> <exe>: dry-run of the launch check
        guard let i = a.firstIndex(where: { modes.contains($0) }) else { return }
        let m = Model()
        if i + 1 < a.count { m.selected = a[i + 1]; m.scan() }
        switch a[i] {
        case "--repair": m.repair(); case "--input": m.inputCheck(); case "--find": m.findApps(); case "--update": m.log += Model.performUpdate()
        case "--tunesteam": m.tuneSteam()
        case "--newbottle": if i + 1 < a.count { m.createBottle(a[i + 1]); RunLoop.main.run(until: Date().addingTimeInterval(90)) }   // --newbottle <name>
        case "--accept-d3dmetal": m.acceptD3DMetal()   // same action as the "I accept" button; for the user's own scripting only
        case "--snapshot": m.snapshot(a.count > i + 2 ? a[i + 2] : "manual")
        case "--willitrun": if i + 2 < a.count { m.log += m.willItRun(a[i + 2]) }
        case "--bugreport": m.copyBugReport(); m.log += NSPasteboard.general.string(forType: .string)?.components(separatedBy: "\n").prefix(6).joined(separator: "\n") ?? ""; m.log += "\n"
        case "--hints": m.log += m.powerHints().isEmpty ? "no power/thermal hints right now\n" : m.powerHints()
        case "--rollback": if let s = m.snapshots().first { m.rollback(to: s.path); RunLoop.main.run(until: Date().addingTimeInterval(40)) } else { m.log += "no snapshots\n" }
        case "--importables": m.log += m.importableBottles().map { "\($0.label)\t\($0.path)" }.joined(separator: "\n") + "\n"
        case "--import": if i + 3 < a.count { m.importBottle(a[i + 2], as: a[i + 3]); RunLoop.main.run(until: Date().addingTimeInterval(60)) }
        case "--tune": if i + 2 < a.count { m.log += m.tuneUnreal(a[i + 2]) ?? "nothing to tune (no settings file yet, or already tuned)\n" }
        case "--launch": if i + 2 < a.count { m.launch(a[i + 2]); RunLoop.main.run(until: Date().addingTimeInterval(Double(a.count > i + 3 ? a[i + 3] : "30") ?? 30)) }
        case "--check": if i + 2 < a.count { let n = m.launchNeeds(a[i + 2]); m.log += n.note + "drivers override: \(n.drivers ?? ["(bottle setting)"]) verbs: \(n.verbs) overrides: \(n.overrides) env: \(n.env) args: \(n.args) desktop: \(n.desktop) light: \(n.status == .green ? "green" : n.status == .yellow ? "yellow" : "red")\n" }
        case "--status": m.log += "drivers: \(m.driverStatus.0 == .green ? "green" : m.driverStatus.0 == .yellow ? "yellow" : "red") (\(m.driverStatus.1))\ncontroller: \(m.padStatus.0 == .green ? "green" : m.padStatus.0 == .yellow ? "yellow" : "red") (\(m.padStatus.1))\n"
        default: m.troubleshoot() }
        print(m.log); exit(0)
    }
    var body: some Scene {
        WindowGroup("Cosmopolitan") { ContentView() }   // cosmopolitan://launch?name=<program> handled in ContentView (§7.7 via Shortcuts/Siri)
            .commands { CommandGroup(after: .appInfo) { Button("Check for Updates…") { updater.checkForUpdates(nil) } } }
    }
}
