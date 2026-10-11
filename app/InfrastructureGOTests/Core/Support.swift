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
    static func species() throws -> [Species] { try SpeciesFile(json: resource("species.json")).species }
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

    nonisolated struct SpeciesCase: Decodable, Sendable, CustomTestStringConvertible {
        let inletId: String
        let day: String
        let tier: Int
        let stormOpen: Bool
        let species: String?
        var testDescription: String { "\(inletId) on \(day), tier \(tier)\(stormOpen ? ", storm" : "")" }
    }

    let tierCases: [TierCase]
    let pointsCases: [PointsCase]
    let speciesCases: [SpeciesCase]

    static let shared: SpawnCases = {
        do { return try GameData.decoder.decode(SpawnCases.self, from: Repo.data("model/spawn_cases.json")) }
        catch { fatalError("model/spawn_cases.json cannot be read: \(error)") }
    }()
}

/// A timestamp with its offset, as the shared cases write it.
nonisolated func instant(_ text: String) throws -> Date {
    try Date(text, strategy: .iso8601)
}
