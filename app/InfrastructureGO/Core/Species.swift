import CryptoKit
import Foundation

/// What can be caught at a drain, as species.json states it.
nonisolated struct Species: Sendable, Decodable, Equatable, Identifiable {
    let id: String
    let name: String
    let tier: Int
    let pool: String
    let model: String
    let scaleM: Double
    let idle: String
    let factId: String?
    let credit: String
}

nonisolated struct SpeciesFile: Sendable, Decodable {
    let version: Int
    let species: [Species]

    init(json: Data) throws {
        self = try GameData.decoder.decode(SpeciesFile.self, from: json)
    }
}

/// Which creature sits at a drain on a day. The choice depends on the drain, the day, the tier and the pool and
/// on nothing else, so that every player meets the same creature and the server comes to the same answer.
nonisolated enum SpeciesPicker {
    static let basePool = "base"
    static let stormPool = "storm"

    /// The first four bytes of the MD5 of the key as a big endian number, modulo the count. MD5 is used because
    /// Swift, Python and Postgres all compute it without anything added. Nothing here is a secret.
    static func hashIndex(_ key: String, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let digest = Array(Insecure.MD5.hash(data: Data(key.utf8)).prefix(4))
        let number = digest.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        return Int(number % UInt32(count))
    }

    /// The species at a drain on a local day, or nil for a resting drain. While a storm window is open the storm
    /// pool replaces the base pool wherever the tier has storm species.
    static func pick(inletId: String, day: String, tier: Tier, stormOpen: Bool, from species: [Species]) -> Species? {
        guard tier > .resting else { return nil }
        var pool = stormOpen ? stormPool : basePool
        var choices = species.filter { $0.tier == tier.rawValue && $0.pool == pool }
        if choices.isEmpty, pool == stormPool {
            pool = basePool
            choices = species.filter { $0.tier == tier.rawValue && $0.pool == pool }
        }
        guard !choices.isEmpty else { return nil }
        return choices[hashIndex("\(inletId)|\(day)|\(tier.rawValue)|\(pool)", count: choices.count)]
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
