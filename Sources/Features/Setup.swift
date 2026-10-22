import SwiftUI

// First-run setup: everything a fresh Mac needs, downloaded and prepared with progress.
//  1. Sikarugir template (the engine's dylibs, MoltenVK, GStreamer, and the driver builds DXMT/DXVK/D9VK/cnc-ddraw);
//  2. the Wine engine chosen in Settings (default: the tested 10.0_8);
//  3. engine fix-ups (prepareEngine), drivers and GStreamer copied into Cosmopolitan's own folders.
// D3DMetal is never copied (Apple's license: the user installs it from Apple's download via Drivers › D3DMetal…).
// Homebrew helpers (winetricks, DOSBox) are offered, not forced; they need Homebrew, which Cosmopolitan does not install.
extension Model {
    var setupNeeded: Bool { !engineOK || !FileManager.default.fileExists(atPath: driversDir + "/dxmt/wine") }

    func runSetup() {
        guard !setupRunning else { return }
        setupRunning = true; setupProgress = 0; setupStep = "Starting…"
        let engine = engineName
        Task.detached {
            let step: @Sendable (String, Double) -> Void = { s, p in Task { @MainActor in self.setupStep = s; self.setupProgress = p; self.log += s + "\n" } }
            let ok = Model.performSetup(engine: engine, step: step)
            await MainActor.run {
                self.setupRunning = false
                if ok { self.showSetup = false; self.log += "Setup finished. Create a bottle or drop a Windows installer into the window.\n"; self.refresh() }
            }
        }
    }

