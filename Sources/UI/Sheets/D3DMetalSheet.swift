import SwiftUI
import UniformTypeIdentifiers

extension ContentView {
    @ViewBuilder var d3dmetalSheet: some View {
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
}
