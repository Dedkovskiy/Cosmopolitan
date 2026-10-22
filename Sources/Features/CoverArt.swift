import SwiftUI

// §5.2 Cover art for Steam games from Steam's own public CDN (no API key, no account): cached per bottle under art/<appid>.jpg.
extension Model {
    func artPath(_ exe: String) -> String? { steamGames[exe].map { "\(bottlesDir)/\(selected)/art/\($0.id).jpg" } }
    func fetchArt() {
        let dir = "\(bottlesDir)/\(selected)/art"
        let todo = programs.compactMap { p -> (String, String)? in guard let g = steamGames[p], !FileManager.default.fileExists(atPath: "\(dir)/\(g.id).jpg") else { return nil }; return (g.id, "\(dir)/\(g.id).jpg") }
        guard !todo.isEmpty else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        Task.detached(priority: .background) {
            for (id, path) in todo {
                // Portrait box first; newer titles sometimes only have the landscape header.
                _ = shell("for n in library_600x900.jpg header.jpg; do curl -s -m 15 -o '\(path)' -f \"https://cdn.cloudflare.steamstatic.com/steam/apps/\(id)/$n\" && break; rm -f '\(path)'; done")
            }
            await MainActor.run { self.artVersion += 1 }
        }
    }
}
