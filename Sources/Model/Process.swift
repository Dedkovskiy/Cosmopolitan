import SwiftUI

extension Model {
    func exec(_ path: String, _ args: [String], env: [String: String] = [:], block: Bool = true, exe: String? = nil, then: (@MainActor () -> Void)? = nil) {
        if block { busy = true }
        log += "$ \((path as NSString).lastPathComponent) \(args.joined(separator: " "))\n"
        let started = Date()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.environment = ProcessInfo.processInfo.environment.merging(env) { $1 }
        if let exe, FileManager.default.fileExists(atPath: exe) { p.currentDirectoryURL = URL(fileURLWithPath: (exe as NSString).deletingLastPathComponent) }   // like Explorer: a program starts in its own folder

        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { h in
            let s = String(decoding: h.availableData, as: UTF8.self)
            if !s.isEmpty { logToFile(s); Task { @MainActor in self.log += s } }
        }
        p.terminationHandler = { t in let code = t.terminationStatus; Task { @MainActor in
            pipe.fileHandleForReading.readabilityHandler = nil
            if block { self.busy = false }
            self.log += code == 0 ? "[done]\n" : "[failed: exit \(code)]\n"
            if let exe, code != 0, Date().timeIntervalSince(started) < 60 { self.triage(exe, code) }   // died right away: look for a known cause
            then?(); self.refresh() } }
        do { try p.run() } catch { log += "Failed: \(error)\n"; busy = false }
    }

    func wine(_ bottle: String, _ args: [String], block: Bool = true, env: [String: String] = [:], drivers: [String]? = nil, exe: String? = nil, then: (@MainActor () -> Void)? = nil) {
        guard engineOK else { log += "Wine engine missing.\n"; return }
        exec(exe.map(loaderNamed) ?? wineBin, args, env: launchEnv(bottle, drivers: drivers).merging(env) { $1 }, block: block, exe: exe, then: then)
    }
}
