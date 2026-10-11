import Foundation
import Testing
@testable import InfrastructureGO

@Suite("The creature of a drain on a day")
struct SpeciesPickerTests {
    @Test("a shared species case", arguments: SpawnCases.shared.speciesCases)
    func species(_ c: SpawnCases.SpeciesCase) throws {
        let tier = try #require(Tier(rawValue: c.tier))
        let got = SpeciesPicker.pick(inletId: c.inletId, day: c.day, tier: tier, stormOpen: c.stormOpen, from: try Repo.species())
        #expect(got?.id == c.species)
    }

    @Test("the hash is the MD5 any tool computes")
    func hashIsMD5() {
        // The md5 command of macOS prints 4d3bb34d176171e43c035819d3d410d1 for this text.
        #expect(SpeciesPicker.hashIndex("in0742|2026-11-10|3|base", count: 2) == 1)
        #expect(SpeciesPicker.hashIndex("in0742|2026-11-10|3|base", count: 1 << 31) == 0x4d3b_b34d % (1 << 31))
        #expect(SpeciesPicker.hashIndex("anything", count: 0) == 0)
    }

    @Test func aRestingDrainHasNoCreature() throws {
        #expect(SpeciesPicker.pick(inletId: "in0001", day: "2026-11-10", tier: .resting, stormOpen: false, from: try Repo.species()) == nil)
        #expect(SpeciesPicker.pick(inletId: "in0001", day: "2026-11-10", tier: .resting, stormOpen: true, from: try Repo.species()) == nil)
    }

    @Test func aStormBringsTheStormPool() throws {
        let species = try Repo.species()
        let storm = Set(species.filter { $0.pool == "storm" }.map(\.id))
        let drawn = Set((1...60).compactMap { SpeciesPicker.pick(inletId: String(format: "in%04d", $0), day: "2026-11-10", tier: .rare, stormOpen: true, from: species)?.id })
        #expect(drawn == storm)
    }

    @Test func aTierWithoutStormSpeciesFallsBackToItsBasePool() throws {
        let species = try Repo.species()
        let picked = try #require(SpeciesPicker.pick(inletId: "in0001", day: "2026-11-10", tier: .uncommon, stormOpen: true, from: species))
        #expect(picked.pool == "base" && picked.tier == 2)
    }

    @Test func everySpeciesOfATierTurnsUpSomewhere() throws {
        let species = try Repo.species()
        for tier in [Tier.common, .uncommon, .rare] {
            let pool = Set(species.filter { $0.tier == tier.rawValue && $0.pool == "base" }.map(\.id))
            let drawn = Set((1...200).compactMap { SpeciesPicker.pick(inletId: String(format: "in%04d", $0), day: "2026-11-10", tier: tier, stormOpen: false, from: species)?.id })
            #expect(drawn == pool)
        }
    }

    @Test func nothingToPickFromGivesNothing() {
        #expect(SpeciesPicker.pick(inletId: "in0001", day: "2026-11-10", tier: .rare, stormOpen: false, from: []) == nil)
    }
}
