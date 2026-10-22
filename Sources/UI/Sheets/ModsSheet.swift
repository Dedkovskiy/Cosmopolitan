import SwiftUI
import UniformTypeIdentifiers

extension ContentView {
    @ViewBuilder var modsSheet: some View {
        if let exe = modExe {
            let list = m.mods(exe)
            VStack(alignment: .leading, spacing: 8) {
                Text("Mods for \(appName(exe))").font(.headline)
                Text("A mod is a folder or zip laid out like the game folder. Enabling copies it over the game and backs up every file it replaces; disabling restores them. A snapshot is taken before the first enable.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if list.isEmpty { Text("No mods yet.").font(.callout) }
                ForEach(list, id: \.name) { mod in
                    HStack {
                        Toggle(mod.name, isOn: Binding(get: { mod.enabled }, set: { m.setMod(exe, mod.name, enabled: $0) })).disabled(m.busy)
                        Spacer()
                        Button("Remove") { m.removeMod(exe, mod.name) }.controlSize(.small)
                    }
                }
                HStack {
                    Button("Add mod (folder or .zip)…") {
                        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = true; p.allowedContentTypes = [.folder, .zip]
                        if p.runModal() == .OK, let u = p.url { m.addMod(exe, from: u.path) }
                    }
                    Button("Open mods folder") { try? FileManager.default.createDirectory(atPath: m.modsDir(exe), withIntermediateDirectories: true); NSWorkspace.shared.open(URL(fileURLWithPath: m.modsDir(exe))) }
                    Spacer(); Button("Close") { modExe = nil }.keyboardShortcut(.cancelAction)
                }
            }.padding().frame(width: 520).id(m.artVersion)
        }
    }
}
