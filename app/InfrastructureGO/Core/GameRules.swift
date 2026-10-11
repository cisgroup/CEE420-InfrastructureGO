import Foundation

/// The numbers of the game as spawn_rules.json states them. The app reads the file, the backend is seeded from
/// it, and the shared cases in model/spawn_cases.json are replayed against it.
nonisolated struct GameRules: Sendable, Decodable {
    nonisolated struct Fence: Sendable, Decodable {
        let radiusM: Double
        let maxAccuracyM: Double
        let serverMaxDistanceM: Double
        let siblingRadiusM: Double
    }

    nonisolated struct TierRule: Sendable, Decodable {
        let tier: Int
        let name: String
        let points: Int
        let minAgeDays: Double?
    }

    nonisolated struct GreatCatch: Sendable, Decodable {
        let points: Int
        let ringScaleMax: Double
    }

    nonisolated struct Ring: Sendable, Decodable {
        let periodS: Double
        let startScale: Double
        let endScale: Double
    }

    nonisolated struct Throw: Sendable, Decodable {
        let count: Int
        let minSwipePt: Double
        let aimToleranceDeg: Double
    }

    let version: Int
    let timezone: String
    let fence: Fence
    let tiers: [TierRule]
    let greatCatch: GreatCatch
    let ring: Ring
    let throwing: Throw

    enum CodingKeys: String, CodingKey {
        case version, timezone, fence, tiers, greatCatch, ring
        case throwing = "throw"
    }

    init(json: Data) throws {
        self = try GameData.decoder.decode(GameRules.self, from: json)
    }

    var days: LocalDays { LocalDays(timezone: timezone) }
}

/// How the game's data files are read. Their keys are written with underscores.
nonisolated enum GameData {
    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}

/// How badly the town needs a look at a drain, which is what a catch there is worth.
nonisolated enum Tier: Int, Sendable, Codable, Comparable, CaseIterable {
    case resting = 0
    case common = 1
    case uncommon = 2
    case rare = 3

    static func < (a: Tier, b: Tier) -> Bool { a.rawValue < b.rawValue }
}
