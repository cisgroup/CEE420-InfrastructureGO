import Foundation

/// How a meeting at a drain ended.
nonisolated enum Outcome: String, Sendable, Codable, Equatable {
    case caught         // the keeper accepted the marker
    case mastered       // the player read the tell and the keeper landed on the marker
    case slipped        // three misses, and the keeper waits at another drain
    case looked         // a look at a drain without a keeper, which still counts for the town
}

/// One look at a drain as the phone remembers it. Until a server exists this list is the player's whole history.
nonisolated struct Meeting: Sendable, Codable, Equatable, Identifiable {
    let id: UUID
    let site: String
    let keeper: String?
    let outcome: Outcome
    let need: Int
    let points: Int
    let parts: Int
    let at: Date
}

/// A keeper that slipped away and waits at another drain until the player comes.
nonisolated struct Waiting: Sendable, Codable, Equatable {
    let keeper: String
    let site: String
    let from: String
    let since: Date
}

/// An open hunt for a rare keeper, which stays at its drain for the week.
nonisolated struct Hunt: Sendable, Codable, Equatable {
    let keeper: String
    let site: String
    let week: String
}

/// Everything a player has done, from which the points, the level, the journal and the map follow.
nonisolated struct PlayerProgress: Sendable, Codable, Equatable {
    var version = 2
    var meetings: [Meeting] = []
    var bonusPoints = 0
    var openCells: Set<Int64> = []
    var known: Set<String> = []
    var parts: [String: Int] = [:]
    var pinned: String?
    var jobs: [Job] = []
    var swappedOn: String?
    var waiting: [Waiting] = []
    var hunt: Hunt?
    var huntOpenedOn: String?
    var visitorsMet: Set<String> = []
    var misses: [String: Int] = [:]
    var told: Set<String> = []
    var left: Set<String> = []
    var figure: String?
    var friend: String?
    var easyCatch = false
    var easyOffered = false
    var sound = true
    var ticks = true

    init() {}

    /// A file written by an older build of this version may lack what a newer build added, so every part is
    /// read if it is there and left at its start value if not.
    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        version = try box.decodeIfPresent(Int.self, forKey: .version) ?? 0
        guard version == 2 else { throw DecodingError.dataCorruptedError(forKey: .version, in: box, debugDescription: "progress of another version") }
        meetings = try box.decodeIfPresent([Meeting].self, forKey: .meetings) ?? []
        bonusPoints = try box.decodeIfPresent(Int.self, forKey: .bonusPoints) ?? 0
        openCells = try box.decodeIfPresent(Set<Int64>.self, forKey: .openCells) ?? []
        known = try box.decodeIfPresent(Set<String>.self, forKey: .known) ?? []
        parts = try box.decodeIfPresent([String: Int].self, forKey: .parts) ?? [:]
        pinned = try box.decodeIfPresent(String.self, forKey: .pinned)
        jobs = try box.decodeIfPresent([Job].self, forKey: .jobs) ?? []
        swappedOn = try box.decodeIfPresent(String.self, forKey: .swappedOn)
        waiting = try box.decodeIfPresent([Waiting].self, forKey: .waiting) ?? []
        hunt = try box.decodeIfPresent(Hunt.self, forKey: .hunt)
        huntOpenedOn = try box.decodeIfPresent(String.self, forKey: .huntOpenedOn)
        visitorsMet = try box.decodeIfPresent(Set<String>.self, forKey: .visitorsMet) ?? []
        misses = try box.decodeIfPresent([String: Int].self, forKey: .misses) ?? [:]
        told = try box.decodeIfPresent(Set<String>.self, forKey: .told) ?? []
        left = try box.decodeIfPresent(Set<String>.self, forKey: .left) ?? []
        figure = try box.decodeIfPresent(String.self, forKey: .figure)
        friend = try box.decodeIfPresent(String.self, forKey: .friend)
        easyCatch = try box.decodeIfPresent(Bool.self, forKey: .easyCatch) ?? false
        easyOffered = try box.decodeIfPresent(Bool.self, forKey: .easyOffered) ?? false
        sound = try box.decodeIfPresent(Bool.self, forKey: .sound) ?? true
        ticks = try box.decodeIfPresent(Bool.self, forKey: .ticks) ?? true
    }

    var points: Int { meetings.reduce(bonusPoints) { $0 + $1.points } }

    /// The drains the player has looked at.
    var looked: Set<String> { Set(meetings.map(\.site)) }

    /// The time of the player's latest look at a drain.
    func lastLook(at site: String) -> Date? {
        meetings.lazy.filter { $0.site == site }.map(\.at).max()
    }

    /// How many looks the player took on a local day.
    func looks(on day: String, days: LocalDays) -> Int {
        meetings.filter { days.day(of: $0.at) == day }.count
    }

    /// The keepers the player has met, which is caught or mastered at least once.
    var met: Set<String> {
        Set(meetings.filter { $0.outcome == .caught || $0.outcome == .mastered }.compactMap(\.keeper))
    }

    /// Whether the player has won a keeper yet. The first meeting of every player is taught and cannot go wrong.
    var hasMetAnyone: Bool { !met.isEmpty }
}

