import Foundation

/// A position on WGS 84, the system a phone reports and the system of every file the app bundles.
nonisolated struct Coordinate: Sendable, Hashable, Codable {
    var lon: Double
    var lat: Double
}

/// Distances and directions over the few hundred metres the game cares about, and the test for a point in a polygon.
nonisolated enum Geo {
    static let semiMajorAxis = 6_378_137.0
    static let eccentricitySquared = 0.006_694_379_990_14

    /// Metres east and north from one position to another, measured on the ellipsoid at their mean latitude.
    /// Over the distances of a street this agrees with the geodesic to well under a centimetre.
    static func offset(from a: Coordinate, to b: Coordinate) -> (east: Double, north: Double) {
        let phi = (a.lat + b.lat) / 2 * .pi / 180
        let w = (1 - eccentricitySquared * sin(phi) * sin(phi)).squareRoot()
        let primeVertical = semiMajorAxis / w
        let meridional = semiMajorAxis * (1 - eccentricitySquared) / (w * w * w)
        let east = (b.lon - a.lon) * .pi / 180 * primeVertical * cos(phi)
        let north = (b.lat - a.lat) * .pi / 180 * meridional
        return (east, north)
    }

    /// The distance in metres between two positions.
    static func distance(_ a: Coordinate, _ b: Coordinate) -> Double {
        let d = offset(from: a, to: b)
        return (d.east * d.east + d.north * d.north).squareRoot()
    }

    /// The direction from one position to another in degrees clockwise from north, from 0 up to 360.
    static func bearing(from a: Coordinate, to b: Coordinate) -> Double {
        let d = offset(from: a, to: b)
        let degrees = atan2(d.east, d.north) * 180 / .pi
        return degrees < 0 ? degrees + 360 : degrees
    }

    /// How far an arrow must turn from the direction the phone points to a bearing, in degrees from -180 to 180,
    /// positive to the right.
    static func turn(fromHeading heading: Double, toBearing bearing: Double) -> Double {
        var delta = (bearing - heading).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta <= -180 { delta += 360 }
        return delta
    }

    /// Whether a position lies inside a closed ring, by counting the crossings of a ray to the east.
    static func contains(ring: [Coordinate], _ p: Coordinate) -> Bool {
        guard ring.count >= 3 else { return false }
        var inside = false
        var j = ring.count - 1
        for i in ring.indices {
            let a = ring[i]
            let b = ring[j]
            if (a.lat > p.lat) != (b.lat > p.lat) {
                let crossing = (b.lon - a.lon) * (p.lat - a.lat) / (b.lat - a.lat) + a.lon
                if p.lon < crossing { inside.toggle() }
            }
            j = i
        }
        return inside
    }

    /// Whether a position lies inside a polygon given as its outer ring followed by its holes.
    static func contains(polygon rings: [[Coordinate]], _ p: Coordinate) -> Bool {
        guard let outer = rings.first, contains(ring: outer, p) else { return false }
        return !rings.dropFirst().contains { contains(ring: $0, p) }
    }
}

/// Calendar days in the game's timezone. A day is the text yyyy-MM-dd, which sorts the way days do.
nonisolated struct LocalDays: Sendable {
    let calendar: Calendar

    init(timezone identifier: String) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier) ?? .gmt
        self.calendar = calendar
    }

    func day(of date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// The week of a date as text, for example 2026-W41. Weeks begin on Monday and belong to the year that holds
    /// their Thursday, the way calendars number them.
    func week(of date: Date) -> String {
        var weeks = Calendar(identifier: .iso8601)
        weeks.timeZone = calendar.timeZone
        let parts = weeks.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return String(format: "%04d-W%02d", parts.yearForWeekOfYear ?? 0, parts.weekOfYear ?? 0)
    }
}
