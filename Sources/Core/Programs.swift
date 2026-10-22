import SwiftUI

// Display name = the program folder under Program Files, or the Steam library name for steamapps games.
var steamGames: [String: (id: String, name: String)] = [:]   // exe path -> appid/name from appmanifest_*.acf
func appName(_ p: String) -> String { steamGames[p]?.name ?? epicGames[p]?.name ?? ((p as NSString).deletingLastPathComponent as NSString).lastPathComponent }
