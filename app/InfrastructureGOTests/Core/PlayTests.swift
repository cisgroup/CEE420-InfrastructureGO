import Foundation
import Testing
@testable import InfrastructureGO

@Suite("A catch from start to finish")
struct PlayTests {
    let now = try! instant("2026-11-10T15:00:00-05:00")

    func siteWithDemoHistory(_ wanted: ClosedRange<Int>) -> String {
        (1...400).map { String(format: "in%04d", $0) }.first { wanted.contains(SpeciesPicker.hashIndex("\($0)|demo world", count: 10)) }!
    }

    @Test func theMadeUpWorldHoldsEveryTier() throws {
        let rules = try Repo.rules()
        let heads = try Repo.inlets().heads
        let tiers = heads.map { Play.outlook(site: $0.id, progress: PlayerProgress(), stormOpen: false, now: now, rules: rules).tier }
        let share = { (tier: Tier) in Double(tiers.filter { $0 == tier }.count) / Double(tiers.count) }
        #expect(share(.rare) > 0.3 && share(.rare) < 0.5)
        #expect(share(.uncommon) > 0.2 && share(.uncommon) < 0.4)
        #expect(share(.common) > 0.2 && share(.common) < 0.4)
        #expect(share(.resting) == 0)
        #expect(DemoWorld.lastReport(site: "in0001", now: now) == DemoWorld.lastReport(site: "in0001", now: now))
    }

    @Test func aFirstCatchAtAnUncheckedDrainIsRareAndThenTheDrainRests() throws {
        let rules = try Repo.rules(), species = try Repo.species(), gear = try Repo.gear()
        let site = siteWithDemoHistory(0...3)
        let (result, grown) = Play.settle(site: site, greatCatch: true, progress: PlayerProgress(), stormOpen: false, now: now, rules: rules, species: species, gear: gear)
        #expect(result.tier == .rare && result.record.points == 35 && result.record.great)
        #expect(result.sentence == "35 points. Great catch. Nobody has checked this drain yet.")
        #expect(result.species?.tier == 3 && result.record.species == result.species?.id)
        #expect(grown.points == 35 && grown.catches.count == 1 && result.before.level == 1)
        let later = now.addingTimeInterval(3600)
        #expect(Play.outlook(site: site, progress: grown, stormOpen: false, now: later, rules: rules).tier == .resting)
        let (again, twice) = Play.settle(site: site, greatCatch: true, progress: grown, stormOpen: false, now: later, rules: rules, species: species, gear: gear)
        #expect(again.tier == .resting && again.record.points == 2 && !again.record.great && again.species == nil)
        #expect(again.sentence == "2 points. You already caught here today.")
        #expect(twice.points == 37)
        let tomorrow = now.addingTimeInterval(86_400)
        #expect(Play.outlook(site: site, progress: twice, stormOpen: false, now: tomorrow, rules: rules).tier == .common, "my own catch of yesterday makes the drain common")
    }

    @Test func theSentenceSaysWhyADrainIsWorthWhatItIs() throws {
        let rules = try Repo.rules()
        let six = Play.outlook(site: siteWithDemoHistory(4...6), progress: PlayerProgress(), stormOpen: false, now: now, rules: rules)
        #expect(six.tier == .uncommon && six.points == 20 && six.sentence == "This drain was last checked 6 days ago.")
        let one = Play.outlook(site: siteWithDemoHistory(7...9), progress: PlayerProgress(), stormOpen: false, now: now, rules: rules)
        #expect(one.tier == .common && one.points == 10 && one.sentence == "This drain was checked yesterday. A second look still helps.")
        let storm = Play.outlook(site: siteWithDemoHistory(7...9), progress: PlayerProgress(), stormOpen: true, now: now, rules: rules)
        #expect(storm.tier == .rare && storm.sentence == "A storm window is open, so every drain is rare.")
        #expect(Words.why(tier: .rare, lastAnyAt: now.addingTimeInterval(-16 * 86_400), stormOpen: false, now: now) == "Nobody has checked this drain in 16 days.")
    }

    @Test func aCatchThatCrossesALevelHandsOverGear() throws {
        let rules = try Repo.rules(), species = try Repo.species(), gear = try Repo.gear()
        var progress = PlayerProgress()
        progress.catches.append(CatchRecord(id: UUID(), site: "in9001", species: "green_frog", tier: 1, points: 80, great: false, at: now.addingTimeInterval(-86_400)))
        let (result, grown) = Play.settle(site: siteWithDemoHistory(0...3), greatCatch: false, progress: progress, stormOpen: false, now: now, rules: rules, species: species, gear: gear)
        #expect(result.before.level == 1 && result.after.level == 2 && grown.points == 110)
        #expect(result.newGear.map(\.id) == ["hard_hat"])
    }

    @Test func progressCountsWhatWasCaught() throws {
        let days = try Repo.rules().days
        var progress = PlayerProgress()
        #expect(progress.points == 0 && progress.lastCatch(at: "in0001") == nil && progress.count(of: "green_frog") == 0)
        progress.catches = [
            CatchRecord(id: UUID(), site: "in0001", species: "green_frog", tier: 1, points: 10, great: false, at: now.addingTimeInterval(-90_000)),
            CatchRecord(id: UUID(), site: "in0002", species: "green_frog", tier: 1, points: 15, great: true, at: now.addingTimeInterval(-600)),
            CatchRecord(id: UUID(), site: "in0002", species: nil, tier: 0, points: 2, great: false, at: now),
        ]
        #expect(progress.points == 27 && progress.count(of: "green_frog") == 2)
        #expect(progress.lastCatch(at: "in0002") == now && progress.firstCatch(of: "green_frog") == now.addingTimeInterval(-90_000))
        #expect(progress.drains(on: "2026-11-10", days: days) == 1 && progress.drains(on: "2026-11-09", days: days) == 1)
        let copy = try JSONDecoder().decode(PlayerProgress.self, from: JSONEncoder().encode(progress))
        #expect(copy == progress)
    }

    @Test func theWordsArePlainAndCarryNoDash() throws {
        let sentences = [Words.name(of: .rare), Words.ago(now.addingTimeInterval(-100), now: now), Words.ago(now.addingTimeInterval(-90_000), now: now),
                         Words.ago(now.addingTimeInterval(-5 * 86_400), now: now), Words.distance(34.4), Words.distance(1530),
                         Words.fence(.noFix), Words.fence(.walkCloser(distanceM: 34.4)), Words.fence(.roughFix(accuracyM: 40)), Words.fence(.inside(distanceM: 3)),
                         Words.grates(1), Words.grates(2), Words.grates(3), Words.grates(5)]
        #expect(sentences == ["Rare", "today", "yesterday", "5 days ago", "34 m", "1.5 km", "Waiting for your position.", "Walk closer, 34 m to go.",
                              "GPS is rough here, wait a moment.", "You are at the drain.", "One grate.", "Two grates in a row.", "Three grates in a row.", "5 grates in a row."])
        #expect(Words.count(1, "drain", "drains") == "1 drain" && Words.count(0, "drain", "drains") == "0 drains" && Words.count(2, "catch", "catches") == "2 catches")
        for tier in Tier.allCases {
            let text = Words.why(tier: tier, lastAnyAt: now.addingTimeInterval(-86_400), stormOpen: false, now: now)
            #expect(!text.contains(" - ") && !text.contains("\u{2014}") && !text.contains("\u{2013}") && text.hasSuffix("."))
        }
    }
}
