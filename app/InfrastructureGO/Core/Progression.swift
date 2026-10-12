import Foundation

/// The story of a role as gear.json states it. Points are experience and a level is reached at its points. Gear
/// comes in parts, and a piece is finished when it has all its parts.
nonisolated struct GearFile: Sendable, Decodable {
    nonisolated struct Role: Sendable, Decodable, Equatable {
        let id: String
        let name: String
    }

    nonisolated struct LevelRule: Sendable, Decodable, Equatable {
        let level: Int
        let points: Int
        let rank: String
    }

    nonisolated struct Piece: Sendable, Decodable, Equatable, Identifiable {
        let id: String
        let name: String
        let parts: Int
        let opens: String?
        let says: String
    }

    let version: Int
    let role: Role
    let levels: [LevelRule]
    let pieces: [Piece]

    init(json: Data) throws {
        self = try GameData.decoder.decode(GearFile.self, from: json)
    }

    func piece(_ id: String?) -> Piece? {
        guard let id else { return nil }
        return pieces.first { $0.id == id }
    }
}

/// Where a player stands, for the level bar.
nonisolated struct Standing: Sendable, Equatable {
    let level: Int
    let rank: String
    let pointsIntoLevel: Int
    let pointsToNext: Int?      // nil at the last level
    let fraction: Double        // of the way to the next level, 1 at the last level
}

nonisolated enum Progression {
    static func standing(points: Int, in file: GearFile) -> Standing {
        let points = max(0, points)
        let reached = file.levels.last { $0.points <= points } ?? file.levels[0]
        guard let next = file.levels.first(where: { $0.points > points }) else {
            return Standing(level: reached.level, rank: reached.rank, pointsIntoLevel: points - reached.points, pointsToNext: nil, fraction: 1)
        }
        let span = next.points - reached.points
        return Standing(level: reached.level, rank: reached.rank, pointsIntoLevel: points - reached.points, pointsToNext: next.points - points,
                        fraction: span > 0 ? Double(points - reached.points) / Double(span) : 1)
    }
}

/// How a handful of parts changed one piece of gear.
nonisolated struct Filled: Sendable, Equatable, Identifiable {
    let piece: GearFile.Piece
    let before: Int
    let after: Int
    var id: String { piece.id }
    var finished: Bool { after >= piece.parts && before < piece.parts }
}

/// Gear in parts. Parts fill one piece at a time, the pinned one first and then the pieces in the order of the
/// file. A finished piece takes no more parts, so nothing a crate gives is ever a duplicate to throw away.
nonisolated enum Gear {
    static func isFinished(_ piece: GearFile.Piece, parts: [String: Int]) -> Bool {
        (parts[piece.id] ?? 0) >= piece.parts
    }

    /// The finished pieces, in the order of the file.
    static func owned(parts: [String: Int], in file: GearFile) -> [GearFile.Piece] {
        file.pieces.filter { isFinished($0, parts: parts) }
    }

    /// Whether the player's gear opens a named way to play, such as the wider veil.
    static func opens(_ name: String, parts: [String: Int], in file: GearFile) -> Bool {
        owned(parts: parts, in: file).contains { $0.opens == name }
    }

    /// The piece the next part goes to, or nil when every piece is finished.
    static func next(parts: [String: Int], pinned: String?, in file: GearFile) -> GearFile.Piece? {
        if let pin = file.piece(pinned), !isFinished(pin, parts: parts) { return pin }
        return file.pieces.first { !isFinished($0, parts: parts) }
    }

    /// The parts still to be earned for all gear.
    static func missing(parts: [String: Int], in file: GearFile) -> Int {
        file.pieces.reduce(0) { $0 + max(0, $1.parts - (parts[$1.id] ?? 0)) }
    }

    /// Hand over a number of parts. Returns how each piece they went to changed and how many parts were left
    /// over because every piece is finished.
    static func add(_ count: Int, to parts: inout [String: Int], pinned: String?, in file: GearFile) -> (filled: [Filled], over: Int) {
        var left = max(0, count)
        var filled: [Filled] = []
        while left > 0, let piece = next(parts: parts, pinned: pinned, in: file) {
            let before = parts[piece.id] ?? 0
            let take = min(left, piece.parts - before)
            parts[piece.id] = before + take
            left -= take
            filled.append(Filled(piece: piece, before: before, after: before + take))
        }
        return (filled, left)
    }
}
