import Foundation
import Testing
@testable import InfrastructureGO

@Suite("The throw and its judge")
struct CatchTests {
    let frog = Keeper.Timing(watchS: [1.8, 3.0], tellS: 0.8, airS: 0.5, settleS: 0.6, hideEvery: 0, hideS: 0, feintEvery: 0)

    func rule() throws -> WorldRules.CatchRule { try Repo.world().catching }

    /// The first moment of a phase in a timeline, and its beat.
    func first(_ phase: Phase, in line: Timeline, leaving: Bool? = nil) throws -> Beat {
        try #require(line.beats.first { $0.phase == phase && (leaving == nil || ($0.next != $0.spot) == leaving) })
    }

    @Test func theSameSeedGivesTheSameBehaviour() {
        #expect(Timeline.make(seed: "in0001|2026-11-10|1", timing: frog) == Timeline.make(seed: "in0001|2026-11-10|1", timing: frog))
        #expect(Timeline.make(seed: "in0001|2026-11-10|1", timing: frog) != Timeline.make(seed: "in0002|2026-11-10|1", timing: frog))
    }

    @Test func aKeeperWatchesTellsLeavesAndSettlesInThatOrder() {
        let line = Timeline.make(seed: "order", timing: frog)
        #expect(line.beats.prefix(4).map(\.phase) == [.watch, .tell, .air, .settle])
        for (a, b) in zip(line.beats, line.beats.dropFirst()) { #expect(a.end == b.start) }
        let air = line.beats.filter { $0.phase == .air }
        #expect(air.allSatisfy { $0.next != $0.spot && (0..<3).contains($0.next) }, "a hop goes to another place on the grate")
        #expect(line.length >= 90)
    }

    @Test func pastItsEndTheBehaviourStartsOver() {
        let line = Timeline.make(seed: "again", timing: frog, seconds: 20)
        let beat = line.beat(at: line.length + 1.0)
        #expect(beat.phase == line.beat(at: 1.0).phase && beat.start >= line.length)
        #expect(line.beat(at: -5).start == 0)
    }

    @Test("every keeper of the file sits on the grate for most of the time")
    func keepersSitMostOfTheTime() throws {
        let share = try rule().sittingShare
        for keeper in try Repo.keepers() {
            let line = Timeline.make(seed: "share|\(keeper.id)", timing: keeper.timing)
            #expect(line.sittingShare >= share, "\(keeper.id) sits \(line.sittingShare) of the time")
        }
        let restless = Keeper.Timing(watchS: [0.3, 0.4], tellS: 0.2, airS: 1.5, settleS: 0.2, hideEvery: 1, hideS: 2, feintEvery: 0)
        #expect(Timeline.make(seed: "restless", timing: restless).sittingShare < share, "a keeper that is mostly away is caught by this check")
    }

    @Test("an aimed throw at a sitting keeper wins it, at 200 moments along every keeper's behaviour")
    func aSittingKeeperIsAlwaysWon() throws {
        let rule = try rule()
        for keeper in try Repo.keepers() {
            let line = Timeline.make(seed: "fair|\(keeper.id)", timing: keeper.timing)
            var sitting = 0
            for k in 0..<200 {
                let moment = line.length * Double(k) / 200
                let beat = line.beat(at: moment)
                guard beat.phase == .watch || beat.phase == .tell || beat.phase == .settle else { continue }
                sitting += 1
                #expect(Judge.judge(release: moment, timeline: line, aim: .keeper, swipePt: 200, rule: rule) == .caught)
            }
            #expect(sitting >= 120)
        }
    }

    @Test func readingTheTellIsTheMasteredCatch() throws {
        let rule = try rule()
        let line = Timeline.make(seed: "tell", timing: frog)
        let tell = try first(.tell, in: line)
        let moment = (tell.start + tell.end) / 2
        #expect(Judge.judge(release: moment, timeline: line, aim: .patch, swipePt: 200, rule: rule) == .mastered)
        #expect(Judge.judge(release: moment, timeline: line, aim: .keeper, swipePt: 200, rule: rule) == .caught, "it is still on the grate and stays for the marker")
    }

    @Test func aThrowAtThePlaceAKeeperHasLeftIsAMiss() throws {
        let rule = try rule()
        let line = Timeline.make(seed: "air", timing: frog)
        let air = try first(.air, in: line)
        #expect(Judge.judge(release: air.start + 0.05, timeline: line, aim: .keeper, swipePt: 200, rule: rule) == .gone)
        #expect(Judge.judge(release: air.start + 0.05, timeline: line, aim: .patch, swipePt: 200, rule: rule) == .mastered, "the marker is on the patch before the keeper lands")
        #expect(Judge.judge(release: air.end - 0.01, timeline: line, aim: .patch, swipePt: 200, rule: rule) == .caught, "the keeper is down before the marker arrives")
        #expect(Judge.judge(release: air.start + 0.05, timeline: line, aim: .keeper, swipePt: 200, rule: rule, easy: true) == .caught)
    }

    @Test func aKeeperUnderTheGrateCannotBeWon() throws {
        let rule = try rule()
        let shy = Keeper.Timing(watchS: [2, 2], tellS: 0.5, airS: 0.4, settleS: 0.5, hideEvery: 1, hideS: 1.0, feintEvery: 0)
        let line = Timeline.make(seed: "shy", timing: shy)
        let hidden = try first(.hidden, in: line)
        #expect(Judge.judge(release: hidden.start + 0.1, timeline: line, aim: .keeper, swipePt: 200, rule: rule) == .gone)
        #expect(Judge.judge(release: hidden.start + 0.1, timeline: line, aim: .keeper, swipePt: 200, rule: rule, easy: true) == .caught)
    }

    @Test func aFeintIsATellWithoutAHop() throws {
        let rule = try rule()
        let sly = Keeper.Timing(watchS: [1.5, 1.5], tellS: 0.6, airS: 0.4, settleS: 0.4, hideEvery: 0, hideS: 0, feintEvery: 2)
        let line = Timeline.make(seed: "sly", timing: sly)
        let feint = try first(.tell, in: line, leaving: false)
        #expect(Judge.judge(release: feint.start + 0.1, timeline: line, aim: .patch, swipePt: 200, rule: rule) == .caught, "nothing lands anywhere, so there is nothing to master")
        #expect(line.beats.contains { $0.phase == .tell && $0.next != $0.spot })
    }

    @Test func aShortSwipeAndAWideOneAreMisses() throws {
        let rule = try rule()
        let line = Timeline.sitting()
        #expect(Judge.judge(release: 1, timeline: line, aim: .keeper, swipePt: rule.minSwipePt - 1, rule: rule) == .short)
        #expect(Judge.judge(release: 1, timeline: line, aim: .nothing, swipePt: 200, rule: rule) == .wide)
        #expect(Judge.judge(release: 1, timeline: line, aim: .keeper, swipePt: rule.minSwipePt, rule: rule) == .caught)
        #expect(Throw.short.isMiss && Throw.wide.isMiss && Throw.gone.isMiss && !Throw.caught.isMiss && !Throw.mastered.isMiss)
    }

    @Test func theFirstMeetingsKeeperOnlySits() throws {
        let line = Timeline.sitting()
        #expect(line.sittingShare == 1)
        for moment in stride(from: 0.0, to: 600, by: 7.3) { #expect(line.beat(at: moment).phase == .watch) }
    }

    @Test func aSwipeMeansWhatItPointsAtMoreClosely() {
        // The marker rests at the bottom middle, the keeper sits straight above it and the patch to the right.
        let aim = { (dx: Double, dy: Double, patch: Bool, tolerance: Double) in
            Judge.aim(swipeDX: dx, swipeDY: dy, restX: 200, restY: 700, keeperX: 200, keeperY: 480, patch: patch ? (x: 310, y: 480) : nil, toleranceDeg: tolerance)
        }
        #expect(aim(0, -150, true, 25) == .keeper)
        #expect(aim(75, -150, true, 25) == .patch)
        #expect(aim(75, -150, false, 25) == .nothing, "26 degrees off with nothing else to mean")
        #expect(aim(75, -150, false, 35) == .keeper, "the wide marker forgives it")
        #expect(aim(-150, -20, true, 25) == .nothing)
        #expect(aim(0, 150, true, 25) == .nothing, "a swipe downward points at nothing")
    }
}
