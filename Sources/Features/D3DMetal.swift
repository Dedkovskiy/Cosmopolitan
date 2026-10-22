import SwiftUI

extension Model {
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