/// What a meeting came to, for the card the player sees.
nonisolated struct MeetingResult: Sendable, Equatable, Identifiable {
    let meeting: Meeting
    let keeper: Keeper?
    let line: String                // what the meeting changed in the journal
    let pageBefore: Page?
    let page: Page?
    let need: Tier
    let look: String                // the quiet line about the points of the look
    let crateParts: Int
    let jobParts: Int
    let levelParts: Int
    let filled: [Filled]
    let thanks: Int                 // points for parts that found no piece to go to
    let jobsDone: [Job]
    let before: Standing
    let after: Standing
    let slippedTo: String?
    var id: UUID { meeting.id }
    var finished: [GearFile.Piece] { filled.filter(\.finished).map(\.piece) }
}

nonisolated enum Play {
    /// The need of a drain for a look by this player now. Until a server exists the last look by anyone is the
    /// player's own, so every drain the player never looked at has the highest need.
    static func need(site: String, progress: PlayerProgress, now: Date, rules: GameRules) -> Tier {
        let last = progress.lastLook(at: site)
        return SpawnRules.tier(now: now, lastAnyAt: last, myLastAt: last, stormOpen: false, rules: rules)
    }

    /// Whether a drain rests for this player, which it does for the rest of the day after a look.
    static func rests(site: String, progress: PlayerProgress, now: Date, rules: GameRules) -> Bool {
        need(site: site, progress: progress, now: now, rules: rules) == .resting
    }

    /// The keeper this player meets at a drain now, or nil at a drain that rests.
    ///
    /// A keeper that slipped away and waits here comes first. The first keeper of every player is the first
    /// common one of the file, the frog. Then the week's visitor, if this is its drain and the player has not met
    /// it this week. Otherwise the keeper that lives here.
    static func keeper(at site: Inlet, grates: Int, progress: PlayerProgress, now: Date, book: Book, visitor: (site: Inlet, keeper: Keeper)? = nil) -> Keeper? {
        guard !rests(site: site.id, progress: progress, now: now, rules: book.rules) else { return nil }
        if let waits = progress.waiting.first(where: { $0.site == site.id }), let keeper = book.keeper(waits.keeper) { return keeper }
        if !progress.hasMetAnyone, let first = book.keepers.first(where: { $0.kind == "common" }) { return first }
        let days = book.rules.days
        if let visitor, visitor.site.id == site.id, !progress.visitorsMet.contains("\(days.week(of: now))|\(site.zone)") { return visitor.keeper }
        return World.resident(of: site, grates: grates, day: days.day(of: now), week: days.week(of: now), keepers: book.keepers, kinds: book.world.kinds)
    }

    /// The parts in the crate of a drain, by its need.
    static func crateParts(need: Tier, world: WorldRules) -> Int {
        world.crateParts.indices.contains(need.rawValue) ? world.crateParts[need.rawValue] : 0
    }

    /// The misses a player has at a drain today. Leaving a meeting does not wipe them.
    static func misses(at site: String, progress: PlayerProgress, now: Date, rules: GameRules) -> Int {
        progress.misses["\(site)|\(rules.days.day(of: now))"] ?? 0
    }

    static func missed(at site: String, progress: PlayerProgress, now: Date, rules: GameRules) -> PlayerProgress {
        var grown = progress
        grown.misses["\(site)|\(rules.days.day(of: now))", default: 0] += 1
        return grown
    }

    /// Settle a meeting and keep it. The look counts for the town whatever became of the keeper.
    static func settle(site: Inlet, keeper: Keeper?, outcome: Outcome, slipTo: Inlet? = nil, progress: PlayerProgress, now: Date, book: Book) -> (MeetingResult, PlayerProgress) {
        let days = book.rules.days
        let day = days.day(of: now)
        let need = need(site: site.id, progress: progress, now: now, rules: book.rules)
        let last = progress.lastLook(at: site.id)
        let won = outcome == .caught || outcome == .mastered
        let newSite = !progress.looked.contains(site.id)
        let pageBefore = keeper.map { Journal.page(of: $0.id, in: progress, rungs: book.world.rungs) }
        let newKind = won && (pageBefore?.meetings ?? 0) == 0 && keeper != nil

        var points = SpawnRules.points(tier: need, greatCatch: false, rules: book.rules)
        if newKind { points += book.world.points.newKind }
        if outcome == .mastered { points += book.world.points.mastered }
        let crate = crateParts(need: need, world: book.world)

        var grown = progress
        let before = Progression.standing(points: grown.points, in: book.gear)
        let record = Meeting(id: UUID(), site: site.id, keeper: keeper?.id, outcome: keeper == nil ? .looked : outcome, need: need.rawValue, points: points, parts: crate, at: now)
        grown.meetings.append(record)
        grown.known.insert(site.id)
        grown.misses = grown.misses.filter { !$0.key.hasPrefix("\(site.id)|") }

        var jobsDone = Jobs.record(.look(newSite: newSite), in: &grown.jobs, day: day)
        if newKind { jobsDone += Jobs.record(.newKeeper, in: &grown.jobs, day: day) }
        if outcome == .mastered { jobsDone += Jobs.record(.seal, in: &grown.jobs, day: day) }
        let levelParts = max(0, Progression.standing(points: grown.points, in: book.gear).level - before.level)
        let handed = Gear.add(crate + jobsDone.count + levelParts, to: &grown.parts, pinned: grown.pinned, in: book.gear)
        let thanks = handed.over * book.world.points.thanks
        grown.bonusPoints += thanks

        if let keeper {
            grown.waiting.removeAll { $0.site == site.id && $0.keeper == keeper.id }
            if outcome == .slipped, let slipTo {
                grown.waiting.append(Waiting(keeper: keeper.id, site: slipTo.id, from: site.id, since: now))
                if grown.waiting.count > book.world.slip.waiting { grown.waiting.removeFirst(grown.waiting.count - book.world.slip.waiting) }
            }
            if won, let hunt = grown.hunt, hunt.site == site.id, hunt.keeper == keeper.id { grown.hunt = nil }
            if won, keeper.kind == "visitor" { grown.visitorsMet.insert("\(days.week(of: now))|\(site.zone)") }
        }

        let page = keeper.map { Journal.page(of: $0.id, in: grown, rungs: book.world.rungs) }
        let line: String
        if let keeper, let pageBefore, let page, won {
            line = Journal.line(keeper, before: pageBefore, after: page, mastered: outcome == .mastered)
        } else if outcome == .slipped {
            line = "It slipped away. It waits at another drain close by."
        } else {
            line = "A look that counts."
        }
        let result = MeetingResult(meeting: record, keeper: keeper, line: line, pageBefore: pageBefore, page: page, need: need,
                                   look: Words.look(points: SpawnRules.points(tier: need, greatCatch: false, rules: book.rules), need: need, last: last, now: now),
                                   crateParts: crate, jobParts: jobsDone.count, levelParts: levelParts, filled: handed.filled, thanks: thanks, jobsDone: jobsDone,
                                   before: before, after: Progression.standing(points: grown.points, in: book.gear),
                                   slippedTo: outcome == .slipped ? slipTo?.id : nil)
        return (result, grown)
    }
}

