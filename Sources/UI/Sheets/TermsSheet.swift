import SwiftUI
import UniformTypeIdentifiers

extension ContentView {
    @ViewBuilder var termsSheet: some View {
           // first run (or changed terms): nothing else until Accept; Quit exits the app
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
}
