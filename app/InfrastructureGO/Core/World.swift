import Foundation

/// Who lives at which drain. The answer follows from the drain, the day and the week and from nothing a player
/// did, so every player meets the same keeper at the same drain, and nobody can spoil another player's keeper.
nonisolated enum World {
    /// Whether the game may single a drain out, as the home of the week's visitor, the goal of a hunt or the place
    /// a slipped keeper waits. Drains on the State's roads and on the ramps of the highway are never singled out,
    /// because nobody should be drawn to stand there. They can still be looked at by a player who is there anyway.
    static func invites(_ inlet: Inlet, rule: WorldRules.Invites) -> Bool {
        !rule.notOwners.contains(inlet.owner) && !rule.notRoads.contains(inlet.road) && !rule.notRoadPrefixes.contains { inlet.road.hasPrefix($0) }
    }

    /// How much a keeper likes a drain, and zero for a drain outside its habitat.
    static func liking(_ keeper: Keeper, for site: Inlet, grates: Int) -> Double {
        let habitat = keeper.habitat
        guard habitat.zones.isEmpty || habitat.zones.contains(site.zone) else { return 0 }
        guard habitat.owners.isEmpty || habitat.owners.contains(site.owner) else { return 0 }
        guard habitat.roads.isEmpty || habitat.roads.contains(site.road) else { return 0 }
        return Double(max(1, keeper.weight)) * (grates > 1 ? max(0, habitat.rows) : 1)
    }

    /// One keeper of a kind for a drain, drawn by a key among those whose habitat fits, likelier the more they like it.
    static func pick(kind: String, site: Inlet, grates: Int, key: String, keepers: [Keeper]) -> Keeper? {
        let fitting = keepers.filter { $0.kind == kind }.map { (keeper: $0, liking: liking($0, for: site, grates: grates)) }.filter { $0.liking > 0 }
        let total = fitting.reduce(0) { $0 + $1.liking }
        guard total > 0 else { return nil }
        var roll = Hash.unit(key) * total
        for entry in fitting {
            if roll < entry.liking { return entry.keeper }
            roll -= entry.liking
        }
        return fitting.last?.keeper
    }

    /// Whether a drain is the home of a rare keeper this week. A rare keeper stays for the whole week, so a hint
    /// about it is still true tomorrow.
    static func isRareHome(_ site: Inlet, week: String, kinds: WorldRules.Kinds) -> Bool {
        Hash.index("\(site.id)|\(week)|rare home", count: 100) < kinds.rarePerHundred
    }

    /// The keeper that lives at a drain on a day of a week.
    static func resident(of site: Inlet, grates: Int, day: String, week: String, keepers: [Keeper], kinds: WorldRules.Kinds) -> Keeper? {
        if isRareHome(site, week: week, kinds: kinds), let rare = pick(kind: "rare", site: site, grates: grates, key: "\(site.id)|\(week)|rare", keepers: keepers) {
            return rare
        }
        let common = Hash.index("\(site.id)|\(day)|kind", count: max(1, kinds.common + kinds.uncommon)) < kinds.common
        let first = common ? "common" : "uncommon"
        let second = common ? "uncommon" : "common"
        return pick(kind: first, site: site, grates: grates, key: "\(site.id)|\(day)|\(first)", keepers: keepers)
            ?? pick(kind: second, site: site, grates: grates, key: "\(site.id)|\(day)|\(second)", keepers: keepers)
    }

    /// The visitor of a week in a zone, one special keeper at one of the drains given. The same keeper visits
    /// every zone in a week, each at a drain of its own.
    static func visitor(zone: String, week: String, sites: [Inlet], keepers: [Keeper]) -> (site: Inlet, keeper: Keeper)? {
        let visitors = keepers.filter { $0.kind == "visitor" }
        let here = sites.filter { $0.zone == zone }.sorted { $0.id < $1.id }
        guard !visitors.isEmpty, !here.isEmpty else { return nil }
        return (here[Hash.index("\(zone)|\(week)|visit", count: here.count)], visitors[Hash.index("\(week)|visitor", count: visitors.count)])
    }

    /// Where a keeper waits that slipped away, the nearest of the drains given that lies far enough for a walk
    /// and near enough to find. The drains given are those the game may single out and that do not rest.
    static func slipTarget(among others: [NearbySite], minM: Double, maxM: Double) -> Inlet? {
        others.sorted { ($0.distanceM, $0.head.id) < ($1.distanceM, $1.head.id) }.first { $0.distanceM >= minM && $0.distanceM <= maxM }?.head
    }
}
