import SwiftUI
import FoundationModels

extension Model {
    // §7.5 On-device crash explainer (Apple Intelligence Macs only): plain-language reading of the last log lines, nothing leaves the Mac.
    func explainCrash(_ name: String, _ tail: String) {
        if #available(macOS 26, *) {
            let model = SystemLanguageModel.default
            guard case .available = model.availability else { return }
            Task { @MainActor in
                do {
                    let session = LanguageModelSession(instructions: "You explain Wine/translation-layer logs for a Mac user in two short plain sentences: what most likely went wrong and one concrete thing to try. No code.")
                    let r = try await session.respond(to: "Program \(name) exited right after starting. Log tail:\n\(tail.suffix(3000))")
                    log += "On-device explanation: \(r.content)\n"
                } catch { log += "On-device explanation unavailable: \(error.localizedDescription)\n" }
            }
        }
    }
}
