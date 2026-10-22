import SwiftUI
import UniformTypeIdentifiers

extension ContentView {
    @ViewBuilder var willItRunSheet: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("Will it run on this Mac?").font(.headline)
                TextField("https://store.steampowered.com/app/3751260/… or an app id", text: $wirLink).textFieldStyle(.roundedBorder).frame(width: 520)
                Text("Checks Highball's curated data, the anti-cheat map and ProtonDB for your chip, memory and macOS version. The verdict appears in the log pane.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack { Spacer(); Button("Close") { showWIR = false }.keyboardShortcut(.cancelAction); Button("Check") { m.log += m.willItRun(wirLink); showWIR = false }.keyboardShortcut(.defaultAction).disabled(wirLink.isEmpty) }
            }.padding()

    }
}
