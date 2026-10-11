import Foundation

/// One storm drain of the town's layer, as the pipeline wrote it into inlets.json.
nonisolated struct Inlet: Sendable, Codable, Hashable, Identifiable {
    let id: String
    let lon: Double
    let lat: Double
    let owner: String
    let road: String
    let type: String
    let grate: String
    let dup: Int
    let zone: String

    var coordinate: Coordinate { Coordinate(lon: lon, lat: lat) }
}

/// A drain seen from a position.
nonisolated struct NearbyInlet: Sendable, Equatable {
    let inlet: Inlet
    let distanceM: Double
    let bearing: Double
}

/// Every drain in town, bundled with the app so that the map and the fence work without a network.
nonisolated struct InletStore: Sendable {
    let inlets: [Inlet]
    let source: String
    let licence: String
    let retrieved: String
    private let position: [String: Int]

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
    }

    init(json: Data) throws {
        let file = try JSONDecoder().decode(File.self, from: json)
        guard file.count == file.inlets.count else { throw Problem.countDiffers(stated: file.count, found: file.inlets.count) }
        var position: [String: Int] = [:]
        position.reserveCapacity(file.inlets.count)
        for (k, inlet) in file.inlets.enumerated() {
            guard position.updateValue(k, forKey: inlet.id) == nil else { throw Problem.repeatedId(inlet.id) }
        }
        inlets = file.inlets
        source = file.source
        licence = file.licence
        retrieved = file.retrieved
        self.position = position
    }

    subscript(id: String) -> Inlet? {
        position[id].map { inlets[$0] }
    }

    /// The drains within a radius of a position, nearest first. A scan over the whole town takes no time that
    /// matters, so there is no index to keep right.
    func nearby(_ here: Coordinate, within radiusM: Double) -> [NearbyInlet] {
        let latSpan = radiusM / 110_000
        let lonSpan = radiusM / (110_000 * max(0.1, cos(here.lat * .pi / 180)))
        var found: [NearbyInlet] = []
        for inlet in inlets where abs(inlet.lat - here.lat) <= latSpan && abs(inlet.lon - here.lon) <= lonSpan {
            let distance = Geo.distance(here, inlet.coordinate)
            if distance <= radiusM {
                found.append(NearbyInlet(inlet: inlet, distanceM: distance, bearing: Geo.bearing(from: here, to: inlet.coordinate)))
            }
        }
        return found.sorted { ($0.distanceM, $0.inlet.id) < ($1.distanceM, $1.inlet.id) }
    }

    /// The other drains close to a drain, nearest first. Drains sit in pairs on opposite kerbs and in clusters at
    /// corners, and these are the ones a report may have meant.
    func siblings(of inlet: Inlet, within radiusM: Double) -> [NearbyInlet] {
        nearby(inlet.coordinate, within: radiusM).filter { $0.inlet.id != inlet.id }
    }
}