    nonisolated static func performSetup(engine: String, step: @escaping (String, Double) -> Void) -> Bool {
        let fm = FileManager.default
        let tplDir = NSHomeDirectory() + "/Library/Application Support/Sikarugir/Template"
        // 1. Template
        step("Finding the newest Sikarugir template…", 0.02)
        var tpl = ((try? fm.contentsOfDirectory(atPath: tplDir)) ?? []).filter { $0.hasPrefix("Template-") && $0.hasSuffix(".app") }.sorted { $0.compare($1, options: .numeric) == .orderedDescending }.first
        if tpl == nil {
            let newest = shell("curl -s -m 15 https://sikarugir-app.github.io/Template/NewestVersion.txt").trimmingCharacters(in: .whitespacesAndNewlines)
            guard newest.hasPrefix("Template-") else { step("✗ Could not reach sikarugir-app.github.io. Check the internet connection and try again.", 0); return false }
            step("Downloading \(newest) (about 150 MB)…", 0.05)
            let r = shell("mkdir -p '\(tplDir)' && cd '\(tplDir)' && curl -sfL -m 1200 -o t.tar.xz 'https://github.com/Sikarugir-App/Template/releases/download/v1.0/\(newest).tar.xz' && tar xf t.tar.xz && rm -f t.tar.xz && ls -d Template-*.app | tail -1")
            guard r.hasSuffix(".app") else { step("✗ Template download failed. Try again.", 0); return false }
            tpl = r.components(separatedBy: "\n").last
        }
        let app = "\(tplDir)/\(tpl!)"
        // 2. Engine
        let engRoot = "\(support)/engines/\(engine)"
        if !fm.fileExists(atPath: engRoot + "/wswine.bundle/bin/wine") {
            step("Downloading the Wine engine \(engine) (about 160 MB)…", 0.35)
            let local = NSHomeDirectory() + "/Library/Application Support/Sikarugir/Engines/\(engine).tar.xz"
            let get = fm.fileExists(atPath: local) ? "cp '\(local)' e.tar.xz" : "curl -sfL -m 1800 -o e.tar.xz 'https://github.com/Sikarugir-App/Engines/releases/download/v1.0/\(engine).tar.xz'"
            step("Unpacking the engine…", 0.6)
            _ = shell("mkdir -p '\(engRoot)' && cd '\(engRoot)' && \(get) && tar xf e.tar.xz && rm -f e.tar.xz")
            guard fm.fileExists(atPath: engRoot + "/wswine.bundle/bin/wine") else { _ = shell("rm -rf '\(engRoot)'"); step("✗ Engine download failed. Try again.", 0); return false }
        }
        step("Preparing the engine (libraries, MoltenVK, GStreamer)…", 0.7)
        let prep = prepareEngine(engRoot + "/wswine.bundle")
        step(prep.trimmingCharacters(in: .whitespacesAndNewlines), 0.8)
        // 3. Drivers from the template (never D3DMetal)
        step("Installing graphics drivers (DXMT, DXVK, D9VK, cnc-ddraw)…", 0.85)
        _ = shell("mkdir -p '\(driversDir)'")
        for d in ["dxmt", "dxvk", "dxvk3", "d9vk", "cnc_ddraw"] where !fm.fileExists(atPath: "\(driversDir)/\(d)/wine") {
            _ = shell("cp -cR '\(app)/Contents/SharedSupport/renderer/\(d)' '\(driversDir)/\(d)' 2>/dev/null")
        }
        guard fm.fileExists(atPath: driversDir + "/dxmt/wine") else { step("✗ Drivers missing from the template. Try again.", 0); return false }
        let wine = "\(engRoot)/wswine.bundle/bin/wine"
        let v = shell("'\(wine)' --version 2>&1 | head -1")
        guard v.hasPrefix("wine-") else { step("✗ The engine does not start: \(v.prefix(80))", 0); return false }
        // 4. A first bottle, so a fresh Mac can install something right away (same steps as Create: wineboot, SDL pads, Windows 10, no Z:).
        let bottles = ((try? fm.contentsOfDirectory(atPath: bottlesDir)) ?? []).filter { !$0.hasPrefix(".") }
        if bottles.isEmpty {
            step("Creating the first bottle \"Games\"…", 0.92)
            let pfx = "\(bottlesDir)/Games"
            let env = "WINEPREFIX='\(pfx)' WINEDEBUG=-all WINEMSYNC=1 WINEDLLOVERRIDES='mscoree,mshtml='"
            _ = shell("mkdir -p '\(pfx)'; \(env) '\(wine)' wineboot -u >/dev/null 2>&1; \(env) '\(wine)' reg add 'HKLM\\System\\CurrentControlSet\\Services\\winebus' /v DisableHidraw /t REG_DWORD /d 1 /f >/dev/null 2>&1; \(env) '\(wine)' winecfg -v win10 >/dev/null 2>&1; '\(engRoot)/wswine.bundle/bin/wineserver' -w; rm -f '\(pfx)/dosdevices/z:'")
            guard fm.fileExists(atPath: "\(pfx)/drive_c/windows/system32/kernel32.dll") else { step("✗ The first bottle could not be created.", 0); return false }
            step("Installing .NET support (Wine Mono from WineHQ)…", 0.95)
            if !installWineMono(pfx, log: { step($0.trimmingCharacters(in: .whitespacesAndNewlines), 0.97) }) { step("⚠ .NET support could not be installed now; it is retried before the first .NET program starts.", 0.97) }
        }
        step("✓ Ready: \(v), drivers installed, bottle ready.", 1)
        return true
    }
}

extension ContentView {
    @ViewBuilder var setupSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Set up Cosmopolitan").font(.title2.bold())
            Text("Cosmopolitan needs a Wine engine and graphics drivers before it can run Windows programs. This downloads about 300 MB from the open-source Sikarugir project and prepares everything. It takes a few minutes.")
                .fixedSize(horizontal: false, vertical: true)
            Text("Engine: \(engineName)").font(.caption).foregroundStyle(.secondary)
            if m.setupRunning || m.setupProgress > 0 {
                ProgressView(value: m.setupProgress)
                Text(m.setupStep).font(.caption).lineLimit(2)
            }
            HStack {
                if !m.setupRunning && m.engineReady { Button("Close") { m.showSetup = false } }
                Spacer()
                Button(m.setupStep.hasPrefix("✗") ? "Try again" : "Set up") { m.runSetup() }
                    .keyboardShortcut(.defaultAction).disabled(m.setupRunning)
            }
        }.padding(24).frame(width: 520).interactiveDismissDisabled(m.setupRunning)
    }
}
