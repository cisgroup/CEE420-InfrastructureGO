import Foundation
import Testing
@testable import InfrastructureGO

@Suite("Distances, directions and polygons")
struct GeoTests {
    let nassauHall = Coordinate(lon: -74.6593, lat: 40.3487)

    @Test func aHundredthOfADegreeNorthIsAboutElevenHundredMetres() {
        let north = Coordinate(lon: nassauHall.lon, lat: nassauHall.lat + 0.01)
        #expect(abs(Geo.distance(nassauHall, north) - 1110.4) < 0.5)
        #expect(Geo.bearing(from: nassauHall, to: north) == 0)
    }

    @Test func aHundredthOfADegreeEastIsShorterAtThisLatitude() {
        let east = Coordinate(lon: nassauHall.lon + 0.01, lat: nassauHall.lat)
        #expect(abs(Geo.distance(nassauHall, east) - 849.5) < 0.5)
        #expect(abs(Geo.bearing(from: nassauHall, to: east) - 90) < 1e-9)
    }

    @Test func bearingsRunClockwiseFromNorth() {
        let south = Coordinate(lon: nassauHall.lon, lat: nassauHall.lat - 0.001)
        let west = Coordinate(lon: nassauHall.lon - 0.001, lat: nassauHall.lat)
        #expect(abs(Geo.bearing(from: nassauHall, to: south) - 180) < 1e-9)
        #expect(abs(Geo.bearing(from: nassauHall, to: west) - 270) < 1e-9)
        #expect(Geo.distance(nassauHall, nassauHall) == 0)
    }

    @Test func distanceIsTheSameBothWays() {
        let other = Coordinate(lon: -74.6727, lat: 40.3568)
        #expect(Geo.distance(nassauHall, other) == Geo.distance(other, nassauHall))
        #expect(abs(abs(Geo.bearing(from: nassauHall, to: other) - Geo.bearing(from: other, to: nassauHall)) - 180) < 1e-9)
    }

    @Test("the arrow turns the short way round", arguments: [(0.0, 90.0, 90.0), (350.0, 10.0, 20.0), (10.0, 350.0, -20.0), (270.0, 0.0, 90.0), (0.0, 180.0, 180.0), (90.0, 90.0, 0.0), (359.0, 1.0, 2.0)])
    func turn(heading: Double, bearing: Double, expected: Double) {
        #expect(abs(Geo.turn(fromHeading: heading, toBearing: bearing) - expected) < 1e-9)
    }

    @Test func aPointInASquare() {
        let square = [Coordinate(lon: 0, lat: 0), Coordinate(lon: 1, lat: 0), Coordinate(lon: 1, lat: 1), Coordinate(lon: 0, lat: 1), Coordinate(lon: 0, lat: 0)]
        #expect(Geo.contains(ring: square, Coordinate(lon: 0.5, lat: 0.5)))
        #expect(!Geo.contains(ring: square, Coordinate(lon: 1.5, lat: 0.5)))
        #expect(!Geo.contains(ring: square, Coordinate(lon: 0.5, lat: -0.1)))
        #expect(!Geo.contains(ring: Array(square.prefix(2)), Coordinate(lon: 0.5, lat: 0.5)))
    }

    @Test func aHoleIsOutside() {
        let outer = [Coordinate(lon: 0, lat: 0), Coordinate(lon: 4, lat: 0), Coordinate(lon: 4, lat: 4), Coordinate(lon: 0, lat: 4), Coordinate(lon: 0, lat: 0)]
        let hole = [Coordinate(lon: 1, lat: 1), Coordinate(lon: 3, lat: 1), Coordinate(lon: 3, lat: 3), Coordinate(lon: 1, lat: 3), Coordinate(lon: 1, lat: 1)]
        #expect(Geo.contains(polygon: [outer, hole], Coordinate(lon: 0.5, lat: 0.5)))
        #expect(!Geo.contains(polygon: [outer, hole], Coordinate(lon: 2, lat: 2)))
        #expect(!Geo.contains(polygon: [], Coordinate(lon: 2, lat: 2)))
    }

    @Test func aShapeWithANotch() {
        let notched = [Coordinate(lon: 0, lat: 0), Coordinate(lon: 4, lat: 0), Coordinate(lon: 4, lat: 4), Coordinate(lon: 2, lat: 1), Coordinate(lon: 0, lat: 4), Coordinate(lon: 0, lat: 0)]
        #expect(Geo.contains(ring: notched, Coordinate(lon: 0.5, lat: 2)))
        #expect(!Geo.contains(ring: notched, Coordinate(lon: 2, lat: 3)))
        #expect(Geo.contains(ring: notched, Coordinate(lon: 3.5, lat: 2)))
    }
}
