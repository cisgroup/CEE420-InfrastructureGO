import Foundation
import Observation

/// A drain as the map draws it.
struct DrainPin: Identifiable, Equatable {
    let head: Inlet
    let tier: Tier
    var id: String { head.id }
}

/// The state of the game on this phone. It joins the bundled files, the player's catches and the position, and it
/// is the only place the views ask.
@Observable
final class GameModel {
    let content: GameContent?
    let problem: String?
    let location = LocationService()
    private(set) var progress: PlayerProgress
    var target: Inlet?
    var stormOpen = false
    var opening = Opening()
    private let store = ProgressStore()

    /// What a debug launch asks to be shown at once, so that each screen can be looked at without tapping to it.
    struct Opening {
        var tab: String?
        var select: String?
        var encounter: String?
        var species: String?
        var spike: String?
        var freeze: String?
    }

    init() {
        do {
            content = try GameContent.bundled()
            problem = nil
        } catch {
            content = nil
            problem = "The game's files could not be read. \(error)"
        }
        progress = store.load()
        #if DEBUG
        applyLaunchArguments()
        #endif
    }

    // MARK: the day and the drains

    var today: String { content?.rules.days.day(of: Date()) ?? "" }

    func canBeCaught(_ head: Inlet) -> Bool {
        content?.zones.canBeCaught(head, on: today) ?? false
    }

    func grates(of head: Inlet) -> Int {
        content?.inlets.members(ofSite: head.id).count ?? 1
    }

    func outlook(of head: Inlet, now: Date = Date()) -> DrainOutlook? {
        guard let content else { return nil }
        return Play.outlook(site: head.id, progress: progress, stormOpen: stormOpen, now: now, rules: content.rules)
    }

    func species(of head: Inlet, now: Date = Date()) -> Species? {
        guard let content, let seen = outlook(of: head, now: now) else { return nil }
        return SpeciesPicker.pick(inletId: head.id, day: content.rules.days.day(of: now), tier: seen.tier, stormOpen: stormOpen, from: content.species)
    }

    /// The drains to draw inside a box of the map, the nearest to its middle first, and no more than the map can carry.
    func pins(west: Double, south: Double, east: Double, north: Double, limit: Int = 180) -> [DrainPin] {
        guard let content else { return [] }
        let day = today
        let now = Date()
        let middle = Coordinate(lon: (west + east) / 2, lat: (south + north) / 2)
        let inside = content.inlets.heads.filter { $0.lon >= west && $0.lon <= east && $0.lat >= south && $0.lat <= north && content.zones.canBeCaught($0, on: day) }
        let nearest = inside.count <= limit ? inside : Array(inside.sorted { Geo.distance(middle, $0.coordinate) < Geo.distance(middle, $1.coordinate) }.prefix(limit))
        return nearest.map { head in
            DrainPin(head: head, tier: Play.outlook(site: head.id, progress: progress, stormOpen: stormOpen, now: now, rules: content.rules).tier)
        }
    }

    // MARK: the player and a drain

    func distance(to head: Inlet) -> Double? {
        guard let fix = location.fix else { return nil }
        return content?.inlets.distance(from: fix.coordinate, toSite: head.id)
    }

    func bearing(to head: Inlet) -> Double? {
        guard let fix = location.fix else { return nil }
        return Geo.bearing(from: fix.coordinate, to: head.coordinate)
    }

    func fence(of head: Inlet) -> FenceState {
        guard let content else { return .noFix }
        return Fence.state(distanceM: distance(to: head), accuracyM: location.fix?.accuracyM, rules: content.rules)
    }

    /// The catchable drains around the player, nearest first.
    func nearby(within metres: Double = 300) -> [NearbySite] {
        guard let content, let fix = location.fix else { return [] }
        let day = today
        return content.inlets.nearbySites(fix.coordinate, within: metres).filter { content.zones.canBeCaught($0.head, on: day) }
    }

    /// Settle a catch at a drain and keep it.
    func settle(_ head: Inlet, great: Bool) -> CatchResult? {
        guard let content else { return nil }
        let (result, grown) = Play.settle(site: head.id, greatCatch: great, progress: progress, stormOpen: stormOpen, now: Date(),
                                          rules: content.rules, species: content.species, gear: content.gear)
        progress = grown
        store.save(grown)
        if target?.id == head.id { target = nil }
        return result
    }

    var standing: Standing? {
        content.map { Progression.standing(points: progress.points, in: $0.gear) }
    }

    // MARK: looking at the game without walking

    /// Put the player a few steps from a drain, as if they had walked there.
    func stand(at head: Inlet) {
        let spot = Coordinate(lon: head.lon + 0.00003, lat: head.lat - 0.00003)
        location.standIn = Fix(coordinate: spot, accuracyM: 5)
    }

    #if DEBUG
    private func applyLaunchArguments() {
        let asked = UserDefaults.standard
        if asked.bool(forKey: "igo.reset") {
            store.erase()
            progress = PlayerProgress()
        }
        if let count = Int(asked.string(forKey: "igo.fill") ?? ""), let content {
            var filled = PlayerProgress()
            let start = Date().addingTimeInterval(-3 * SpawnRules.secondsPerDay)
            for (k, head) in content.inlets.heads.filter({ content.zones.canBeCaught($0, on: today) }).prefix(count).enumerated() {
                let (_, grown) = Play.settle(site: head.id, greatCatch: k % 3 == 0, progress: filled, stormOpen: false, now: start.addingTimeInterval(Double(k) * 240),
                                             rules: content.rules, species: content.species, gear: content.gear)
                filled = grown
            }
            progress = filled
        }
        stormOpen = asked.bool(forKey: "igo.storm")
        if let site = asked.string(forKey: "igo.stand"), let head = content?.inlets[site] { stand(at: head) }
        opening = Opening(tab: asked.string(forKey: "igo.tab"), select: asked.string(forKey: "igo.select"), encounter: asked.string(forKey: "igo.encounter"),
                          species: asked.string(forKey: "igo.species"), spike: asked.string(forKey: "igo.spike"), freeze: asked.string(forKey: "igo.freeze"))
    }
    #endif
}
