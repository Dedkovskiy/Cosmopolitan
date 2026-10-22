import SwiftUI

// Everything shown in the log pane is also appended to ~/Library/Logs/Cosmopolitan.log (truncated on each app start).
let logPath = NSHomeDirectory() + "/Library/Logs/Cosmopolitan.log"
let logFile: FileHandle? = { FileManager.default.createFile(atPath: logPath, contents: nil); return FileHandle(forWritingAtPath: logPath) }()
func logToFile(_ s: String) { logFile?.write(Data(s.utf8)) }
// True when running a command-line mode: no Steam autostart, no background jobs (a CLI process takes its children down when it exits).
var cliMode = false
// pgrep pattern that cannot match the shell running the pgrep itself: "[S]team.exe" matches "Steam.exe" but not the literal "[S]team.exe".
func pgrepPattern(_ name: String) -> String { name.isEmpty ? name : "[\(name.prefix(1))]\(name.dropFirst())" }
// Run a shell command and return its output; usable from any thread.
func shell(_ cmd: String) -> String {
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/sh"); p.arguments = ["-c", cmd]
    let o = Pipe(); p.standardOutput = o; p.standardError = o
    try? p.run(); let d = o.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
    return String(decoding: d, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}
