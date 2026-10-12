import Foundation
import Testing
@testable import InfrastructureGO

@Suite("Who lives where")
struct WorldTests {
    let cast = [madeUpKeeper("frog", kind: "common", weight: 3), madeUpKeeper("puddle", kind: "common", weight: 1), madeUpKeeper("glub", kind: "uncommon"),
                madeUpKeeper("heron", kind: "rare"), madeUpKeeper("dragon", kind: "visitor")]

    func resident(_ site: Inlet, day: String = "2026-11-10", week: String = "2026-W46", cast: [Keeper]? = nil, grates: Int = 1) throws -> Keeper? {
        World.resident(of: site, grates: grates, day: day, week: week, keepers: cast ?? self.cast, kinds: try Repo.world().kinds)
    }

    @Test func aWeekBeginsOnMonday() throws {
        let days = try Repo.rules().days
        #expect(days.week(of: try instant("2026-10-11T12:00:00-04:00")) == "2026-W41", "a Sunday closes its week")
        #expect(days.week(of: try instant("2026-10-12T00:30:00-04:00")) == "2026-W42")
        #expect(days.week(of: try instant("2026-10-12T03:30:00+00:00")) == "2026-W41", "the week is the one in New York")
        #expect(days.week(of: try instant("2027-01-01T12:00:00-05:00")) == "2026-W53")
    }

    @Test func theKindsComeOutInTheirShares() throws {
        let sites = try drainsOfTheGame()
        let kinds = try sites.compactMap { try resident($0)?.kind }
        #expect(kinds.count == sites.count, "every drain of the game has a keeper")
        let share = { (kind: String) in Double(kinds.filter { $0 == kind }.count) / Double(kinds.count) }
        #expect(share("rare") > 0.015 && share("rare") < 0.05, "rare is \(share("rare"))")
        #expect(share("common") > 0.57 && share("common") < 0.69)
        #expect(share("uncommon") > 0.28 && share("uncommon") < 0.40)
        #expect(share("visitor") == 0, "a visitor never simply lives somewhere")
        let frogs = try sites.filter { try resident($0)?.id == "frog" }.count, puddles = try sites.filter { try resident($0)?.id == "puddle" }.count
        #expect(Double(frogs) / Double(puddles) > 2.2 && Double(frogs) / Double(puddles) < 4, "a keeper that weighs three times as much lives at about three times as many drains")
    }

    @Test func aDrainShowsTheSameKeeperAllDayAndAnotherOnOtherDays() throws {
        let sites = try drainsOfTheGame()
        #expect(try resident(sites[0]) == (try resident(sites[0])))
        let changed = try sites.prefix(200).filter { try resident($0, day: "2026-11-10")?.id != (try resident($0, day: "2026-11-11")?.id) }.count
        #expect(changed > 30, "the town is not the same every day")
    }

