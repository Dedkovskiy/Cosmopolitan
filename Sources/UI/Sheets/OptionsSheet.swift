import SwiftUI
import UniformTypeIdentifiers

extension ContentView {
    @ViewBuilder var optionsSheet: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("Options for \(appName(optExe ?? ""))").font(.headline)
                TextEditor(text: $optText).font(.system(.body, design: .monospaced)).frame(width: 520, height: 180)
                Text("Applies to the next launch. Empty file = fully automatic.").font(.caption).foregroundStyle(.secondary)
                HStack { Spacer(); Button("Cancel") { optExe = nil }; Button("Save") { if let e = optExe { m.saveOptions(e, optText) }; optExe = nil }.keyboardShortcut(.defaultAction) }
            }.padding()

    }
}
