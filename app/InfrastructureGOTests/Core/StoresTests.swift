import Foundation
import Testing
@testable import InfrastructureGO

/// The counts the pipeline wrote beside the files, so that the app's bundle is checked against the same numbers.
nonisolated struct InletSummary: Decodable {
    nonisolated struct ZoneCount: Decodable {
        let inlets: Int
        let playable: Int
        let sites: Int
        let playableSites: Int
    }

    let layerRows: Int
    let inlets: Int
    let collapsedRows: Int
    let sites: Int
    let sitesOfMoreThanOneInlet: Int
    let zones: [String: ZoneCount]
    let playable: Int
    let playableSites: Int

    static func read() throws -> InletSummary {
        try GameData.decoder.decode(InletSummary.self, from: Repo.data("data/inlets/summary.json"))
    }
}

@Suite("The bundled drains and zones")
struct StoresTests {
    @Test func theBundleHoldsEveryDrainThePipelineCounted() throws {
        let store = try Repo.inlets()
        let summary = try InletSummary.read()
        #expect(store.inlets.count == summary.inlets)
        #expect(store.inlets.reduce(0) { $0 + $1.dup } == summary.collapsedRows)
        #expect(store.inlets.count + summary.collapsedRows == summary.layerRows)
        #expect(Set(store.inlets.map(\.id)).count == store.inlets.count)
        #expect(!store.source.isEmpty && !store.licence.isEmpty && store.retrieved == "2026-09-11")
    }

    @Test func aDrainIsFoundByItsId() throws {
        let store = try Repo.inlets()
        let first = try #require(store["in0001"])
        #expect(first.id == "in0001" && first == store.inlets[0])
        #expect(store["in9999"] == nil)
    }

    @Test func aRowOfGratesIsOneSite() throws {
        let store = try Repo.inlets()
        let summary = try InletSummary.read()
        #expect(store.heads.count == summary.sites)
        #expect(store.heads.allSatisfy { $0.isSiteHead })
        #expect(store.heads.filter { store.members(ofSite: $0.id).count > 1 }.count == summary.sitesOfMoreThanOneInlet)
        #expect(store.inlets.reduce(0) { $0 + (store.members(ofSite: $1.site).contains($1) ? 1 : 0) } == store.inlets.count)
        let pardoe = store.members(ofSite: "in1342")       // the three grates in a row that the first photographs show
        #expect(pardoe.map(\.id) == ["in1342", "in1343", "in1344"])
        #expect(pardoe.allSatisfy { $0.road == "Pardoe Road" && $0.zone == "west" })
        let last = try #require(pardoe.last)
        #expect(store.head(of: last).id == "in1342" && !last.isSiteHead)
        #expect(store.members(ofSite: "in9999").isEmpty)
    }

    @Test func nearbySitesComeNearestFirstAndWithinTheRadius() throws {
        let store = try Repo.inlets()
        let mountainAvenue = Coordinate(lon: -74.672675, lat: 40.356792)       // where the first photograph was taken
        let near = store.nearbySites(mountainAvenue, within: 60)
        #expect(near.count >= 3)
        #expect(near.map(\.distanceM) == near.map(\.distanceM).sorted())
        #expect(near.allSatisfy { $0.distanceM <= 60 && $0.bearing >= 0 && $0.bearing < 360 && $0.head.isSiteHead })
        #expect(near.first?.head.road == "Mountain Avenue")
        #expect(store.nearbySites(mountainAvenue, within: 0.5).isEmpty)
        let everything = store.inlets.filter { Geo.distance(mountainAvenue, $0.coordinate) <= 60 }
        #expect(Set(everything.map(\.site)) == Set(near.map(\.head.id)))
    }

    @Test func aSiteIsAsNearAsItsNearestGrate() throws {
        let store = try Repo.inlets()
        let far = try #require(store["in1344"])       // the last grate of the row on Pardoe Road
        let standingOnIt = store.nearbySites(far.coordinate, within: 30)
        #expect(standingOnIt.first?.head.id == "in1342" && standingOnIt.first?.grates == 3)
        #expect(standingOnIt.first?.distanceM == 0)
        #expect(store.distance(from: far.coordinate, toSite: "in1342") == 0)
        #expect(store.distance(from: far.coordinate, toSite: "in9999") == nil)
        #expect(standingOnIt.filter { $0.head.site == "in1342" }.count == 1, "a row of grates is listed once")
    }

