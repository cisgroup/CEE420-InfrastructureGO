import Foundation

/// Everything the game reads from its bundle, loaded once at launch. The drains and zones are written by the
/// pipeline, so the app, the web map and the backend count the same drains.
nonisolated struct GameContent: Sendable {
    let inlets: InletStore
    let zones: ZoneStore
    let rules: GameRules
    let world: WorldRules
    let keepers: [Keeper]
    let gear: GearFile
    let jobs: [JobRule]
    let facts: FactFile

    nonisolated enum Missing: Error {
        case file(String)
    }

    var book: Book { Book(rules: rules, world: world, keepers: keepers, gear: gear, jobs: jobs) }

    static func bundled(_ bundle: Bundle = .main) throws -> GameContent {
        func data(_ name: String, _ ending: String) throws -> Data {
            guard let url = bundle.url(forResource: name, withExtension: ending) else { throw Missing.file("\(name).\(ending)") }
            return try Data(contentsOf: url)
        }
        return GameContent(
            inlets: try InletStore(json: data("inlets", "json")),
            zones: try ZoneStore(geojson: data("zones", "geojson")),
            rules: try GameRules(json: data("spawn_rules", "json")),
            world: try WorldRules(json: data("world_rules", "json")),
            keepers: try KeeperFile(json: data("keepers", "json")).keepers,
            gear: try GearFile(json: data("gear", "json")),
            jobs: try JobFile(json: data("jobs", "json")).jobs,
            facts: try FactFile(json: data("facts", "json")))
    }
}
