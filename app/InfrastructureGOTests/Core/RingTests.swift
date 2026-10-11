import Foundation
import Testing
@testable import InfrastructureGO

@Suite("The ring and the throw")
struct RingTests {
    @Test func theRingShrinksAndStartsAgain() throws {
        let ring = try Repo.rules().ring
        #expect(Ring.scale(elapsed: 0, rules: ring) == ring.startScale)
        #expect(abs(Ring.scale(elapsed: ring.periodS / 2, rules: ring) - (ring.startScale + ring.endScale) / 2) < 1e-9)
        #expect(Ring.scale(elapsed: ring.periodS * 0.999, rules: ring) < ring.endScale + 0.01)
        #expect(Ring.scale(elapsed: ring.periodS, rules: ring) == ring.startScale)
        #expect(abs(Ring.scale(elapsed: ring.periodS * 3.25, rules: ring) - Ring.scale(elapsed: ring.periodS * 0.25, rules: ring)) < 1e-9)
        #expect(Ring.scale(elapsed: -5, rules: ring) == ring.startScale)
    }

    @Test func theRingIsSmallEnoughForAGreatCatchForPartOfEveryTurn() throws {
        let rules = try Repo.rules()
        let steps = stride(from: 0.0, to: rules.ring.periodS, by: rules.ring.periodS / 1000)
        let share = Double(steps.filter { Ring.scale(elapsed: $0, rules: rules.ring) <= rules.greatCatch.ringScaleMax }.count) / 1000
        #expect(share > 0.1 && share < 0.4)
    }

    @Test func aStraightThrowAtASmallRingIsAGreatCatch() throws {
        let rules = try Repo.rules()
        let outcome = Throwing.outcome(throwNumber: 1, swipeDX: 0, swipeDY: -200, aimDX: 0, aimDY: -300, ringScale: 0.4, rules: rules)
        #expect(outcome == .hit(great: true))
    }

    @Test func theSameThrowAtALargeRingLandsWithoutTheBonus() throws {
        let rules = try Repo.rules()
        #expect(Throwing.outcome(throwNumber: 1, swipeDX: 0, swipeDY: -200, aimDX: 0, aimDY: -300, ringScale: 0.9, rules: rules) == .hit(great: false))
        #expect(Throwing.outcome(throwNumber: 1, swipeDX: 0, swipeDY: -200, aimDX: 0, aimDY: -300, ringScale: rules.greatCatch.ringScaleMax, rules: rules) == .hit(great: true))
    }

    @Test func aShortSwipeMisses() throws {
        let rules = try Repo.rules()
        #expect(Throwing.outcome(throwNumber: 1, swipeDX: 0, swipeDY: -(rules.throwing.minSwipePt - 1), aimDX: 0, aimDY: -300, ringScale: 0.4, rules: rules) == .miss)
        #expect(Throwing.outcome(throwNumber: 1, swipeDX: 0, swipeDY: -rules.throwing.minSwipePt, aimDX: 0, aimDY: -300, ringScale: 0.4, rules: rules) == .hit(great: true))
    }

    @Test func aSwipeBesideTheCreatureMisses() throws {
        let rules = try Repo.rules()
        let inside = (rules.throwing.aimToleranceDeg - 1) * .pi / 180
        let outside = (rules.throwing.aimToleranceDeg + 1) * .pi / 180
        #expect(Throwing.outcome(throwNumber: 1, swipeDX: 200 * sin(inside), swipeDY: -200 * cos(inside), aimDX: 0, aimDY: -300, ringScale: 0.9, rules: rules) == .hit(great: false))
        #expect(Throwing.outcome(throwNumber: 1, swipeDX: 200 * sin(outside), swipeDY: -200 * cos(outside), aimDX: 0, aimDY: -300, ringScale: 0.9, rules: rules) == .miss)
        #expect(Throwing.outcome(throwNumber: 2, swipeDX: 0, swipeDY: 200, aimDX: 0, aimDY: -300, ringScale: 0.4, rules: rules) == .miss)
    }

    @Test func aimIsTakenTowardsTheCreatureWhereverItSits() throws {
        let rules = try Repo.rules()
        #expect(Throwing.outcome(throwNumber: 1, swipeDX: -150, swipeDY: -150, aimDX: -200, aimDY: -200, ringScale: 0.9, rules: rules) == .hit(great: false))
        #expect(Throwing.outcome(throwNumber: 1, swipeDX: 150, swipeDY: -150, aimDX: -200, aimDY: -200, ringScale: 0.9, rules: rules) == .miss)
    }

    @Test func theSecondThrowCarriesNoBonus() throws {
        let rules = try Repo.rules()
        #expect(Throwing.outcome(throwNumber: 2, swipeDX: 0, swipeDY: -200, aimDX: 0, aimDY: -300, ringScale: 0.4, rules: rules) == .hit(great: false))
    }

    @Test func theLastThrowAlwaysLands() throws {
        let rules = try Repo.rules()
        #expect(rules.throwing.count == 3)
        #expect(Throwing.outcome(throwNumber: 3, swipeDX: 0, swipeDY: 5, aimDX: 0, aimDY: -300, ringScale: 0.4, rules: rules) == .hit(great: false))
        #expect(Throwing.outcome(throwNumber: 3, swipeDX: 0, swipeDY: 0, aimDX: 0, aimDY: 0, ringScale: 1, rules: rules) == .hit(great: false))
    }

    @Test func theSameSwipeAlwaysComesToTheSameResult() throws {
        let rules = try Repo.rules()
        let results = (0..<50).map { _ in Throwing.outcome(throwNumber: 1, swipeDX: 30, swipeDY: -180, aimDX: 10, aimDY: -250, ringScale: 0.44, rules: rules) }
        #expect(Set(results.map { "\($0)" }).count == 1)
    }
}
