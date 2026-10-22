import SwiftUI

extension Model {
    func optionsPath(_ exe: String) -> String { "\(bottlesDir)/\(selected)/options/\((exe as NSString).lastPathComponent).env" }
    func options(_ exe: String) -> [String: String] {
        var o: [String: String] = [:]
        for l in ((try? String(contentsOfFile: optionsPath(exe), encoding: .utf8)) ?? "").components(separatedBy: "\n") where !l.hasPrefix("#") {
            let kv = l.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if kv.count == 2 { o[kv[0]] = kv[1] }
        }
        return o
    }
    func saveOptions(_ exe: String, _ text: String) {
        try? FileManager.default.createDirectory(atPath: (optionsPath(exe) as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try? text.write(toFile: optionsPath(exe), atomically: true, encoding: .utf8)
        readiness[exe] = launchNeeds(exe)
    }
    static let optionsTemplate = """
    # One setting per line. Lines starting with # are ignored.
    # ARGS=-dx11 -windowed          extra command-line arguments
    # DRIVERS=dxmt,d9vk             driver set for this program (overrides Auto)
    # LANG=ja_JP.UTF-8              run in another locale; ja/zh/ko also install matching fonts
    # MOUSE_CAPTURE=1               keep the cursor inside the game window (camera-heavy games)
    # FOCUS_SHORTCUT=Gaming         run this macOS Shortcut when the game starts and when it exits
    # PAUSE_IN_BACKGROUND=1         suspend the game while another app is in front (single-player only)
    # ROSETTA_ADVERTISE_AVX=0       force AVX off/on for this program (auto-detected otherwise)
    # WINEDLLOVERRIDES=xaudio2_7=n  any other KEY=VALUE becomes an environment variable

    """
}
