import SwiftUI

extension Model {
    // §7.2 / §4.3 AVX: Rosetta hides AVX unless asked. Disassemble the exe once (llvm-objdump reads PE) and count ymm-register uses;
    // a real count means the game has AVX code paths, so ROSETTA_ADVERTISE_AVX=1 goes into its launch. Cached per exe; ~25 s for a 25 MB exe.
    func avxCache(_ exe: String) -> String { "\(bottlesDir)/\(selected)/options/.avx-\((exe as NSString).lastPathComponent)" }
    func avxCount(_ exe: String) -> Int? { Int(((try? String(contentsOfFile: avxCache(exe), encoding: .utf8)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) }
    func scanAVX(_ exes: [String]) {
        let todo = exes.filter { avxCount($0) == nil && exeEra($0).kind == "pe" }
        guard !todo.isEmpty else { return }
        let caches = Dictionary(uniqueKeysWithValues: todo.map { ($0, avxCache($0)) })
        Task.detached(priority: .background) {
            for exe in todo {
                let n = shell("xcrun llvm-objdump -d --no-show-raw-insn '\(exe)' 2>/dev/null | grep -c ymm")
                try? FileManager.default.createDirectory(atPath: (caches[exe]! as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
                try? n.write(toFile: caches[exe]!, atomically: true, encoding: .utf8)
                await MainActor.run { self.readiness[exe] = self.launchNeeds(exe) }
            }
        }
    }
}
