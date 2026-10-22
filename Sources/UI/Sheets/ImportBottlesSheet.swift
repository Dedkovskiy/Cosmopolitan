import SwiftUI
import UniformTypeIdentifiers

extension ContentView {
    @ViewBuilder var importBottlesSheet: some View {
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
}