    @Test func aRareKeeperStaysAtItsDrainForTheWeek() throws {
        let kinds = try Repo.world().kinds
        let homes = try drainsOfTheGame().filter { World.isRareHome($0, week: "2026-W46", kinds: kinds) }
        #expect(homes.count >= 5)
        for home in homes {
            for day in ["2026-11-09", "2026-11-11", "2026-11-15"] { #expect(try resident(home, day: day)?.id == "heron") }
        }
        let nextWeek = try drainsOfTheGame().filter { World.isRareHome($0, week: "2026-W47", kinds: kinds) }
        #expect(Set(nextWeek.map(\.id)) != Set(homes.map(\.id)), "the rare homes move with the week")
    }

    @Test func aKeeperLivesOnlyInItsHabitat() throws {
        let campusOnly = [madeUpKeeper("frog", kind: "common"), madeUpKeeper("owl", kind: "common", weight: 5, zones: ["campus"]), madeUpKeeper("glub", kind: "uncommon", owners: ["County"])]
        let sites = try drainsOfTheGame()
        let owls = try sites.filter { try resident($0, cast: campusOnly)?.id == "owl" }
        #expect(!owls.isEmpty && owls.allSatisfy { $0.zone == "campus" })
        let glubs = try sites.filter { try resident($0, cast: campusOnly)?.id == "glub" }
        #expect(!glubs.isEmpty && glubs.allSatisfy { $0.owner == "County" })
        #expect(try sites.allSatisfy { try resident($0, cast: campusOnly) != nil }, "where no uncommon keeper fits, a common one lives")
        let site = sites[0]
        #expect(World.liking(campusOnly[1], for: site, grates: 1) == (site.zone == "campus" ? 5 : 0))
    }

    @Test func aKeeperThatLikesRowsOfGratesIsLikelierThere() throws {
        let rows = madeUpKeeper("crab", kind: "common", rows: 4)
        let site = try drainsOfTheGame()[0]
        #expect(World.liking(rows, for: site, grates: 3) == 4 * World.liking(rows, for: site, grates: 1))
    }

    @Test func everyKeeperOfTheFileHasDrainsToLiveAtInEveryZone() throws {
        let sites = try drainsOfTheGame(), keepers = try Repo.keepers(), kinds = try Repo.world().kinds
        for keeper in keepers where keeper.kind != "visitor" {
            for zone in ["west", "downtown", "campus"] {
                #expect(sites.contains { $0.zone == zone && World.liking(keeper, for: $0, grates: 1) > 0 }, "\(keeper.id) fits no drain in \(zone)")
            }
        }
        for keeper in keepers where keeper.kind == "common" {
            let homes = sites.filter { World.resident(of: $0, grates: 1, day: "2026-11-10", week: "2026-W46", keepers: keepers, kinds: kinds)?.id == keeper.id }
            #expect(homes.count >= 40, "\(keeper.id) lives at \(homes.count) drains")
        }
    }

    @Test func theGameSinglesOutNoDrainOnTheStatesRoads() throws {
        let rule = try Repo.world().invites
        let sites = try drainsOfTheGame()
        let invited = sites.filter { World.invites($0, rule: rule) }
        #expect(invited.count < sites.count && invited.count > 500)
        #expect(invited.allSatisfy { $0.owner != "State" && $0.road != "State Road" && !$0.road.hasPrefix("FR ") })
        #expect(sites.contains { $0.road.hasPrefix("FR ") }, "the ramps of the highway are in the layer, which is why the rule exists")
    }

    @Test func theVisitorOfAWeekHasOneDrainInEveryZone() throws {
        let rule = try Repo.world().invites
        let invited = try drainsOfTheGame().filter { World.invites($0, rule: rule) }
        for zone in ["west", "downtown", "campus"] {
            let visit = try #require(World.visitor(zone: zone, week: "2026-W46", sites: invited, keepers: cast))
            #expect(visit.keeper.id == "dragon" && visit.site.zone == zone)
            #expect(World.visitor(zone: zone, week: "2026-W46", sites: invited, keepers: cast)?.site.id == visit.site.id)
        }
        let weeks = Set((40...52).compactMap { World.visitor(zone: "west", week: "2026-W\($0)", sites: invited, keepers: cast)?.site.id })
        #expect(weeks.count > 6, "the visitor comes to another drain in other weeks")
        #expect(World.visitor(zone: "west", week: "2026-W46", sites: invited, keepers: cast.filter { $0.kind != "visitor" }) == nil)
    }

    @Test func aKeeperThatSlippedAwayWaitsAWalkAway() throws {
        let store = try Repo.inlets(), world = try Repo.world()
        let from = try #require(store["in1375"])
        let others = store.nearbySites(from.coordinate, within: 400).filter { $0.head.id != from.id }
        let target = try #require(World.slipTarget(among: others, minM: world.slip.minM, maxM: world.slip.maxM))
        let walk = try #require(store.distance(from: from.coordinate, toSite: target.id))
        #expect(walk >= world.slip.minM && walk <= world.slip.maxM)
        #expect(others.filter { $0.distanceM >= world.slip.minM }.first?.head.id == target.id, "it is the nearest one that is far enough")
        #expect(World.slipTarget(among: others.filter { $0.distanceM < 30 }, minM: world.slip.minM, maxM: world.slip.maxM) == nil)
    }
}
