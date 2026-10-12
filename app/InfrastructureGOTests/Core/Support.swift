import Foundation
import Testing
@testable import InfrastructureGO

/// Where the tests find the files they read. The game's data files and the shared cases are read from the
/// repository itself, so that the tests of the app, of the pipeline and of the backend all look at the same bytes.
nonisolated enum Repo {
    static let root: URL = URL(filePath: #filePath)
        .deletingLastPathComponent()    // Core
        .deletingLastPathComponent()    // InfrastructureGOTests
        .deletingLastPathComponent()    // app
        .deletingLastPathComponent()    // the repository

    static func data(_ path: String) throws -> Data {
        try Data(contentsOf: root.appending(path: path))
    }

    static func resource(_ name: String) throws -> Data {
        try data("app/InfrastructureGO/Resources/\(name)")
    }

    static func rules() throws -> GameRules { try GameRules(json: resource("spawn_rules.json")) }
    static func keepers() throws -> [Keeper] { try KeeperFile(json: resource("keepers.json")).keepers }
    static func world() throws -> WorldRules { try WorldRules(json: resource("world_rules.json")) }
    static func jobs() throws -> [JobRule] { try JobFile(json: resource("jobs.json")).jobs }
    static func book() throws -> Book { Book(rules: try rules(), world: try world(), keepers: try keepers(), gear: try gear(), jobs: try jobs()) }
    static func gear() throws -> GearFile { try GearFile(json: resource("gear.json")) }
    static func facts() throws -> FactFile { try FactFile(json: resource("facts.json")) }
    static func inlets() throws -> InletStore { try InletStore(json: resource("inlets.json")) }
    static func zones() throws -> ZoneStore { try ZoneStore(geojson: resource("zones.geojson")) }
}

/// The shared cases of model/spawn_cases.json, the same file the pipeline replays in Python.
nonisolated struct SpawnCases: Decodable, Sendable {
    nonisolated struct TierCase: Decodable, Sendable, CustomTestStringConvertible {
        let name: String
        let now: String
        let lastAnyAt: String?
        let myLastAt: String?
        let stormOpen: Bool
        let tier: Int
        var testDescription: String { name }
    }

    nonisolated struct PointsCase: Decodable, Sendable, CustomTestStringConvertible {
        let tier: Int
        let greatCatch: Bool
        let points: Int
        var testDescription: String { "tier \(tier)\(greatCatch ? ", great catch" : "")" }
    }

    let tierCases: [TierCase]
    let pointsCases: [PointsCase]

    static let shared: SpawnCases = {
        do { return try GameData.decoder.decode(SpawnCases.self, from: Repo.data("model/spawn_cases.json")) }
        catch { fatalError("model/spawn_cases.json cannot be read: \(error)") }
    }()
}

/// A timestamp with its offset, as the shared cases write it.
nonisolated func instant(_ text: String) throws -> Date {
    try Date(text, strategy: .iso8601)
}

/// A keeper made up for a test, so that a rule can be tried on a cast the tests control.
nonisolated func madeUpKeeper(_ id: String, kind: String, weight: Int = 1, zones: [String] = [], owners: [String] = [], roads: [String] = [], rows: Double = 1,
                              timing: Keeper.Timing = Keeper.Timing(watchS: [1.8, 3.0], tellS: 0.8, airS: 0.5, settleS: 0.6, hideEvery: 0, hideS: 0, feintEvery: 0)) -> Keeper {
    Keeper(id: id, name: id.capitalized, part: "grate", keeps: "keeper of the grate", kind: kind, pattern: "hopper", model: id, heightM: 0.4, hoverM: 0, weight: weight,
           habitat: Keeper.Habitat(zones: zones, owners: owners, roads: roads, rows: rows), timing: timing,
           clips: ["idle": "idle"], tell: "It crouches.", tellWord: "crouch", hint: "Somewhere.", returning: "Back again.", pose: "Proud Hop", joke: "", credit: "")
}

/// The drains of the game on a day in November, the ones a player can look at.
nonisolated func drainsOfTheGame() throws -> [Inlet] {
    let zones = try Repo.zones()
    return try Repo.inlets().heads.filter { zones.canBeCaught($0, on: "2026-11-10") }
}
