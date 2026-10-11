import Foundation
import Testing
@testable import InfrastructureGO

@Suite("The tier of a drain and the points of a catch")
struct SpawnRulesTests {
    @Test("the shared cases hold enough to mean something")
    func casesArePresent() {
        #expect(SpawnCases.shared.tierCases.count >= 26)
        #expect(SpawnCases.shared.pointsCases.count == 8)
        #expect(Set(SpawnCases.shared.tierCases.map(\.tier)) == [0, 1, 2, 3])
    }

    @Test("a shared tier case", arguments: SpawnCases.shared.tierCases)
    func tier(_ c: SpawnCases.TierCase) throws {
        let rules = try Repo.rules()
        let got = SpawnRules.tier(now: try instant(c.now), lastAnyAt: try c.lastAnyAt.map(instant), myLastAt: try c.myLastAt.map(instant),
                                  stormOpen: c.stormOpen, rules: rules)
        #expect(got.rawValue == c.tier)
    }

    @Test("a shared points case", arguments: SpawnCases.shared.pointsCases)
    func points(_ c: SpawnCases.PointsCase) throws {
        let tier = try #require(Tier(rawValue: c.tier))
        #expect(SpawnRules.points(tier: tier, greatCatch: c.greatCatch, rules: try Repo.rules()) == c.points)
    }

    @Test("an older last report never lowers the tier")
    func tierGrowsWithAge() throws {
        let rules = try Repo.rules()
        let now = try instant("2026-11-10T20:00:00Z")
        let seen = stride(from: 0.0, to: 20 * 24, by: 6).map { hours in
            SpawnRules.tier(now: now, lastAnyAt: now.addingTimeInterval(-hours * 3600), myLastAt: nil, stormOpen: false, rules: rules)
        }
        #expect(seen == seen.sorted())
        #expect(seen.first == .common && seen.last == .rare)
        #expect(seen.firstIndex(of: .uncommon) == 3 * 4)
        #expect(seen.firstIndex(of: .rare) == 14 * 4)
    }

    @Test("the day is the one in New York, whatever the phone's own timezone")
    func dayIsNewYorks() throws {
        let days = try Repo.rules().days
        #expect(days.day(of: try instant("2026-11-11T04:59:59Z")) == "2026-11-10")
        #expect(days.day(of: try instant("2026-11-11T05:00:00Z")) == "2026-11-11")
        #expect(days.day(of: try instant("2026-11-01T05:30:00Z")) == "2026-11-01")      // the first hour, still summer time
        #expect(days.day(of: try instant("2026-07-04T03:59:59Z")) == "2026-07-03")
    }
}

@Suite("The fence around a drain")
struct FenceTests {
    @Test func insideWithAGoodFix() throws {
        #expect(Fence.state(distanceM: 12, accuracyM: 5, rules: try Repo.rules()) == .inside(distanceM: 12))
    }

    @Test func theEdgeOfTheFenceIsInside() throws {
        let rules = try Repo.rules()
        #expect(Fence.state(distanceM: rules.fence.radiusM, accuracyM: rules.fence.maxAccuracyM, rules: rules) == .inside(distanceM: rules.fence.radiusM))
        #expect(Fence.state(distanceM: rules.fence.radiusM + 0.01, accuracyM: 5, rules: rules) == .walkCloser(distanceM: rules.fence.radiusM + 0.01))
    }

    @Test func nearWithARoughFixWaits() throws {
        #expect(Fence.state(distanceM: 12, accuracyM: 40, rules: try Repo.rules()) == .roughFix(accuracyM: 40))
    }

    @Test func farAwayIsToldToWalkEvenWithARoughFix() throws {
        #expect(Fence.state(distanceM: 180, accuracyM: 40, rules: try Repo.rules()) == .walkCloser(distanceM: 180))
    }

    @Test func noFixIsNoFix() throws {
        let rules = try Repo.rules()
        #expect(Fence.state(distanceM: nil, accuracyM: 5, rules: rules) == .noFix)
        #expect(Fence.state(distanceM: 12, accuracyM: nil, rules: rules) == .noFix)
        #expect(Fence.state(distanceM: 12, accuracyM: -1, rules: rules) == .noFix)       // the phone's way of saying the fix is invalid
    }

    @Test("the server's limit lies outside the fence, so an honest catch is never refused")
    func serverLimitIsWider() throws {
        let rules = try Repo.rules()
        #expect(rules.fence.serverMaxDistanceM >= rules.fence.radiusM + rules.fence.maxAccuracyM)
    }
}
