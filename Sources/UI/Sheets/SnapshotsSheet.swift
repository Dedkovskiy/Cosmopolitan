import SwiftUI
import UniformTypeIdentifiers

extension ContentView {
    @ViewBuilder var snapshotsSheet: some View {
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
}
