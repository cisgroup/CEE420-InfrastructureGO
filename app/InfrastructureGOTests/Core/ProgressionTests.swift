import Foundation
import Testing
@testable import InfrastructureGO

@Suite("Levels and gear")
struct ProgressionTests {
    @Test func aNewPlayerIsAtLevelOneWithNothing() throws {
        let file = try Repo.gear()
        let standing = Progression.standing(points: 0, in: file)
        #expect(standing.level == 1 && standing.pointsIntoLevel == 0 && standing.fraction == 0)
        #expect(standing.pointsToNext == file.levels[1].points)
        #expect(Progression.gear(at: 0, in: file).isEmpty)
    }

    @Test("a level is reached at exactly its points", arguments: [(99, 1), (100, 2), (299, 2), (300, 3), (599, 3), (600, 4), (1000, 5), (1500, 6), (2200, 7), (3000, 8), (3999, 8), (4000, 9), (250_000, 9)])
    func levels(points: Int, level: Int) throws {
        #expect(Progression.standing(points: points, in: try Repo.gear()).level == level)
    }

    @Test func theBarFillsBetweenTwoLevels() throws {
        let standing = Progression.standing(points: 200, in: try Repo.gear())
        #expect(standing.level == 2 && standing.pointsIntoLevel == 100 && standing.pointsToNext == 100 && standing.fraction == 0.5)
    }

    @Test func theLastLevelHasNoNext() throws {
        let standing = Progression.standing(points: 5000, in: try Repo.gear())
        #expect(standing.level == 9 && standing.pointsToNext == nil && standing.fraction == 1 && standing.pointsIntoLevel == 1000)
    }

    @Test func negativePointsCountAsNone() throws {
        #expect(Progression.standing(points: -40, in: try Repo.gear()).level == 1)
    }

    @Test func gearArrivesInTheOrderOfTheLevels() throws {
        let file = try Repo.gear()
        #expect(Progression.gear(at: 100, in: file).map(\.id) == ["hard_hat"])
        #expect(Progression.gear(at: 650, in: file).map(\.id) == ["hard_hat", "vest", "boots"])
        #expect(Progression.gear(at: 4000, in: file).count == file.gear.count)
    }

    @Test func aCatchThatCrossesALevelHandsOverItsGear() throws {
        let file = try Repo.gear()
        #expect(Progression.newGear(from: 95, to: 125, in: file).map(\.id) == ["hard_hat"])
        #expect(Progression.newGear(from: 125, to: 155, in: file).isEmpty)
        #expect(Progression.newGear(from: 290, to: 620, in: file).map(\.id) == ["vest", "boots"])
    }

    @Test func theTwoUnlocksComeWithTheirGear() throws {
        let file = try Repo.gear()
        #expect(!Progression.has(unlock: "history", at: 2199, in: file))
        #expect(Progression.has(unlock: "history", at: 2200, in: file))
        #expect(!Progression.has(unlock: "wide_radius", at: 2999, in: file))
        #expect(Progression.has(unlock: "wide_radius", at: 3000, in: file))
        #expect(!Progression.has(unlock: "something_else", at: 99_999, in: file))
    }

    @Test func everyGearFactIsAFactOnFile() throws {
        let file = try Repo.gear()
        let facts = try Repo.facts()
        for gear in file.gear {
            if let id = gear.factId { #expect(facts.fact(id: id) != nil, "the fact \(id) of \(gear.id) is missing") }
        }
        #expect(facts.facts.allSatisfy { !$0.text.isEmpty && !$0.source.isEmpty && !$0.retrieved.isEmpty })
        #expect(facts.fact(id: nil) == nil)
    }
}
