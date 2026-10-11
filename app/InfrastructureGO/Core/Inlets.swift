import Foundation

/// One storm drain of the town's layer, as the pipeline wrote it into inlets.json.
///
/// The layer draws every grate as a point of its own, also where two or three grates stand in a row along one
/// kerb. Such a row is one drain to anyone who stands in front of it, so every inlet names its site, the id of
/// the first inlet of its row. An inlet that stands alone is its own site. The game counts by site.
nonisolated struct Inlet: Sendable, Codable, Hashable, Identifiable {
    let id: String
    let lon: Double
    let lat: Double
    let owner: String
    let road: String
    let type: String
    let grate: String
    let dup: Int
    let site: String
    let zone: String

    var coordinate: Coordinate { Coordinate(lon: lon, lat: lat) }

    /// Whether this inlet is the one its site is named after, the one the map draws and a report names.
    var isSiteHead: Bool { id == site }
}

/// A site seen from a position. The distance and the direction are those of its nearest grate.
nonisolated struct NearbySite: Sendable, Equatable {
    let head: Inlet
    let grates: Int
    let distanceM: Double
    let bearing: Double
}

/// Every drain in town, bundled with the app so that the map and the fence work without a network.
nonisolated struct InletStore: Sendable {
    let inlets: [Inlet]
    let heads: [Inlet]
    let source: String
    let licence: String
    let retrieved: String
    private let position: [String: Int]
    private let membersOfSite: [String: [Int]]

    private nonisolated struct File: Decodable {
        let source: String
        let licence: String
        let retrieved: String
        let count: Int
        let inlets: [Inlet]
    }

    nonisolated enum Problem: Error, Equatable {
        case countDiffers(stated: Int, found: Int)
        case repeatedId(String)
        case siteWithoutHead(String)
    }

    init(json: Data) throws {
        let file = try JSONDecoder().decode(File.self, from: json)
        guard file.count == file.inlets.count else { throw Problem.countDiffers(stated: file.count, found: file.inlets.count) }
        var position: [String: Int] = [:]
        var members: [String: [Int]] = [:]
        position.reserveCapacity(file.inlets.count)
        for (k, inlet) in file.inlets.enumerated() {
            guard position.updateValue(k, forKey: inlet.id) == nil else { throw Problem.repeatedId(inlet.id) }
            members[inlet.site, default: []].append(k)
        }
        for site in members.keys where position[site] == nil { throw Problem.siteWithoutHead(site) }
        inlets = file.inlets
        heads = file.inlets.filter(\.isSiteHead)
        source = file.source
        licence = file.licence
        retrieved = file.retrieved
        self.position = position
        membersOfSite = members
    }

    subscript(id: String) -> Inlet? {
        position[id].map { inlets[$0] }
    }

    /// The inlet a site is named after, for any inlet of the site.
    func head(of inlet: Inlet) -> Inlet {
        self[inlet.site] ?? inlet
    }

    /// The grates of a site, in the order of their ids.
    func members(ofSite site: String) -> [Inlet] {
        (membersOfSite[site] ?? []).map { inlets[$0] }
    }

    /// The sites within a radius of a position, nearest first. A site is as near as its nearest grate. A scan
    /// over the whole town takes no time that matters, so there is no index to keep right.
    func nearbySites(_ here: Coordinate, within radiusM: Double) -> [NearbySite] {
        let latSpan = radiusM / 110_000
        let lonSpan = radiusM / (110_000 * max(0.1, cos(here.lat * .pi / 180)))
        var best: [String: (distance: Double, bearing: Double)] = [:]
        for inlet in inlets where abs(inlet.lat - here.lat) <= latSpan && abs(inlet.lon - here.lon) <= lonSpan {
            let distance = Geo.distance(here, inlet.coordinate)
            guard distance <= radiusM else { continue }
            if let known = best[inlet.site], known.distance <= distance { continue }
            best[inlet.site] = (distance, Geo.bearing(from: here, to: inlet.coordinate))
        }
        return best.compactMap { site, seen in
            self[site].map { NearbySite(head: $0, grates: membersOfSite[site]?.count ?? 1, distanceM: seen.distance, bearing: seen.bearing) }
        }
        .sorted { ($0.distanceM, $0.head.id) < ($1.distanceM, $1.head.id) }
    }

    /// The distance in metres from a position to a site, which is the distance to its nearest grate.
    func distance(from here: Coordinate, toSite site: String) -> Double? {
        members(ofSite: site).map { Geo.distance(here, $0.coordinate) }.min()
    }

    /// The other sites close to a site, nearest first. Drains sit on opposite kerbs and in clusters at corners,
    /// and these are the ones a report may have meant instead.
    func siblingSites(of site: String, within radiusM: Double) -> [NearbySite] {
        var best: [String: NearbySite] = [:]
        for member in members(ofSite: site) {
            for other in nearbySites(member.coordinate, within: radiusM) where other.head.site != site {
                if let known = best[other.head.id], known.distanceM <= other.distanceM { continue }
                best[other.head.id] = other
            }
        }
        return best.values.sorted { ($0.distanceM, $0.head.id) < ($1.distanceM, $1.head.id) }
    }
}
