import Foundation
import Testing
@testable import InfrastructureGO

@Suite("The detector")
struct DetectorTests {
    let here = Coordinate(lon: -74.672675, lat: 40.356792)

    /// A place a number of metres east of the player.
    func east(_ metres: Double) -> Coordinate {
        Coordinate(lon: here.lon + metres / 84_800, lat: here.lat)
    }

    func read(_ things: [Findable], from place: Coordinate? = nil, inPlay: Bool = true, justLooked: Coordinate? = nil, hunted: String? = nil) -> Reading {
        Detector.read(here: place ?? here, inPlay: inPlay, things: things, rangeM: 150, fenceM: 20, justLooked: justLooked, quietM: 30, hunted: hunted)
    }

    @Test func withoutAPositionItSaysSo() {
        #expect(Detector.read(here: nil, inPlay: true, things: [], rangeM: 150, fenceM: 20).state == .noFix)
    }

    @Test func nothingWithinReachIsQuietAndOutsideThePlayAreaItSaysThat() {
        let far = [Findable(site: "a", at: east(400), kind: "common")]
        #expect(read(far).state == .quiet && read(far).strength == 0)
        #expect(read(far, inPlay: false).state == .outside)
        #expect(read([]).site == nil)
    }

    @Test func theReadingGrowsAsThePlayerNears() {
        let thing = [Findable(site: "a", at: east(140), kind: "common")]
        let strengths = [0.0, 40, 90, 125].map { read(thing, from: east($0)).strength }
        #expect(strengths == strengths.sorted() && strengths[0] > 0 && strengths[3] > 0.8)
        let reading = read(thing)
        #expect(reading.state == .signal && reading.site == "a")
        #expect(abs((reading.bearing ?? 0) - 90) < 1 && abs((reading.distanceM ?? 0) - 140) < 2)
    }

    @Test func atADrainItSaysCloseEnough() {
        #expect(read([Findable(site: "a", at: east(12), kind: nil)]).state == .atDrain)
        #expect(read([Findable(site: "a", at: east(21), kind: nil)]).state == .signal)
    }

    @Test func theNearestThingIsMeant() {
        let things = [Findable(site: "far", at: east(120), kind: nil), Findable(site: "near", at: east(60), kind: "rare")]
        #expect(read(things).site == "near" && read(things).kind == "rare")
    }

    @Test func thePairOfTheDrainJustLookedAtIsPassedOver() {
        let looked = east(5)
        let things = [Findable(site: "pair", at: east(16), kind: nil), Findable(site: "next", at: east(110), kind: nil)]
        #expect(read(things, justLooked: looked).site == "next")
        #expect(read(things).site == "pair", "without a look just taken the pair is the nearest thing")
    }

    @Test func aHuntedKeeperIsFoundFromTwiceAsFar() {
        let things = [Findable(site: "rare", at: east(260), kind: "rare")]
        #expect(read(things).state == .quiet)
        let hunting = read(things, hunted: "rare")
        #expect(hunting.state == .signal && hunting.site == "rare" && hunting.strength > 0)
    }

    @Test func aStrongerReadingTicksFaster() throws {
        let rule = try Repo.world().detector
        let gaps = [0.0, 0.3, 0.6, 1.0].map { Detector.tickEvery(strength: $0, rule: rule) }
        #expect(gaps == gaps.sorted(by: >))
        #expect(gaps[0] == rule.slowTickS && abs(gaps[3] - rule.fastTickS) < 1e-9)
    }
}
