import Foundation

/// A keeper of the hidden watershed, as keepers.json states it. A keeper is what a player meets at a drain.
nonisolated struct Keeper: Sendable, Decodable, Hashable, Identifiable {
    /// Where a keeper can live. An empty list admits every zone, owner or road. Rows is how much likelier the
    /// keeper is at a drain with several grates in a row, 1 for no preference.
    nonisolated struct Habitat: Sendable, Decodable, Hashable {
        let zones: [String]
        let owners: [String]
        let roads: [String]
        let rows: Double
    }

    /// How a keeper behaves in a meeting, in seconds. It watches from the grate for a while, gives its tell,
    /// leaves the grate for a moment and settles again. Some hide under the grate after every few rounds, and
    /// some give their tell now and then without leaving.
    nonisolated struct Timing: Sendable, Decodable, Hashable {
        let watchS: [Double]
        let tellS: Double
        let airS: Double
        let settleS: Double
        let hideEvery: Int
        let hideS: Double
        let feintEvery: Int
    }

    let id: String
    let name: String
    let part: String
    let keeps: String
    let kind: String            // common, uncommon, rare or visitor
    let pattern: String         // hopper, bouncer or flyer
    let model: String
    let heightM: Double
    let hoverM: Double
    let weight: Int
    let habitat: Habitat
    let timing: Timing
    let clips: [String: String]
    let tell: String
    let tellWord: String
    let hint: String
    let returning: String
    let pose: String
    let joke: String
    let credit: String

    static let kinds = ["common", "uncommon", "rare", "visitor"]
}

nonisolated struct KeeperFile: Sendable, Decodable {
    let version: Int
    let keepers: [Keeper]

    init(json: Data) throws {
        self = try GameData.decoder.decode(KeeperFile.self, from: json)
    }
}

/// A fact card, one or two plain sentences with the source they come from.
nonisolated struct Fact: Sendable, Decodable, Equatable, Identifiable {
    let id: String
    let text: String
    let source: String
    let retrieved: String
}

nonisolated struct FactFile: Sendable, Decodable {
    let version: Int
    let facts: [Fact]

    init(json: Data) throws {
        self = try GameData.decoder.decode(FactFile.self, from: json)
    }

    func fact(id: String?) -> Fact? {
        guard let id else { return nil }
        return facts.first { $0.id == id }
    }
}