    @Test func nothingIsNearInTheMiddleOfTheOcean() throws {
        #expect(try Repo.inlets().nearbySites(Coordinate(lon: -40, lat: 40), within: 500).isEmpty)
    }

    @Test func siblingsAreTheOtherSitesCloseBy() throws {
        let store = try Repo.inlets()
        let rules = try Repo.rules()
        let siblings = store.siblingSites(of: "in1342", within: rules.fence.siblingRadiusM)
        #expect(!siblings.isEmpty, "the row on Pardoe Road has other drains within reach")
        #expect(siblings.allSatisfy { $0.head.site != "in1342" && $0.distanceM <= rules.fence.siblingRadiusM && $0.head.isSiteHead })
        #expect(Set(siblings.map(\.head.id)).count == siblings.count)
        let paired = store.heads.filter { !store.siblingSites(of: $0.id, within: rules.fence.siblingRadiusM).isEmpty }.count
        #expect(Double(paired) / Double(store.heads.count) > 0.4, "a large share of all drains have another within reach, which is why a report asks which one it was")
    }

    @Test func aBundleThatMiscountsRepeatsAnIdOrNamesAMissingSiteIsRefused() throws {
        let one = #"{"id":"in0001","lon":0,"lat":0,"owner":"","road":"","type":"","grate":"","dup":0,"site":"in0001","zone":""}"#
        let miscounted = Data(#"{"source":"s","licence":"l","retrieved":"r","count":2,"inlets":[\#(one)]}"#.utf8)
        #expect(throws: InletStore.Problem.countDiffers(stated: 2, found: 1)) { try InletStore(json: miscounted) }
        let repeated = Data(#"{"source":"s","licence":"l","retrieved":"r","count":2,"inlets":[\#(one),\#(one)]}"#.utf8)
        #expect(throws: InletStore.Problem.repeatedId("in0001")) { try InletStore(json: repeated) }
        let orphan = #"{"id":"in0002","lon":0,"lat":0,"owner":"","road":"","type":"","grate":"","dup":0,"site":"in0007","zone":""}"#
        let headless = Data(#"{"source":"s","licence":"l","retrieved":"r","count":2,"inlets":[\#(one),\#(orphan)]}"#.utf8)
        #expect(throws: InletStore.Problem.siteWithoutHead("in0007")) { try InletStore(json: headless) }
    }

    @Test func theZonesAreTheThreeOfTheFirstSeason() throws {
        let zones = try Repo.zones()
        #expect(zones.zones.map(\.id) == ["west", "downtown", "campus"])
        #expect(zones.zone(id: "campus")?.owners.contains("Private") == true)
        #expect(zones.zone(id: "west")?.owners.contains("Private") == false)
        #expect(zones.zone(id: "nowhere") == nil)
    }

    @Test("the app's own polygon test puts every drain in the zone the pipeline gave it")
    func everyDrainLiesInItsZone() throws {
        let store = try Repo.inlets()
        let zones = try Repo.zones()
        let summary = try InletSummary.read()
        var disagreements: [String] = []
        for inlet in store.inlets where (zones.zone(containing: inlet.coordinate)?.id ?? "") != inlet.zone {
            disagreements.append(inlet.id)
        }
        #expect(disagreements.isEmpty, "these drains fall elsewhere: \(disagreements.prefix(5))")
        for zone in zones.zones {
            #expect(store.inlets.filter { $0.zone == zone.id }.count == summary.zones[zone.id]?.inlets)
        }
    }

    @Test func drainsCanBeCaughtWhereTheZoneIsOnAndAdmitsTheOwner() throws {
        let store = try Repo.inlets()
        let zones = try Repo.zones()
        let summary = try InletSummary.read()
        #expect(store.inlets.filter { zones.canBeCaught($0, on: "2026-10-12") }.count == summary.playable)
        #expect(store.heads.filter { zones.canBeCaught($0, on: "2026-10-12") }.count == summary.playableSites)
        #expect(store.inlets.filter { zones.canBeCaught($0, on: "2026-10-10") }.isEmpty, "the day before the zones open nothing can be caught")
        for zone in zones.zones {
            #expect(store.inlets.filter { $0.zone == zone.id && zones.canBeCaught($0, on: "2026-11-10") }.count == summary.zones[zone.id]?.playable)
            #expect(store.heads.filter { $0.zone == zone.id && zones.canBeCaught($0, on: "2026-11-10") }.count == summary.zones[zone.id]?.playableSites)
        }
        #expect(store.heads.allSatisfy { head in store.members(ofSite: head.id).allSatisfy { $0.zone == head.zone } }, "no zone edge cuts a row of grates in two")
        let privateDowntown = try #require(store.inlets.first { $0.zone == "downtown" && $0.owner == "Private" })
        #expect(!zones.canBeCaught(privateDowntown, on: "2026-11-10"))
        let privateCampus = try #require(store.inlets.first { $0.zone == "campus" && $0.owner == "Private" })
        #expect(zones.canBeCaught(privateCampus, on: "2026-11-10"))
        let outside = try #require(store.inlets.first { $0.zone.isEmpty })
        #expect(!zones.canBeCaught(outside, on: "2026-11-10"))
    }

    @Test func aZoneWithAnEndCloses() {
        let zone = Zone(id: "z", name: "Z", activeFrom: "2026-10-12", activeTo: "2026-12-07", owners: ["Municipality"], polygons: [])
        #expect(!zone.isActive(on: "2026-10-11") && zone.isActive(on: "2026-10-12") && zone.isActive(on: "2026-12-07") && !zone.isActive(on: "2026-12-08"))
    }

    @Test func aZonesFileWithAnUnknownShapeIsRefused() {
        let line = Data(#"{"features":[{"properties":{"id":"z","name":"Z","active_from":"2026-10-12","active_to":null,"owners":[]},"geometry":{"type":"LineString","coordinates":[[0,0],[1,1]]}}]}"#.utf8)
        #expect(throws: ZoneStore.Problem.unknownGeometry("LineString")) { try ZoneStore(geojson: line) }
    }

    @Test func aMultiPolygonZoneIsRead() throws {
        let multi = Data(#"{"features":[{"properties":{"id":"z","name":"Z","active_from":"2026-10-12","active_to":"2026-12-07","owners":["State"]},"geometry":{"type":"MultiPolygon","coordinates":[[[[0,0],[1,0],[1,1],[0,1],[0,0]]],[[[5,5],[6,5],[6,6],[5,6],[5,5]]]]}}]}"#.utf8)
        let zone = try #require(try ZoneStore(geojson: multi).zones.first)
        #expect(zone.contains(Coordinate(lon: 0.5, lat: 0.5)) && zone.contains(Coordinate(lon: 5.5, lat: 5.5)) && !zone.contains(Coordinate(lon: 3, lat: 3)))
        #expect(zone.activeTo == "2026-12-07")
    }

    @Test func theRulesFileReadsAsWritten() throws {
        let rules = try Repo.rules()
        #expect(rules.timezone == "America/New_York")
        #expect(rules.tiers.map(\.tier) == [0, 1, 2, 3])
        #expect(rules.tiers.map(\.points) == [2, 10, 20, 30])
        #expect(rules.fence.radiusM == 20 && rules.fence.serverMaxDistanceM == 50)
    }

    @Test func theWorldsNumbersReadAsWritten() throws {
        let world = try Repo.world()
        #expect(world.crateParts == [0, 1, 2, 3] && world.rungs == [1, 3, 7, 15])
        #expect(world.kinds.common + world.kinds.uncommon == 100 && world.kinds.rarePerHundred == 3)
        #expect(world.veil.openM < world.veil.bootsOpenM && world.detector.rangeM < world.detector.longRangeM)
        #expect(world.slip.minM > (try Repo.rules().fence.radiusM), "a keeper that slipped away waits outside the fence, so there is a walk")
        #expect(world.catching.misses == 3)
    }

    @Test func everyKeeperOfTheFileIsWhole() throws {
        let keepers = try Repo.keepers()
        #expect(Set(keepers.map(\.id)).count == keepers.count)
        #expect(keepers.first?.id == "frog" && keepers.first?.kind == "common", "the first keeper of every player is the frog")
        for keeper in keepers {
            #expect(Keeper.kinds.contains(keeper.kind))
            for role in ["idle", "tell", "leap", "land", "accept", "refuse", "goodbye"] {
                #expect(keeper.clips[role] != nil, "\(keeper.id) has no movement for \(role)")
            }
            #expect(keeper.heightM > 0.1 && keeper.heightM < 1 && keeper.weight > 0 && keeper.timing.watchS.count == 2)
            #expect(!keeper.credit.isEmpty && !keeper.keeps.isEmpty && !keeper.tellWord.isEmpty)
        }
    }
}
