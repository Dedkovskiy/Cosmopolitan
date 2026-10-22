import SwiftUI
import Carbon

// §9.2 US keyboard layout per game. Wine's Mac driver has no layout switch of its own, but it follows the input source macOS has selected,
// so the switch lives here: select the US layout when the game starts, restore the previous one when it exits. Automatic when the
// current layout is not Latin (Cyrillic, Greek, Arabic, Hebrew, Thai, …) because WASD and hotkeys break there; Options US_KEYBOARD=1 forces it,
// US_KEYBOARD=0 disables it for a game.
extension Model {
    private static func inputSourceID(_ s: TISInputSource) -> String {
        guard let p = TISGetInputSourceProperty(s, kTISPropertyInputSourceID) else { return "" }
        return Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String
    }
    static func currentLayoutID() -> String { inputSourceID(TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()) }
    @discardableResult static func selectLayout(_ id: String) -> Bool {
        guard let list = TISCreateInputSourceList([kTISPropertyInputSourceID: id] as CFDictionary, true)?.takeRetainedValue() as? [TISInputSource], let s = list.first else { return false }
        TISEnableInputSource(s)
        return TISSelectInputSource(s) == noErr
    }
    static let nonLatin = ["Russian", "Ukrainian", "Bulgarian", "Serbian", "Greek", "Arabic", "Hebrew", "Thai", "Georgian", "Armenian", "Persian", "Hindi", "Devanagari", "Korean", "Japanese", "Chinese", "Pinyin", "Kazakh", "Belarusian", "Macedonian", "Mongolian"]
    func forceKeyboardLayout(_ exe: String) {
        let o = options(exe)["US_KEYBOARD"]
        let before = Model.currentLayoutID()
        let wanted = o == "1" || (o != "0" && Model.nonLatin.contains { before.localizedCaseInsensitiveContains($0) })
        guard wanted, !before.hasSuffix(".US"), !before.hasSuffix(".ABC") else { return }
        guard Model.selectLayout("com.apple.keylayout.US") else { log += "Keyboard: could not select the US layout.\n"; return }
        log += "Keyboard: US layout while \(appName(exe)) runs (was \(before.components(separatedBy: ".").last ?? before)); restored on exit.\n"
        whenExits(exe) { Model.selectLayout(before); self.log += "Keyboard: layout restored to \(before.components(separatedBy: ".").last ?? before).\n" }
    }
}
