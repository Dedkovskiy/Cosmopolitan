import SwiftUI

// Everything shown in the log pane is also appended to ~/Library/Logs/Cosmopolitan.log (truncated on each app start).
let logPath = NSHomeDirectory() + "/Library/Logs/Cosmopolitan.log"
let logFile: FileHandle? = { FileManager.default.createFile(atPath: logPath, contents: nil); return FileHandle(forWritingAtPath: logPath) }()
func logToFile(_ s: String) { logFile?.write(Data(s.utf8)) }
// True when running a command-line mode: no Steam autostart, no background jobs (a CLI process takes its children down when it exits).
var cliMode = false
// pgrep pattern that cannot match the shell running the pgrep itself: "[S]team.exe" matches "Steam.exe" but not the literal "[S]team.exe".
func pgrepPattern(_ name: String) -> String { name.isEmpty ? name : "[\(name.prefix(1))]\(name.dropFirst())" }
// Run a process to the end and return what it wrote to a Pipe stdout. Never waitUntilExit(): it spins the current run loop, so on the main thread
// queued main-actor work runs in the middle of the wait. That crashed the app ("trying to lock recursively") when the work read d3dmetalOK while
// d3dmetalOK's own lazy initialiser was this wait. The exit handler fires on a background queue, so the semaphore cannot deadlock the main thread.
@discardableResult func runToEnd(_ p: Process) -> Data {
    let done = DispatchSemaphore(value: 0); p.terminationHandler = { _ in done.signal() }
    guard (try? p.run()) != nil else { return Data() }   // not started: reading the pipe would block forever
    let d = (p.standardOutput as? Pipe)?.fileHandleForReading.readDataToEndOfFile() ?? Data()
    done.wait(); return d
}
// Run a shell command and return its output; usable from any thread.
func shell(_ cmd: String) -> String {
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/sh"); p.arguments = ["-c", cmd]
    let o = Pipe(); p.standardOutput = o; p.standardError = o
    return String(decoding: runToEnd(p), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}
