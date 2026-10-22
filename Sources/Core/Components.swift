import Foundation
import CryptoKit

// Everything Cosmopolitan downloads is pinned: exact version, official URL, SHA-256, licence and source. Nothing is installed unless the
// downloaded file's hash matches. The full component list with sources is in docs/components.md.
struct Pinned: Sendable { let name, version, file, url, sha256, license, source: String }

enum Pins {
    // WineHQ publishes no checksum file; this hash is of the WineHQ file, and the release asset on the Wine Mono project's own GitHub
    // has the same bytes (both downloaded and compared on 2026-10-22).
    static let wineMono = Pinned(name: "Wine Mono", version: "9.4.0", file: "wine-mono-9.4.0-x86.msi",
        url: "https://dl.winehq.org/wine/wine-mono/9.4.0/wine-mono-9.4.0-x86.msi",
        sha256: "cf6173ae94b79e9de13d9a74cdb2560a886fc3d271f9489acb1cfdbd961cacb2",
        license: "MIT, with bundled components under their own licences", source: "WineHQ (same bytes as github.com/madewokherd/wine-mono, release wine-mono-9.4.0)")
}

func sha256File(_ path: String) -> String? {
    guard let h = FileHandle(forReadingAtPath: path) else { return nil }
    defer { try? h.close() }
    var hasher = SHA256()
    while let d = try? h.read(upToCount: 1 << 20), !d.isEmpty { hasher.update(data: d) }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
}

// The pinned file from support/cache, downloading it when missing or damaged. Returns a path only when the SHA-256 matches. A failed
// or mismatching download is deleted and nothing is installed; a verified file already in the cache is kept.
func fetchPinned(_ p: Pinned, log: (String) -> Void = { _ in }) -> String? {
    let fm = FileManager.default, dir = support + "/cache", path = dir + "/" + p.file, part = path + ".part"
    try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
    if sha256File(path) == p.sha256 { return path }
    // Test build only: fetch from another URL (a local file:// with wrong bytes) to prove the checksum check.
    let url = isTestBuild ? (ProcessInfo.processInfo.environment["COSMO_TEST_URL_" + p.file.replacingOccurrences(of: "[^A-Za-z0-9]", with: "_", options: .regularExpression)] ?? p.url) : p.url
    try? fm.removeItem(atPath: part)
    log("Downloading \(p.name) \(p.version) from \(URL(string: url)?.host ?? "a local file")…\n")
    _ = shell("curl -sfL --retry 2 -m 1800 -o '\(part)' '\(url)'")
    guard let got = sha256File(part) else { log("✗ \(p.name): download failed; nothing installed.\n"); return nil }
    guard got == p.sha256 else {
        try? fm.removeItem(atPath: part)
        log("✗ \(p.name): checksum mismatch (got \(got.prefix(12))…, expected \(p.sha256.prefix(12))…); nothing installed.\n"); return nil
    }
    try? fm.removeItem(atPath: path)
    guard (try? fm.moveItem(atPath: part, toPath: path)) != nil else { return nil }
    log("✓ \(p.name) \(p.version) verified (SHA-256 \(p.sha256.prefix(12))…).\n")
    return path
}

// Wine for helper runs inside a bottle: no driver slots (so nothing is ever copied into system32), msync like every launch.
func plainWine(_ prefix: String) -> String { "env WINEPREFIX='\(prefix)' WINEMSYNC=1 WINEDEBUG=-all '\(wineBin)'" }
