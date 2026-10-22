import SwiftUI

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
        let pads = nativeControllers().joined(separator: ", ")   // IOKit HID, no shell
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
    var lastMemWarn = Date.distantPast                 // memory advisor rate limit
    @Published var artVersion = 0                      // bumped when cover art or playtime files change, so tiles redraw
    var pauseObservers: [NSObjectProtocol] = []        // pause-in-background observers, one per armed game
    @Published var autostartSteam = false              // AUTOSTART_STEAM=1 in cosmopolitan.env: Steam comes up with the app, with the bottle's drivers
    @Published var batterySaver = false   // 60 fps cap in D3DMetal and DXMT, DXMT renders at 2/3 and MetalFX-upscales: far less GPU work on battery
    @Published var metalFX = false        // D3DM_ENABLE_METALFX: a game's DLSS menu option becomes MetalFX temporal upscaling (D3DMetal, macOS 26+)
    func setBatterySaver(_ on: Bool) {
        envSet("D3DM_MAX_FPS", on ? "60" : nil)
        envSet("DXMT_CONFIG", on ? "d3d11.preferredMaxFrameRate=60;d3d11.metalSpatialUpscaleFactor=1.5" : nil)
    }
    // Stop Steam: ask politely, and if it is still up after 20 s (it sometimes ignores -shutdown), end its processes.
    func steamRunning() -> Bool { isRunning("Steam\\steam.exe") }   // libproc, matches the Windows command line Wine shows
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
        guard !cliMode, launchEnvRaw()["AUTOSTART_STEAM"] != "0", let s = programs.first(where: { $0.hasSuffix("/Steam/steam.exe") }) else { return }
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
        linkSharedBottles()
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
        for p in storeGames() where !found.contains(p) { found.append(p) }   // GOG game folders, Legendary-installed Epic games
        // Extras from "Find apps" (dropped silently once uninstalled).
        for p in ((try? String(contentsOfFile: "\(bottlesDir)/\(selected)/cosmopolitan.apps", encoding: .utf8)) ?? "").components(separatedBy: "\n")
            where !p.isEmpty && !found.contains(p) && FileManager.default.fileExists(atPath: p) { found.append(p) }
        found = dedupe(found)   // one tile per application folder
        for p in found where icons[p] == nil { icons[p] = exeIcon(p) }
        programs = found.sorted { ($0 as NSString).lastPathComponent.lowercased() < ($1 as NSString).lastPathComponent.lowercased() }
        verifyAll(); fetchArt()
        if watchedBottle != selected { watchBottle(); excludeFromBackups(selected) }
        for b in unpluggedBottles() { log += "Bottle \(b) is on a drive that is not connected; it reappears when the drive is plugged in.\n" }
    }

    // Run any executable; `block` locks the UI buttons until it exits.
}
