import Foundation

/// One catch as the phone remembers it. Until a server exists this list is the player's whole history.
nonisolated struct CatchRecord: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let site: String
    let species: String?
    let tier: Int
    let points: Int
    let great: Bool
    let at: Date
}

/// What a player has caught so far, from which the points, the level and the field guide follow.
nonisolated struct PlayerProgress: Codable, Sendable, Equatable {
    var catches: [CatchRecord] = []

    var points: Int { catches.reduce(0) { $0 + $1.points } }

    /// The time of the player's latest catch at a site.
    func lastCatch(at site: String) -> Date? {
        catches.lazy.filter { $0.site == site }.map(\.at).max()
    }

    func count(of species: String) -> Int {
        catches.filter { $0.species == species }.count
    }

    func firstCatch(of species: String) -> Date? {
        catches.lazy.filter { $0.species == species }.map(\.at).min()
    }

    /// How many different drains the player caught at on a local day.
    func drains(on day: String, days: LocalDays) -> Int {
        Set(catches.filter { days.day(of: $0.at) == day }.map(\.site)).count
    }
}

/// A made up history of reports by other players, so that the map shows every tier before a server exists. Four
/// drains in ten were never checked, three were checked six days ago and three yesterday. Which drain gets which
/// follows from its id, so the world looks the same on every phone and on every day.
nonisolated enum DemoWorld {
    static func lastReport(site: String, now: Date) -> Date? {
        switch SpeciesPicker.hashIndex("\(site)|demo world", count: 10) {
        case 0...3: return nil
        case 4...6: return now.addingTimeInterval(-6 * SpawnRules.secondsPerDay)
        default: return now.addingTimeInterval(-1 * SpawnRules.secondsPerDay)
        }
    }
}

/// What a catch came to, for the card the player sees.
nonisolated struct CatchResult: Sendable, Equatable {
    let record: CatchRecord
    let species: Species?
    let tier: Tier
    let sentence: String
    let before: Standing
    let after: Standing
    let newGear: [GearFile.Gear]
}

/// What a player may know about a drain before walking to it.
nonisolated struct DrainOutlook: Sendable, Equatable {
    let tier: Tier
    let lastAnyAt: Date?
    let points: Int
    let sentence: String
}

nonisolated enum Play {
    /// The last report on a site by anyone, which before a server exists is the later of the made up history
    /// and the player's own catches.
    static func lastAnyAt(site: String, progress: PlayerProgress, now: Date) -> Date? {
        [DemoWorld.lastReport(site: site, now: now), progress.lastCatch(at: site)].compactMap { $0 }.max()
    }

    static func outlook(site: String, progress: PlayerProgress, stormOpen: Bool, now: Date, rules: GameRules) -> DrainOutlook {
        let last = lastAnyAt(site: site, progress: progress, now: now)
        let tier = SpawnRules.tier(now: now, lastAnyAt: last, myLastAt: progress.lastCatch(at: site), stormOpen: stormOpen, rules: rules)
        return DrainOutlook(tier: tier, lastAnyAt: last, points: SpawnRules.points(tier: tier, greatCatch: false, rules: rules),
                            sentence: Words.why(tier: tier, lastAnyAt: last, stormOpen: stormOpen, now: now))
    }

    /// Settle a catch. The tier is the one the drain has at this instant, the species the one of the day, and the
    /// record is added to the progress that comes back.
    static func settle(site: String, greatCatch: Bool, progress: PlayerProgress, stormOpen: Bool, now: Date,
                       rules: GameRules, species: [Species], gear: GearFile) -> (CatchResult, PlayerProgress) {
        let seen = outlook(site: site, progress: progress, stormOpen: stormOpen, now: now, rules: rules)
        let great = greatCatch && seen.tier > .resting
        let creature = SpeciesPicker.pick(inletId: site, day: rules.days.day(of: now), tier: seen.tier, stormOpen: stormOpen, from: species)
        let points = SpawnRules.points(tier: seen.tier, greatCatch: great, rules: rules)
        let record = CatchRecord(id: UUID(), site: site, species: creature?.id, tier: seen.tier.rawValue, points: points, great: great, at: now)
        var grown = progress
        grown.catches.append(record)
        let result = CatchResult(record: record, species: creature, tier: seen.tier,
                                 sentence: Words.result(points: points, great: great, why: seen.sentence),
                                 before: Progression.standing(points: progress.points, in: gear),
                                 after: Progression.standing(points: grown.points, in: gear),
                                 newGear: Progression.newGear(from: progress.points, to: grown.points, in: gear))
        return (result, grown)
    }
}

/// The sentences of the game, in plain words and in one place.
nonisolated enum Words {
    static func name(of tier: Tier) -> String {
        switch tier {
        case .resting: "Resting"
        case .common: "Common"
        case .uncommon: "Uncommon"
        case .rare: "Rare"
        }
    }

    /// How long ago something was, counted in whole days of elapsed time.
    static func ago(_ then: Date, now: Date) -> String {
        let days = Int(max(0, now.timeIntervalSince(then)) / SpawnRules.secondsPerDay)
        switch days {
        case 0: return "today"
        case 1: return "yesterday"
        default: return "\(days) days ago"
        }
    }

    /// Why a drain is worth what it is worth, as one sentence.
    static func why(tier: Tier, lastAnyAt: Date?, stormOpen: Bool, now: Date) -> String {
        switch tier {
        case .resting:
            return "You already caught here today."
        case .rare:
            guard let last = lastAnyAt else { return "Nobody has checked this drain yet." }
            if stormOpen && now.timeIntervalSince(last) < 14 * SpawnRules.secondsPerDay { return "A storm window is open, so every drain is rare." }
            return "Nobody has checked this drain in \(Int(now.timeIntervalSince(last) / SpawnRules.secondsPerDay)) days."
        case .uncommon:
            return "This drain was last checked \(ago(lastAnyAt ?? now, now: now))."
        case .common:
            return "This drain was checked \(ago(lastAnyAt ?? now, now: now)). A second look still helps."
        }
    }

    static func result(points: Int, great: Bool, why: String) -> String {
        "\(points) points. " + (great ? "Great catch. " : "") + why
    }

    static func distance(_ metres: Double) -> String {
        metres < 1000 ? "\(Int(metres.rounded())) m" : String(format: "%.1f km", metres / 1000)
    }

    static func fence(_ state: FenceState) -> String {
        switch state {
        case .noFix: "Waiting for your position."
        case .walkCloser(let distance): "Walk closer, \(Words.distance(distance)) to go."
        case .roughFix: "GPS is rough here, wait a moment."
        case .inside: "You are at the drain."
        }
    }

    /// A count with its noun, the way a person says it.
    static func count(_ number: Int, _ one: String, _ many: String) -> String {
        "\(number) \(number == 1 ? one : many)"
    }

    static func grates(_ count: Int) -> String {
        switch count {
        case 1: "One grate."
        case 2: "Two grates in a row."
        case 3: "Three grates in a row."
        default: "\(count) grates in a row."
        }
    }
}
