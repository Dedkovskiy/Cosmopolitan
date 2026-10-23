// winshot PID PREFIX: saves each on-screen window of a process as PREFIX-1.png, PREFIX-2.png… (largest first) with screencapture -l,
// which captures a window's own contents even when other windows cover it. Prints one line per file with its size in points.
// Compile once: swiftc -O tests/lib/winshot.swift -o <dir>/winshot. Needs Screen Recording permission for the terminal.
import CoreGraphics
import Foundation

let args = CommandLine.arguments
guard args.count == 3, let pid = Int32(args[1]) else { print("usage: winshot PID PREFIX"); exit(2) }
func size(_ w: [String: Any]) -> (CGFloat, CGFloat) { let b = w[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]; return (b["Width"] ?? 0, b["Height"] ?? 0) }
let wins = ((CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? [])
    .filter { ($0[kCGWindowOwnerPID as String] as? Int32) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 && size($0).0 > 50 }
    .sorted { size($0).0 * size($0).1 > size($1).0 * size($1).1 }
guard !wins.isEmpty else { print("no window for pid \(pid)"); exit(1) }
for (n, w) in wins.enumerated() {
    guard let id = w[kCGWindowNumber as String] as? Int else { continue }
    let out = "\(args[2])-\(n + 1).png", p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture"); p.arguments = ["-x", "-o", "-l\(id)", out]
    try? p.run(); p.waitUntilExit()
    let (wd, ht) = size(w); print("\(out) \(Int(wd))x\(Int(ht))")
}
