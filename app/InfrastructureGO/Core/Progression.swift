import Foundation

/// The story of a role as gear.json states it. Points are experience, a level is reached at its points, and each
/// level from the second on hands over one piece of gear.
nonisolated struct GearFile: Sendable, Decodable {
    nonisolated struct Role: Sendable, Decodable, Equatable {
        let id: String
        let name: String
    }

    nonisolated struct LevelRule: Sendable, Decodable, Equatable {
        let level: Int
        let points: Int
        let gear: String?
    }

    nonisolated struct Gear: Sendable, Decodable, Equatable, Identifiable {
        let id: String
        let name: String
        let factId: String?
        let unlock: String?
    }

    let version: Int
    let role: Role
    let levels: [LevelRule]
    let gear: [Gear]

    init(json: Data) throws {
        self = try GameData.decoder.decode(GearFile.self, from: json)
    }
}

/// Where a player stands, for the level bar.
nonisolated struct Standing: Sendable, Equatable {
    let level: Int
    let pointsIntoLevel: Int
    let pointsToNext: Int?      // nil at the last level
    let fraction: Double        // of the way to the next level, 1 at the last level
}

nonisolated enum Progression {
    static func standing(points: Int, in file: GearFile) -> Standing {
        let points = max(0, points)
        let reached = file.levels.last { $0.points <= points } ?? file.levels[0]
        guard let next = file.levels.first(where: { $0.points > points }) else {
            return Standing(level: reached.level, pointsIntoLevel: points - reached.points, pointsToNext: nil, fraction: 1)
        }
        let span = next.points - reached.points
        return Standing(level: reached.level, pointsIntoLevel: points - reached.points, pointsToNext: next.points - points,
                        fraction: span > 0 ? Double(points - reached.points) / Double(span) : 1)
    }

    /// Every piece of gear the points have earned, in the order of the levels.
    static func gear(at points: Int, in file: GearFile) -> [GearFile.Gear] {
        let level = standing(points: points, in: file).level
        return file.levels.filter { $0.level <= level }.compactMap { rule in file.gear.first { $0.id == rule.gear } }
    }

    /// The gear a catch has just earned, when the points rose from one total to another.
    static func newGear(from before: Int, to after: Int, in file: GearFile) -> [GearFile.Gear] {
        let had = Set(gear(at: before, in: file).map(\.id))
        return gear(at: after, in: file).filter { !had.contains($0.id) }
    }

    /// Whether the points have earned a named change of play, such as the drain's history on the map.
    static func has(unlock name: String, at points: Int, in file: GearFile) -> Bool {
        gear(at: points, in: file).contains { $0.unlock == name }
    }
}