/// The sentences of the game, in plain words and in one place.
nonisolated enum Words {
    /// How long ago something was, counted in whole days of elapsed time.
    static func ago(_ then: Date, now: Date) -> String {
        let days = Int(max(0, now.timeIntervalSince(then)) / SpawnRules.secondsPerDay)
        switch days {
        case 0: return "today"
        case 1: return "yesterday"
        default: return "\(days) days ago"
        }
    }

    /// What is known about earlier looks at a drain. It speaks of the player's own looks, because until a server
    /// exists the phone knows of no others, and it claims nothing about what the town or anybody else did.
    static func lastLook(_ last: Date?, now: Date) -> String {
        guard let last else { return "You have not looked at this drain yet." }
        return "You last looked here \(ago(last, now: now))."
    }

    /// The quiet line of a result about the points of the look itself.
    static func look(points: Int, need: Tier, last: Date?, now: Date) -> String {
        switch need {
        case .resting: "\(count(points, "point", "points")). You already looked here today."
        default: last == nil ? "\(points) points for your first look at this drain." : "\(points) points. \(lastLook(last, now: now))"
        }
    }

    /// What a crate of a drain holds, said before it is opened.
    static func crate(parts: Int) -> String {
        switch parts {
        case 0: "No crate today."
        case 1: "A small crate."
        case 2: "A good crate."
        default: "A full crate."
        }
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

    /// What the detector says under its needle.
    static func detector(_ reading: Reading) -> String {
        switch reading.state {
        case .noFix: "Waiting for your position."
        case .outside: "The watershed ends here. Turn back toward the dashed line."
        case .quiet: "Quiet here. Walk on, the needle shows the way."
        case .atDrain: "Close enough. You can stay on this side."
        case .signal: reading.distanceM.map { "Something \(distance($0)) away." } ?? "Something is near."
        }
    }

    /// The hint that opens a hunt. It names the road of the drain, or a direction where the road has no name.
    static func hint(road: String, bearing: Double) -> String {
        if !road.isEmpty { return "Your detector picked up something unusual near \(road)." }
        let names = ["north", "north east", "east", "south east", "south", "south west", "west", "north west"]
        return "Your detector picked up something unusual in the streets \(names[Int(((bearing + 22.5).truncatingRemainder(dividingBy: 360)) / 45) % 8]) of you."
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
