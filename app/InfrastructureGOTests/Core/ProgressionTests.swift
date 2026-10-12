import Foundation
import Testing
@testable import InfrastructureGO

@Suite("Levels and gear in parts")
struct ProgressionTests {
    @Test func aNewPlayerIsAnApprenticeAtLevelOne() throws {
        let standing = Progression.standing(points: 0, in: try Repo.gear())
        #expect(standing.level == 1 && standing.rank == "Apprentice" && standing.pointsToNext == 100 && standing.fraction == 0)
    }

    @Test("a level is reached at exactly its points", arguments: [(99, 1), (100, 2), (299, 2), (300, 3), (599, 3), (600, 4), (1000, 5), (2199, 6), (2200, 7), (3999, 8), (4000, 9), (99_999, 9)])
    func level(points: Int, level: Int) throws {
        #expect(Progression.standing(points: points, in: try Repo.gear()).level == level)
    }

    @Test func theRanksClimbFromApprenticeToTownPlanner() throws {
        let gear = try Repo.gear()
        #expect(Progression.standing(points: 600, in: gear).rank == "Crew member")
        #expect(Progression.standing(points: 4000, in: gear).rank == "Town planner")
        #expect(Progression.standing(points: 4000, in: gear).pointsToNext == nil && Progression.standing(points: 4000, in: gear).fraction == 1)
        #expect(Progression.standing(points: 200, in: gear).fraction == 0.5)
        #expect(Progression.standing(points: -5, in: gear).level == 1)
    }

    @Test func theHardHatIsThereFromTheStartAndPricesRise() throws {
        let gear = try Repo.gear()
        #expect(Gear.owned(parts: [:], in: gear).map(\.id) == ["hard_hat"])
        #expect(gear.pieces.map(\.parts) == [0, 3, 6, 10, 15, 20, 26, 32, 40])
        #expect(Gear.missing(parts: [:], in: gear) == 152)
        #expect(Set(gear.pieces.map(\.id)).count == gear.pieces.count)
    }

    @Test func partsFillOnePieceAtATimeAndRunOverIntoTheNext() throws {
        let gear = try Repo.gear()
        var parts: [String: Int] = [:]
        let first = Gear.add(3, to: &parts, pinned: nil, in: gear)
        #expect(first.filled.map(\.piece.id) == ["boots"] && first.filled[0].finished && first.over == 0)
        #expect(Gear.opens("wide_veil", parts: parts, in: gear) && !Gear.opens("long_range", parts: parts, in: gear))
        let second = Gear.add(8, to: &parts, pinned: nil, in: gear)
        #expect(second.filled.map(\.piece.id) == ["long_coil", "lamp"])
        #expect(second.filled[0].finished && !second.filled[1].finished && second.filled[1].after == 2)
        #expect(Gear.next(parts: parts, pinned: nil, in: gear)?.id == "lamp")
    }

    @Test func aPinnedPieceIsFilledFirstAndAFinishedPinIsPassedOver() throws {
        let gear = try Repo.gear()
        var parts: [String: Int] = [:]
        let pinned = Gear.add(2, to: &parts, pinned: "lamp", in: gear)
        #expect(pinned.filled.map(\.piece.id) == ["lamp"] && parts["boots"] == nil)
        parts["lamp"] = 10
        #expect(Gear.next(parts: parts, pinned: "lamp", in: gear)?.id == "boots")
        #expect(Gear.next(parts: parts, pinned: "no such piece", in: gear)?.id == "boots")
    }

    @Test func aFinishedPieceTakesNoMorePartsAndPartsWithoutAPlaceAreLeftOver() throws {
        let gear = try Repo.gear()
        var parts: [String: Int] = [:]
        let all = Gear.add(152, to: &parts, pinned: nil, in: gear)
        #expect(all.over == 0 && Gear.owned(parts: parts, in: gear).count == gear.pieces.count && Gear.missing(parts: parts, in: gear) == 0)
        for piece in gear.pieces { #expect((parts[piece.id] ?? 0) == piece.parts) }
        let more = Gear.add(4, to: &parts, pinned: "boots", in: gear)
        #expect(more.filled.isEmpty && more.over == 4)
        #expect(Gear.next(parts: parts, pinned: nil, in: gear) == nil)
    }
}
