import SwiftUI

// Settings window (⌘,). Everything here is stored in UserDefaults and read where it is used:
//  engine          — Wine engine folder under engines/ (default: the tested 10.0_8)
//  autostartSteam  — start Steam with the app when a bottle has it (default on)
//  dailyCleanup    — run Clean up once a day (default on)
//  compatReports   — after a session, offer a prefilled compatibility report for Highball (opt-in, default off; nothing is sent by itself)
struct SettingsView: View {
    @AppStorage("engine") var engine = defaultEngine
    @AppStorage("autostartSteam") var autostartSteam = true
    @AppStorage("dailyCleanup") var dailyCleanup = true
    @AppStorage("compatReports") var compatReports = false
    @State var tools: [(name: String, path: String?, formula: String, why: String)] = SettingsView.toolStatus()
    @State var installing: String? = nil

    static func toolStatus() -> [(name: String, path: String?, formula: String, why: String)] {
        func find(_ n: String) -> String? { ["/opt/homebrew/bin/\(n)", "/usr/local/bin/\(n)", NSHomeDirectory() + "/.local/bin/\(n)"].first { FileManager.default.fileExists(atPath: $0) } }
        return [("winetricks", find("winetricks"), "winetricks", "fetches runtimes (Visual C++, .NET, fonts) a game is missing"),
                ("DOSBox", find("dosbox"), "dosbox-staging", "runs DOS games"),
                ("Legendary", find("legendary"), "pipx:legendary-gl", "Epic Games library and downloads"),
                ("lgogdownloader", find("lgogdownloader"), "lgogdownloader", "GOG downloads for Windows-only games"),
                ("ClamAV", find("clamscan"), "clamav", "scans downloaded programs for malware")]
    }
    var engines: [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: support + "/engines")) ?? [])
            .filter { $0.hasPrefix("WS12Wine") && FileManager.default.fileExists(atPath: support + "/engines/\($0)/wswine.bundle/bin/wine") }.sorted()
    }

    var body: some View {
        Form {
            Section("Engine") {
                Picker("Wine engine", selection: $engine) {
                    ForEach(Set(engines + [engine]).sorted(), id: \.self) { e in Text(e + (e == defaultEngine ? "  (tested)" : "")).tag(e) }
                }
                Text("Changing the engine takes effect for programs started afterwards. 11.x engines currently show Steam black on macOS 27.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Behaviour") {
                Toggle("Start Steam together with Cosmopolitan", isOn: $autostartSteam)
                Toggle("Clean up caches and old versions once a day", isOn: $dailyCleanup)
            }
            Section("Compatibility reports") {
                Toggle("Offer a compatibility report after playing a game", isOn: $compatReports)
                Text("Off by default. When on, Cosmopolitan offers a prefilled report for the open Highball database after a session; it is only sent if you submit it yourself on GitHub. Nothing is ever sent automatically.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Section("Helper tools (Homebrew)") {
                ForEach(tools, id: \.name) { t in
                    HStack {
                        Image(systemName: t.path != nil ? "checkmark.circle.fill" : "circle").foregroundStyle(t.path != nil ? .green : .secondary)
                        VStack(alignment: .leading) { Text(t.name); Text(t.why).font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        if t.path == nil {
                            Button(installing == t.name ? "Installing…" : "Install") { install(t.name, t.formula) }
                                .disabled(installing != nil || !FileManager.default.fileExists(atPath: "/opt/homebrew/bin/brew"))
                        }
                    }
                }
                if !FileManager.default.fileExists(atPath: "/opt/homebrew/bin/brew") {
                    Text("Homebrew is not installed (brew.sh); these tools are optional.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }.formStyle(.grouped).frame(width: 520, height: 560)
    }

    func install(_ name: String, _ formula: String) {
        installing = name
        let cmd = formula.hasPrefix("pipx:") ? "command -v pipx >/dev/null || brew install pipx; pipx install \(formula.dropFirst(5))" : "brew install \(formula)"
        Task.detached {
            _ = shell("export PATH=/opt/homebrew/bin:/usr/local/bin:$PATH; \(cmd) >/dev/null 2>&1")
            await MainActor.run { installing = nil; tools = SettingsView.toolStatus() }
        }
    }
}
