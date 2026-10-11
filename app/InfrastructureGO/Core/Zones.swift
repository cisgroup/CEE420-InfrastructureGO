import Foundation

/// A play zone, a named polygon in which the game is switched on from a day on for the drains of some owners.
nonisolated struct Zone: Sendable, Equatable, Identifiable {
    let id: String
    let name: String
    let activeFrom: String
    let activeTo: String?
    let owners: Set<String>
    let polygons: [[[Coordinate]]]      // each polygon is its outer ring followed by its holes

    func contains(_ position: Coordinate) -> Bool {
        polygons.contains { Geo.contains(polygon: $0, position) }
    }

    /// Whether the zone is switched on on a local day, written yyyy-MM-dd.
    func isActive(on day: String) -> Bool {
        activeFrom <= day && (activeTo.map { day <= $0 } ?? true)
    }
}

/// The zones of zones.geojson, the file the pipeline copies into the app.
nonisolated struct ZoneStore: Sendable {
    let zones: [Zone]

    nonisolated enum Problem: Error, Equatable {
        case unknownGeometry(String)
    }

    private nonisolated struct Collection: Decodable {
        let features: [Feature]
    }

    private nonisolated struct Feature: Decodable {
        let properties: Properties
        let geometry: Geometry
    }

    private nonisolated struct Properties: Decodable {
        let id: String
        let name: String
        let activeFrom: String
        let activeTo: String?
        let owners: [String]
    }

    private nonisolated struct Geometry: Decodable {
        let polygons: [[[Coordinate]]]

        enum CodingKeys: String, CodingKey { case type, coordinates }

        init(from decoder: Decoder) throws {
            let box = try decoder.container(keyedBy: CodingKeys.self)
            let type = try box.decode(String.self, forKey: .type)
            let rings: [[[[Double]]]]
            switch type {
            case "Polygon": rings = [try box.decode([[[Double]]].self, forKey: .coordinates)]
            case "MultiPolygon": rings = try box.decode([[[[Double]]]].self, forKey: .coordinates)
            default: throw Problem.unknownGeometry(type)
            }
            polygons = rings.map { polygon in polygon.map { ring in ring.map { Coordinate(lon: $0[0], lat: $0[1]) } } }
        }
    }

    init(geojson: Data) throws {
        let collection = try GameData.decoder.decode(Collection.self, from: geojson)
        zones = collection.features.map { feature in
            Zone(id: feature.properties.id, name: feature.properties.name, activeFrom: feature.properties.activeFrom,
                 activeTo: feature.properties.activeTo, owners: Set(feature.properties.owners), polygons: feature.geometry.polygons)
        }
    }

    func zone(id: String) -> Zone? {
        zones.first { $0.id == id }
    }

    /// The zone a position lies in, for telling a player where the game begins.
    func zone(containing position: Coordinate) -> Zone? {
        zones.first { $0.contains(position) }
    }

    /// Whether a drain can be caught on a local day. Its zone comes from the pipeline, which tested the same
    /// polygons, and the zone must be switched on that day and admit the drain's owner.
    func canBeCaught(_ inlet: Inlet, on day: String) -> Bool {
        guard let zone = zone(id: inlet.zone) else { return false }
        return zone.isActive(on: day) && zone.owners.contains(inlet.owner)
    }
}
