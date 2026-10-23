import AppIntents

// Item 37: Spotlight and Shortcuts can play a game ("Play <game> in Cosmopolitan"). The games are the Library's; the app opens and starts
// the game its usual way (launch checks included). Metadata.appintents is extracted at build time (scripts/build.sh).
struct GameEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Game"
    static let defaultQuery = GameQuery()
    let id: String   // the game's name, as the Library shows it
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(id)") }
}
struct GameQuery: EntityStringQuery {
    @MainActor func entities(for ids: [String]) async throws -> [GameEntity] { ids.map(GameEntity.init) }
    @MainActor func suggestedEntities() async throws -> [GameEntity] { Model.shared.library.map { GameEntity(id: appName($0)) } }
    @MainActor func entities(matching s: String) async throws -> [GameEntity] { Model.shared.library.map(appName).filter { $0.localizedCaseInsensitiveContains(s) }.map(GameEntity.init) }
}
struct PlayGameIntent: AppIntent {
    static let title: LocalizedStringResource = "Play a game"
    static let openAppWhenRun = true
    @Parameter(title: "Game") var game: GameEntity
    @MainActor func perform() async throws -> some IntentResult {
        if let p = Model.shared.library.first(where: { appName($0) == game.id }) { Model.shared.play(p) }
        return .result()
    }
}
struct CosmopolitanShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: PlayGameIntent(), phrases: ["Play \(\.$game) in \(.applicationName)", "Start \(\.$game) with \(.applicationName)"],
                    shortTitle: "Play a game", systemImageName: "gamecontroller")
    }
}
