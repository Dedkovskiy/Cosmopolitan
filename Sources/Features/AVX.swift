import SwiftUI
#if canImport(CosmoNative)
import CosmoNative   // swift build: the C++ module is a package target (scripts/build.sh uses the bridging header)
#endif

extension Model {
    // §7.2 / §4.3 AVX: Rosetta hides AVX unless asked. Disassemble the exe once (llvm-objdump reads PE) and count ymm-register uses;
    // a real count means the game has AVX code paths, so ROSETTA_ADVERTISE_AVX=1 goes into its launch. Cached per exe; ~25 s for a 25 MB exe.
    func avxCache(_ exe: String) -> String { "\(bottlesDir)/\(bottleOf(exe))/options/.avx-\((exe as NSString).lastPathComponent)" }
    // Cache line: "<vex>,<evex>" (older caches hold a single ymm count from the disassembler era; still valid as the first number).
    func avxCount(_ exe: String) -> Int? { Int(((try? String(contentsOfFile: avxCache(exe), encoding: .utf8)) ?? "").split(separator: ",").first.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") }
    func avx512Count(_ exe: String) -> Int { Int(((try? String(contentsOfFile: avxCache(exe), encoding: .utf8)) ?? "").split(separator: ",").dropFirst().first.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 0 }
    // Native C++ decoder (Sources/Native/avxscan.cpp): walks the code sections instruction by instruction, ~0.1 s for 25 MB.
    func scanAVX(_ exes: [String]) {
        let todo = exes.filter { avxCount($0) == nil && exeEra($0).kind == "pe" }
        guard !todo.isEmpty else { return }
        let caches = Dictionary(uniqueKeysWithValues: todo.map { ($0, avxCache($0)) })
        Task.detached(priority: .background) {
            for exe in todo {
                let r = cosmo_avx_scan(exe)
                guard r.error == 0 else { continue }
                try? FileManager.default.createDirectory(atPath: (caches[exe]! as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
                try? "\(r.vex),\(r.evex)".write(toFile: caches[exe]!, atomically: true, encoding: .utf8)
                await MainActor.run { self.readiness[exe] = self.launchNeeds(exe) }
            }
        }
    }
}
