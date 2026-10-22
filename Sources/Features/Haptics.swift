import SwiftUI
import GameController
import CoreHaptics

// §5.4 DualSense haptics. Inside Wine a game talks XInput; winebus maps XInput vibration onto SDL rumble, and SDL's own DualSense driver
// (hidapi, enabled by the hints below in the launch environment) drives the pad's motors. Adaptive triggers and the fine haptics need the
// DualSense's native protocol, which no Windows game speaks under translation — not available. "Test rumble" exercises the pad from macOS so a
// silent pad in a game can be told apart from a game that simply doesn't rumble.
extension Model {
    func testRumble() {
        guard let pad = GCController.controllers().first(where: { $0.haptics != nil }) ?? GCController.controllers().first else { log += "Rumble test: no controller connected to macOS.\n"; return }
        guard let engine = pad.haptics?.createEngine(withLocality: .default) else { log += "Rumble test: \(pad.vendorName ?? "controller") has no haptics interface.\n"; return }
        do {
            try engine.start()
            let ev = CHHapticEvent(eventType: .hapticContinuous, parameters: [CHHapticEventParameter(parameterID: .hapticIntensity, value: 1), CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)], relativeTime: 0, duration: 0.6)
            let player = try engine.makePlayer(with: CHHapticPattern(events: [ev], parameters: []))
            try player.start(atTime: 0)
            log += "Rumble test: pulsed \(pad.vendorName ?? "the controller") for 0.6 s. If you felt it, in-game rumble reaches the pad through SDL; triggers stay passive under Wine.\n"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { engine.stop() }
        } catch { log += "Rumble test failed: \(error.localizedDescription)\n" }
    }
}
