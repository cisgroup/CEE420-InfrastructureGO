import Foundation

/// The numbers of the world around the drains as world_rules.json states them.
nonisolated struct WorldRules: Sendable, Decodable {
    nonisolated struct Kinds: Sendable, Decodable {
        let common: Int
        let uncommon: Int
        let rarePerHundred: Int
    }

    nonisolated struct VeilRule: Sendable, Decodable {
        let cellM: Double
        let openM: Double
        let bootsOpenM: Double
        let origin: Coordinate
    }

    nonisolated struct DetectorRule: Sendable, Decodable {
        let rangeM: Double
        let longRangeM: Double
        let quietM: Double
        let slowTickS: Double
        let fastTickS: Double
    }

    nonisolated struct Nearby: Sendable, Decodable {
        let radiusM: Double
        let slots: Int
        let vestSlots: Int
    }

    nonisolated struct Slip: Sendable, Decodable {
        let minM: Double
        let maxM: Double
        let wheelMaxM: Double
        let waiting: Int
    }

    nonisolated struct HuntRule: Sendable, Decodable {
        let minM: Double
        let maxM: Double
        let opensAtLook: Int
    }

    nonisolated struct Points: Sendable, Decodable {
        let newKind: Int
        let mastered: Int
        let thanks: Int
    }

    nonisolated struct CatchRule: Sendable, Decodable {
        let flightS: Double
        let minSwipePt: Double
        let aimDeg: Double
        let wideAimDeg: Double
        let misses: Int
        let sittingShare: Double
        let graceS: Double
    }

    nonisolated struct Stages: Sendable, Decodable {
        let nearbyAfterMeetings: Int
        let jobsAfterDrains: Int
        let huntAfterLooks: Int
        let visitorAfterPieces: Int
    }

    nonisolated struct Invites: Sendable, Decodable {
        let notOwners: [String]
        let notRoads: [String]
        let notRoadPrefixes: [String]
    }

    nonisolated struct JobsRule: Sendable, Decodable {
        let slots: Int
        let reachM: Double
    }

    let version: Int
    let kinds: Kinds
    let senseM: Double
    let veil: VeilRule
    let detector: DetectorRule
    let nearby: Nearby
    let slip: Slip
    let hunt: HuntRule
    let crateParts: [Int]
    let points: Points
    let rungs: [Int]
    let catching: CatchRule
    let stages: Stages
    let invites: Invites
    let jobs: JobsRule

    enum CodingKeys: String, CodingKey {
        case version, kinds, senseM, veil, detector, nearby, slip, hunt, crateParts, points, rungs, stages, invites, jobs
        case catching = "catch"
    }

    init(json: Data) throws {
        self = try GameData.decoder.decode(WorldRules.self, from: json)
    }
}

/// Everything the rules read, in one hand, so that a function asks for one thing.
nonisolated struct Book: Sendable {
    let rules: GameRules
    let world: WorldRules
    let keepers: [Keeper]
    let gear: GearFile
    let jobs: [JobRule]

    func keeper(_ id: String?) -> Keeper? {
        guard let id else { return nil }
        return keepers.first { $0.id == id }
    }
}
