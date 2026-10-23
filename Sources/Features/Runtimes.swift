import Foundation

// Microsoft runtimes in a bottle: the pinned installers from Microsoft (Components.swift), run with their own silent switches. Used when a
// program imports a DLL that only these runtimes provide, and for the community-fix verbs that name them (instead of winetricks).
enum Runtime: String, CaseIterable, Sendable {
    case vcredist86, vcredist64, directx
    var pin: Pinned { switch self { case .vcredist86: Pins.vcRedist86; case .vcredist64: Pins.vcRedist64; case .directx: Pins.directX } }
}

extension Model {
    // The runtime that provides a DLL a program imports, if it is one of ours. The rule lives in C++ (cosmo_preflight, item 13).
    nonisolated static func runtimeFor(dll: String, is32: Bool) -> Runtime? {
        let n = cosmo_preflight(dll.lowercased(), is32 ? 1 : 0, 0).needs
        if n & UInt32(COSMO_NEED_VCREDIST86) != 0 { return .vcredist86 }
        if n & UInt32(COSMO_NEED_VCREDIST64) != 0 { return .vcredist64 }
        return n & UInt32(COSMO_NEED_DIRECTX) != 0 ? .directx : nil
    }
    // Item 28: the imports of the DLLs beside a program (its folder, top level, at most 64): an engine DLL can import Direct3D or a runtime
    // the exe itself doesn't. They only add graphics APIs and runtimes, never "missing DLLs" (an unused plugin may import anything).
    nonisolated static func besideImports(_ dir: String) -> Set<String> {
        let dlls = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).filter { $0.lowercased().hasSuffix(".dll") }.sorted().prefix(64)
        return Set(dlls.flatMap { peRead("\(dir)/\($0)").imports })
    }
    // Community-fix (winetricks) verbs that name one of these runtimes.
    nonisolated static func runtimesFor(verb: String) -> [Runtime] {
        let v = verb.lowercased()
        if ["vcrun2015", "vcrun2017", "vcrun2019", "vcrun2022"].contains(v) { return [.vcredist86, .vcredist64] }
        if v.hasPrefix("d3dx9") || v.hasPrefix("d3dx10") || v.hasPrefix("d3dx11") || ["d3dcompiler_43", "xact", "xact_x64", "xinput", "directx9", "dxsdk_jun2010"].contains(v) { return [.directx] }
        return []
    }
    nonisolated static func runtimeMarker(_ prefix: String, _ r: Runtime) -> String { prefix + "/.runtime-" + r.rawValue }
    // Microsoft's file, not Wine's builtin stand-in (in every bottle's system folders): Wine stamps "Wine builtin DLL" at offset 64, in the DOS stub.
    nonisolated static func isMicrosoftDLL(_ path: String) -> Bool {
        guard let h = FileHandle(forReadingAtPath: path), let head = try? h.read(upToCount: 256) else { return false }
        try? h.close()
        return head.count >= 128 && head.range(of: Data("Wine builtin DLL".utf8)) == nil
    }

    // Installs the pinned runtime into the bottle. Blocking: call off the main actor.
    @discardableResult nonisolated static func installRuntime(_ r: Runtime, prefix: String, log: @escaping (String) -> Void) -> Bool {
        let fm = FileManager.default
        guard let exe = fetchPinned(r.pin, log: log) else { return false }
        let tmp = prefix + "/drive_c/windows/temp", dst = tmp + "/" + r.pin.file
        try? fm.createDirectory(atPath: tmp, withIntermediateDirectories: true)
        try? fm.removeItem(atPath: dst); try? fm.copyItem(atPath: exe, toPath: dst)   // restricted bottles have no Z:, so it goes onto C:
        log("Installing \(r.pin.name) \(r.pin.version) into the bottle…\n")
        let w = plainWine(prefix)
        switch r {
        case .vcredist86, .vcredist64:
            _ = shell("cd '\(tmp)' && \(w) 'C:\\windows\\temp\\\(r.pin.file)' /install /quiet /norestart >/dev/null 2>&1")
        case .directx:   // the package is a self-extractor: unpack it, then run Microsoft's own DXSETUP silently
            _ = shell("cd '\(tmp)' && \(w) 'C:\\windows\\temp\\\(r.pin.file)' /Q '/T:C:\\windows\\temp\\dxredist' >/dev/null 2>&1 && \(w) 'C:\\windows\\temp\\dxredist\\DXSETUP.exe' /silent >/dev/null 2>&1")
            try? fm.removeItem(atPath: tmp + "/dxredist")
        }
        try? fm.removeItem(atPath: dst)
        // Installed = the runtime's DLL in the system folder is Microsoft's file, not Wine's builtin stand-in.
        let (dir, probe) = r == .vcredist64 ? ("system32", "msvcp140.dll") : r == .vcredist86 ? ("syswow64", "msvcp140.dll") : ("syswow64", "d3dx9_43.dll")
        let ok = isMicrosoftDLL("\(prefix)/drive_c/windows/\(dir)/\(probe)")
        if ok { try? "\(r.pin.version)\n".write(toFile: runtimeMarker(prefix, r), atomically: true, encoding: .utf8) }
        log(ok ? "✓ \(r.pin.name) installed (\(dir)\\\(probe) is Microsoft's).\n" : "✗ \(r.pin.name): the installer ran, but \(dir)\\\(probe) is still Wine's own.\n")
        return ok
    }
}
