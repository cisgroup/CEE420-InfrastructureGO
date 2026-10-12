import Foundation
import Observation

/// A drain as the map draws it.
struct Token: Identifiable, Equatable {
    enum State: Equatable {
        case plain                                              // known, too far to see what it holds
        case resting                                            // the player looked here today
        case holds(keeper: String?, met: Bool, crate: Int)      // near enough to see who is there
    }

    let head: Inlet
    let state: State
    var id: String { head.id }
}

/// A keeper somewhere near, for the strip of shadows.
struct Shadow: Identifiable, Equatable {
    let head: Inlet
    let keeper: Keeper
    let met: Bool
    let distanceM: Double
    var id: String { head.id }
}

/// An invitation the map draws above the veil, a keeper that waits or the visitor of the week.
struct Invitation: Identifiable, Equatable {
    let head: Inlet
    let keeper: Keeper
    let showsKeeper: Bool
    let isVisitor: Bool
    var id: String { (isVisitor ? "visitor " : "waiting ") + head.id }
}

/// What a meeting needs to know before it starts.
struct MeetingPlan {
    let head: Inlet
    let keeper: Keeper?
    let timeline: Timeline
    let isFirst: Bool
    let misses: Int
    let crateParts: Int
    let aimDeg: Double
    let pulse: Bool
    let easy: Bool
}

/// The state of the game on this phone. It joins the bundled files, what the player has done and the position,
/// and it is the only place the views ask.
@Observable
final class GameModel {
    let content: GameContent?
    let problem: String?
    let location = LocationService()
    let sound = SoundBox()
    let haptics = Haptics()
    private(set) var progress: PlayerProgress
    var target: Inlet?
    var opening = Opening()

    /// What the detector says now, the keepers near, the veil to draw and a sentence to show for a moment.
    private(set) var reading = Reading.nothing
    private(set) var shadows: [Shadow] = []
    private(set) var veil: (holes: [[Coordinate]], islands: [[Coordinate]]) = ([], [])
    private(set) var veilVersion = 0
    private(set) var announcement: String?
    private(set) var ticks = 0
    private(set) var isWalking = false
    /// While a meeting fills the screen nothing is said on the map. What came up is said when the map is back.
    var inMeeting = false {
        didSet {
            if !inMeeting { sayNext() }
        }
    }
    private var unsaid: [String] = []

    /// The desk panel can move the clock forward, so that the next day and the next week can be tried at once.
    private(set) var clockOffset: TimeInterval = 0
    var now: Date { Date().addingTimeInterval(clockOffset) }

    private let store = ProgressStore()
    private var walking: Task<Void, Never>?
    private var ticking: Task<Void, Never>?
    private var unsaved = 0
    private var offeredOn = ""
    private var offered: [Inlet] = []
    private var invited: Set<String> = []
    private var visitors: [String: (site: Inlet, keeper: Keeper)] = [:]
    private var visitorsOf = ""

    /// What a debug launch asks to be shown at once, so that each screen can be looked at without tapping to it.
    struct Opening {
        var tab: String?
        var select: String?
        var encounter: String?
        var keeper: String?
        var moment: String?
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
        sound.isOn = progress.sound
        haptics.isOn = progress.ticks
        redrawVeil()
    }

    // MARK: the day and the drains

    var today: String { content?.rules.days.day(of: now) ?? "" }
    var week: String { content?.rules.days.week(of: now) ?? "" }

    private var grid: VeilGrid? {
        content.map { VeilGrid(origin: $0.world.veil.origin, cellM: $0.world.veil.cellM) }
    }

    /// The drains of the game today, the ones a player may look at. Counted again when the day changes.
    var drains: [Inlet] {
        guard let content else { return [] }
        if offeredOn != today {
            offeredOn = today
            offered = content.inlets.heads.filter { content.zones.canBeCaught($0, on: offeredOn) }
            invited = Set(offered.filter { World.invites($0, rule: content.world.invites) }.map(\.id))
        }
        return offered
    }

    func isOfTheGame(_ head: Inlet) -> Bool {
        content?.zones.canBeCaught(head, on: today) ?? false
    }

    /// Whether the game may single this drain out as a place to walk to.
    func invites(_ head: Inlet) -> Bool {
        _ = drains
        return invited.contains(head.id)
    }

    func grates(of head: Inlet) -> Int {
        content?.inlets.members(ofSite: head.id).count ?? 1
    }

    func rests(_ head: Inlet) -> Bool {
        guard let content else { return true }
        return Play.rests(site: head.id, progress: progress, now: now, rules: content.rules)
    }

    /// Whether a drain still holds something for the player today.
    func holds(_ head: Inlet) -> Bool {
        isOfTheGame(head) && !rests(head) && !progress.left.contains(head.id)
    }

    func need(of head: Inlet) -> Tier {
        guard let content else { return .resting }
        return Play.need(site: head.id, progress: progress, now: now, rules: content.rules)
    }

    func crateParts(of head: Inlet) -> Int {
        guard let content else { return 0 }
        return Play.crateParts(need: need(of: head), world: content.world)
    }

    /// The visitor of this week in a zone, once the player has earned enough gear to be shown visitors.
    func visitor(in zone: String) -> (site: Inlet, keeper: Keeper)? {
        guard let content, showsVisitors else { return nil }
        if visitorsOf != week {
            visitorsOf = week
            visitors = [:]
            let places = drains.filter { invited.contains($0.id) }
            for zone in content.zones.zones {
                visitors[zone.id] = World.visitor(zone: zone.id, week: week, sites: places, keepers: content.keepers)
            }
        }
        return visitors[zone]
    }

    /// The keeper the player meets at a drain now.
    func keeper(at head: Inlet) -> Keeper? {
        guard let content, isOfTheGame(head) else { return nil }
        return Play.keeper(at: head, grates: grates(of: head), progress: progress, now: now, book: content.book, visitor: visitor(in: head.zone))
    }

    // MARK: what has opened up

    var hasMetAnyone: Bool { progress.hasMetAnyone }

    var showsNearby: Bool {
        progress.met.count >= (content?.world.stages.nearbyAfterMeetings ?? 1)
    }

    var showsJobs: Bool {
        progress.looked.count >= (content?.world.stages.jobsAfterDrains ?? 2)
    }

    var showsHunts: Bool {
        progress.looked.count >= (content?.world.stages.huntAfterLooks ?? 4)
    }

    var showsVisitors: Bool {
        guard let content else { return false }
        return Gear.owned(parts: progress.parts, in: content.gear).count - 1 >= content.world.stages.visitorAfterPieces
    }

    func opens(_ name: String) -> Bool {
        guard let content else { return false }
        return Gear.opens(name, parts: progress.parts, in: content.gear)
    }

    var standing: Standing? {
        content.map { Progression.standing(points: progress.points, in: $0.gear) }
    }

    /// How many drains of the game the player has found, of how many there are.
    var found: (known: Int, all: Int) {
        let all = drains
        return (all.filter { progress.known.contains($0.id) }.count, all.count)
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

    /// The drain the player stands at that still holds something, the chosen one first and else the nearest.
    var drainAtHand: Inlet? {
        guard let content, let fix = location.fix else { return nil }
        if let target, holds(target), case .inside = fence(of: target) { return target }
        return content.inlets.nearbySites(fix.coordinate, within: content.rules.fence.radiusM).first { holds($0.head) }.flatMap { near in
            if case .inside = fence(of: near.head) { return near.head }
            return nil
        }
    }

    // MARK: the map

    /// The player moved. Open the veil around them, find the drains under it, and listen again.
    func moved() {
        guard let content, let grid, let fix = location.fix else {
            reading = Detector.read(here: nil, inPlay: false, things: [], rangeM: 0, fenceM: 0)
            return
        }
        let radius = opens("wide_veil") ? content.world.veil.bootsOpenM : content.world.veil.openM
        let fresh = Veil.open(&progress.openCells, around: fix.coordinate, radiusM: radius, grid: grid)
        if fresh > 0 {
            var uncovered = 0
            for near in content.inlets.nearbySites(fix.coordinate, within: radius + 2 * content.world.veil.cellM)
            where isOfTheGame(near.head) && !progress.known.contains(near.head.id) && Veil.isOpen(near.head.coordinate, cells: progress.openCells, grid: grid) {
                progress.known.insert(near.head.id)
                uncovered += 1
            }
            if uncovered > 0 && hasMetAnyone { sound.play("uncover", volume: 0.5) }
            if showsJobs { payJobs(Jobs.record(.cells(fresh), in: &progress.jobs, day: today)) }
            redrawVeil()
            unsaved += 1
            if unsaved >= 12 { save() }
        }
        listen()
    }

    private func redrawVeil() {
        guard let grid else { return }
        veil = Veil.rings(of: progress.openCells, grid: grid)
        veilVersion += 1
    }

    /// Read the detector and the shadows of the keepers near.
    func listen() {
        guard let content, let fix = location.fix else { return }
        let range = opens("long_range") ? content.world.detector.longRangeM : content.world.detector.rangeM
        let near = content.inlets.nearbySites(fix.coordinate, within: max(range * 2, content.world.nearby.radiusM)).filter { holds($0.head) }
        var things = near.map { Findable(site: $0.head.id, at: $0.head.coordinate, kind: keeper(at: $0.head)?.kind) }
        if !hasMetAnyone, let first = things.first { things = [first] }
        let inPlay = content.zones.zone(containing: fix.coordinate).map { $0.isActive(on: today) } ?? false
        reading = Detector.read(here: fix.coordinate, inPlay: inPlay, things: things, rangeM: range, fenceM: content.rules.fence.radiusM, hunted: progress.hunt?.site)
        if showsNearby {
            let slots = opens("more_shadows") ? content.world.nearby.vestSlots : content.world.nearby.slots
            shadows = near.filter { $0.distanceM <= content.world.nearby.radiusM }.compactMap { place in
                keeper(at: place.head).map { Shadow(head: place.head, keeper: $0, met: progress.met.contains($0.id), distanceM: place.distanceM) }
            }.prefix(slots).map { $0 }
        } else {
            shadows = []
        }
    }

    /// The drains to draw inside a box of the map. Only drains the player has found are drawn, and what a drain
    /// holds shows only near the player. Before the first meeting only the one nearest drain is drawn at all.
    func tokens(west: Double, south: Double, east: Double, north: Double, limit: Int = 150) -> [Token] {
        guard let content else { return [] }
        let here = location.fix?.coordinate
        var inside = drains.filter { $0.lon >= west && $0.lon <= east && $0.lat >= south && $0.lat <= north && progress.known.contains($0.id) }
        if !hasMetAnyone {
            guard let here else { return [] }
            inside = inside.filter { holds($0) }.min { Geo.distance(here, $0.coordinate) < Geo.distance(here, $1.coordinate) }.map { [$0] } ?? []
        }
        let middle = Coordinate(lon: (west + east) / 2, lat: (south + north) / 2)
        let shown = inside.count <= limit ? inside : Array(inside.sorted { Geo.distance(middle, $0.coordinate) < Geo.distance(middle, $1.coordinate) }.prefix(limit))
        return shown.map { head in
            if rests(head) { return Token(head: head, state: .resting) }
            guard let here, !progress.left.contains(head.id), Geo.distance(here, head.coordinate) <= content.world.senseM else { return Token(head: head, state: .plain) }
            let who = keeper(at: head)
            return Token(head: head, state: .holds(keeper: who?.id, met: who.map { progress.met.contains($0.id) } ?? false, crate: crateParts(of: head)))
        }
    }

    /// What the map draws above the veil, the keepers that wait for the player and the visitor of the week.
    var invitations: [Invitation] {
        guard let content else { return [] }
        var out: [Invitation] = []
        for waits in progress.waiting {
            guard let head = content.inlets[waits.site], let keeper = content.book.keeper(waits.keeper), holds(head) else { continue }
            out.append(Invitation(head: head, keeper: keeper, showsKeeper: opens("near_slip") || progress.met.contains(keeper.id), isVisitor: false))
        }
        for zone in content.zones.zones {
            guard let visit = visitor(in: zone.id), holds(visit.site), !progress.visitorsMet.contains("\(week)|\(zone.id)") else { continue }
            out.append(Invitation(head: visit.site, keeper: visit.keeper, showsKeeper: progress.met.contains(visit.keeper.id), isVisitor: true))
        }
        return out
    }

    /// The streets of the game with how many of their drains the player has looked at, the most complete first.
    var streets: [(road: String, looked: Int, all: Int)] {
        let looked = progress.looked
        var count: [String: (looked: Int, all: Int)] = [:]
        for head in drains where !head.road.isEmpty {
            count[head.road, default: (0, 0)].all += 1
            if looked.contains(head.id) { count[head.road, default: (0, 0)].looked += 1 }
        }
        return count.map { (road: $0.key, looked: $0.value.looked, all: $0.value.all) }
            .sorted { ($0.looked > 0 ? 0 : 1, -Double($0.looked) / Double($0.all), $0.road) < ($1.looked > 0 ? 0 : 1, -Double($1.looked) / Double($1.all), $1.road) }
    }

    // MARK: a meeting

    func plan(for head: Inlet) -> MeetingPlan? {
        guard let content else { return nil }
        var who = keeper(at: head)
        #if DEBUG
        if let asked = opening.keeper, let forced = content.book.keeper(asked) { who = forced }
        #endif
        let misses = Play.misses(at: head.id, progress: progress, now: now, rules: content.rules)
        let first = !hasMetAnyone
        let timeline = first || who == nil ? Timeline.sitting() : Timeline.make(seed: "\(head.id)|\(today)|\(misses)", timing: who!.timing)
        return MeetingPlan(head: head, keeper: who, timeline: timeline, isFirst: first, misses: misses, crateParts: crateParts(of: head),
                           aimDeg: Judge.tolerance(rule: content.world.catching, wide: opens("wide_aim")), pulse: opens("pulse"), easy: progress.easyCatch)
    }

    /// Count a miss at a drain. Returns how many the player has there today.
    func missed(at head: Inlet) -> Int {
        guard let content else { return 0 }
        progress = Play.missed(at: head.id, progress: progress, now: now, rules: content.rules)
        save()
        return Play.misses(at: head.id, progress: progress, now: now, rules: content.rules)
    }

    /// Settle a meeting at a drain and keep it.
    func settle(_ head: Inlet, keeper: Keeper?, outcome: Outcome) -> MeetingResult? {
        guard let content else { return nil }
        var slipTo: Inlet?
        if outcome == .slipped {
            let reach = opens("near_slip") ? content.world.slip.wheelMaxM : content.world.slip.maxM
            let taken = Set(progress.waiting.map(\.site))
            let others = content.inlets.nearbySites(head.coordinate, within: content.world.slip.maxM)
                .filter { $0.head.id != head.id && holds($0.head) && invites($0.head) && !taken.contains($0.head.id) }
            slipTo = World.slipTarget(among: others, minM: content.world.slip.minM, maxM: reach) ?? World.slipTarget(among: others, minM: content.world.slip.minM, maxM: content.world.slip.maxM)
        }
        let levelBefore = standing?.level ?? 1
        let (result, grown) = Play.settle(site: head, keeper: keeper, outcome: outcome, slipTo: slipTo, progress: progress, now: now, book: content.book)
        progress = grown
        if let slipTo { progress.known.insert(slipTo.id) }
        if target?.id == head.id { target = nil }
        if outcome == .slipped, !progress.easyOffered {
            progress.easyOffered = true
            announce("Too quick for you? Easy catch in the settings makes every aimed throw land.")
        }
        refreshJobs()
        openHunt()
        tellWhatIsNew(levelBefore: levelBefore)
        for piece in result.finished { announce("\(piece.name) finished. \(piece.says)") }
        save()
        moved()
        return result
    }

    // MARK: jobs, hunts and what is new

    private func payJobs(_ finished: [Job]) {
        guard let content, !finished.isEmpty else { return }
        let handed = Gear.add(finished.count, to: &progress.parts, pinned: progress.pinned, in: content.gear)
        progress.bonusPoints += handed.over * content.world.points.thanks
        let piece = handed.filled.last?.piece.name
        announce("Job done: \(finished[0].text). \(piece.map { "A part for your \($0.lowercased())." } ?? "The crew says thank you.")")
        sound.play("piece", volume: 0.6)
    }

    /// The kinds of jobs that can be done today near where the player is and has been.
    private var possibleJobs: Set<String> {
        guard let content, let fix = location.fix else { return ["looks", "cells"] }
        var kinds: Set<String> = ["looks", "cells"]
        let near = content.inlets.nearbySites(fix.coordinate, within: content.world.jobs.reachM).filter { isOfTheGame($0.head) }
        if near.contains(where: { !progress.looked.contains($0.head.id) }) { kinds.insert("new_sites") }
        if near.contains(where: { place in holds(place.head) && keeper(at: place.head).map { !progress.met.contains($0.id) } == true }) { kinds.insert("new_keeper") }
        if hasMetAnyone { kinds.insert("seal") }
        return kinds
    }

    func refreshJobs() {
        guard let content, showsJobs else { return }
        let before = progress.jobs
        progress.jobs = Jobs.refresh(progress.jobs, day: today, rules: content.jobs, possible: possibleJobs, slots: content.world.jobs.slots)
        if before.isEmpty && !progress.jobs.isEmpty { tell("jobs", "The crew has small jobs for you. A finished job pays a part of gear. They are in your journal.") }
    }

    var canSwapJob: Bool { progress.swappedOn != today }

    func swapJob(at index: Int) {
        guard let content, canSwapJob, let changed = Jobs.swapped(progress.jobs, at: index, day: today, rules: content.jobs, possible: possibleJobs) else { return }
        progress.jobs = changed
        progress.swappedOn = today
        save()
    }

    /// Open a hunt when a rare keeper the player never met lives a short walk away. The hint is true, because it
    /// is worked out from where that keeper is this week.
    private func openHunt() {
        guard let content, showsHunts, let fix = location.fix else { return }
        if let hunt = progress.hunt, hunt.week != week || content.inlets[hunt.site].map({ !holds($0) }) == true { progress.hunt = nil }
        guard progress.hunt == nil, progress.huntOpenedOn != today else { return }
        let rule = content.world.hunt
        let found = content.inlets.nearbySites(fix.coordinate, within: rule.maxM).first { place in
            guard place.distanceM >= rule.minM, holds(place.head), invites(place.head), World.isRareHome(place.head, week: week, kinds: content.world.kinds) else { return false }
            guard let who = keeper(at: place.head) else { return false }
            return who.kind == "rare" && !progress.met.contains(who.id)
        }
        guard let found, let who = keeper(at: found.head) else { return }
        progress.hunt = Hunt(keeper: who.id, site: found.head.id, week: week)
        progress.huntOpenedOn = today
        announce(Words.hint(road: found.head.road, bearing: found.bearing))
    }

    /// The sentence of the open hunt, for the journal and the map.
    var huntLine: String? {
        guard let content, let hunt = progress.hunt, let head = content.inlets[hunt.site], let fix = location.fix else { return nil }
        return Words.hint(road: head.road, bearing: Geo.bearing(from: fix.coordinate, to: head.coordinate))
    }

    private func tellWhatIsNew(levelBefore: Int) {
        if showsNearby { tell("nearby", "New on the map: shadows of the keepers near you. Tap one and the arrow leads you there.") }
        if showsVisitors { tell("visitor", "A visitor is in town this week. Its light shows on the map, also where you have not walked yet.") }
        if let level = standing?.level, level > levelBefore { sound.play("level", volume: 0.7) }
    }

    /// Say something once in the life of this progress.
    private func tell(_ key: String, _ text: String) {
        guard !progress.told.contains(key) else { return }
        progress.told.insert(key)
        announce(text)
    }

    /// Say a sentence on the map for a while. Sentences wait their turn, so that two things that happen at once
    /// are both read, one after the other.
    func announce(_ text: String) {
        guard !unsaid.contains(text), announcement != text else { return }
        unsaid.append(text)
        if announcement == nil { sayNext() }
    }

    private func sayNext() {
        guard !inMeeting, announcement == nil, !unsaid.isEmpty else { return }
        let said = unsaid.removeFirst()
        announcement = said
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(7))
            if self?.announcement == said {
                self?.announcement = nil
                self?.sayNext()
            }
        }
    }

    func dismissAnnouncement() {
        announcement = nil
        sayNext()
    }

    /// One line about the next thing within reach, for the end of a result.
    var nextUp: String? {
        if let waits = invitations.first(where: { !$0.isVisitor }), let far = distance(to: waits.head) {
            return "A keeper that slipped away waits \(Words.distance(far)) from here."
        }
        if let hunt = huntLine { return hunt }
        if let stranger = shadows.first(where: { !$0.met }) { return "Someone you have not met is \(Words.distance(stranger.distanceM)) away." }
        if let near = shadows.first { return "\(near.keeper.name) is \(Words.distance(near.distanceM)) away." }
        switch reading.state {
        case .signal, .atDrain: return reading.distanceM.map { "The detector has something \(Words.distance($0)) away." }
        default: return "Quiet here. The needle will swing again as you walk on."
        }
    }

    // MARK: choices of the player

    func choose(figure: String) {
        progress.figure = figure
        save()
    }

    func pin(_ piece: String?) {
        progress.pinned = piece
        save()
    }

    func befriend(_ keeper: String?) {
        progress.friend = keeper
        save()
    }

    /// Leave a drain alone. It is passed over by the detector and the shadows, and whoever waited there goes home.
    func leave(_ head: Inlet) {
        progress.left.insert(head.id)
        progress.waiting.removeAll { $0.site == head.id }
        if progress.hunt?.site == head.id { progress.hunt = nil }
        if target?.id == head.id { target = nil }
        save()
        listen()
    }

    func set(easyCatch: Bool? = nil, sound soundOn: Bool? = nil, ticks ticksOn: Bool? = nil) {
        if let easyCatch { progress.easyCatch = easyCatch }
        if let soundOn {
            progress.sound = soundOn
            sound.isOn = soundOn
        }
        if let ticksOn {
            progress.ticks = ticksOn
            haptics.isOn = ticksOn
        }
        save()
    }

    func save() {
        store.save(progress)
        unsaved = 0
    }

    // MARK: the detector's ticking

    /// Tick while something is within reach, faster the nearer it is. Every tick is a sound, a tick in the hand
    /// and a kick of the needle on the screen, so that it is felt, heard or seen.
    func startTicking() {
        guard ticking == nil, let content else { return }
        ticking = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let reading = self.reading
                if !self.inMeeting, reading.state == .signal || reading.state == .atDrain {
                    self.ticks += 1
                    self.sound.play("tick", volume: Float(0.25 + 0.5 * reading.strength))
                    self.haptics.tick(strength: 0.3 + 0.7 * reading.strength)
                    try? await Task.sleep(for: .seconds(Detector.tickEvery(strength: reading.strength, rule: content.world.detector)))
                } else {
                    try? await Task.sleep(for: .seconds(0.5))
                }
            }
        }
    }

    // MARK: playing at a desk

    /// Put the player a few steps from a drain, as if they had walked there.
    func stand(at head: Inlet) {
        walking?.cancel()
        isWalking = false
        location.standIn = Fix(coordinate: Coordinate(lon: head.lon + 0.00003, lat: head.lat - 0.00003), accuracyM: 5)
        moved()
    }

    /// Walk to a place at a brisk pace, so that the veil opens along the way as it would on a real walk.
    func walk(to goal: Coordinate, metresPerSecond: Double = 12) {
        walking?.cancel()
        guard let from = location.fix?.coordinate else {
            location.standIn = Fix(coordinate: goal, accuracyM: 5)
            moved()
            return
        }
        let total = Geo.distance(from, goal)
        guard total > 1 else { return }
        location.standInCourse = Geo.bearing(from: from, to: goal)
        isWalking = true
        walking = Task { [weak self] in
            let step = 0.2
            var gone = 0.0
            while gone < total, !Task.isCancelled {
                gone = min(total, gone + metresPerSecond * step)
                let part = gone / total
                self?.location.standIn = Fix(coordinate: Coordinate(lon: from.lon + (goal.lon - from.lon) * part, lat: from.lat + (goal.lat - from.lat) * part), accuracyM: 5)
                self?.moved()
                try? await Task.sleep(for: .seconds(step))
            }
            if !Task.isCancelled {
                self?.isWalking = false
                self?.save()
            }
        }
    }

    #if DEBUG
    /// Jump into a zone, to its drain nearest the middle.
    func jump(to zone: String) {
        let here = drains.filter { $0.zone == zone }
        guard !here.isEmpty else { return }
        let middle = Coordinate(lon: here.map(\.lon).reduce(0, +) / Double(here.count), lat: here.map(\.lat).reduce(0, +) / Double(here.count))
        if let head = here.min(by: { Geo.distance(middle, $0.coordinate) < Geo.distance(middle, $1.coordinate) }) { stand(at: head) }
    }

    /// The drain of this week's visitor in the zone the player stands in, or in the first zone.
    var visitorOfMyZone: (site: Inlet, keeper: Keeper)? {
        guard let content else { return nil }
        let mine = location.fix.flatMap { content.zones.zone(containing: $0.coordinate)?.id } ?? content.zones.zones.first?.id ?? ""
        return visitor(in: mine)
    }

    func skip(days: Int) {
        clockOffset += Double(days) * SpawnRules.secondsPerDay
        refreshJobs()
        listen()
    }

    func startOver() {
        walking?.cancel()
        isWalking = false
        store.erase()
        progress = PlayerProgress()
        clockOffset = 0
        target = nil
        announcement = nil
        location.standIn = Fix(coordinate: Coordinate(lon: -74.672675, lat: 40.356792), accuracyM: 5)
        redrawVeil()
        moved()
    }

    private func applyLaunchArguments() {
        let asked = UserDefaults.standard
        if asked.bool(forKey: "igo.reset") {
            store.erase()
            progress = PlayerProgress()
        }
        if let day = asked.string(forKey: "igo.day"), let wanted = try? Date("\(day)T12:00:00-05:00", strategy: .iso8601) {
            clockOffset = wanted.timeIntervalSinceNow
        }
        if let figure = asked.string(forKey: "igo.figure") { progress.figure = figure }
        if let count = Int(asked.string(forKey: "igo.fill") ?? ""), let content {
            // A number of made up looks, so that later stages of the game can be looked at without playing to them.
            var filled = PlayerProgress()
            filled.figure = progress.figure ?? "a"
            let start = now.addingTimeInterval(-3 * SpawnRules.secondsPerDay)
            let from = Coordinate(lon: -74.672675, lat: 40.356792)
            let heads = content.inlets.heads.filter { content.zones.canBeCaught($0, on: today) }.sorted { Geo.distance(from, $0.coordinate) < Geo.distance(from, $1.coordinate) }
            for (k, head) in heads.prefix(count).enumerated() {
                let at = start.addingTimeInterval(Double(k) * 240)
                let who = Play.keeper(at: head, grates: 1, progress: filled, now: at, book: content.book)
                (_, filled) = Play.settle(site: head, keeper: who, outcome: k % 4 == 1 ? .mastered : .caught, progress: filled, now: at, book: content.book)
                if let grid { Veil.open(&filled.openCells, around: head.coordinate, radiusM: content.world.veil.openM, grid: grid) }
            }
            progress = filled
        }
        if asked.string(forKey: "igo.gear") == "all", let content {
            for piece in content.gear.pieces { progress.parts[piece.id] = piece.parts }
        }
        if let site = asked.string(forKey: "igo.stand"), let head = content?.inlets[site] {
            location.standIn = Fix(coordinate: Coordinate(lon: head.lon + 0.00003, lat: head.lat - 0.00003), accuracyM: 5)
        }
        if asked.string(forKey: "igo.stand") == "visitor", let visit = visitor(in: "west") {
            // Sixty metres short of the visitor's drain, so that its light is seen from a little way off.
            location.standIn = Fix(coordinate: Coordinate(lon: visit.site.lon + 0.0007, lat: visit.site.lat - 0.0002), accuracyM: 5)
        }
        if let place = asked.string(forKey: "igo.walk")?.split(separator: ",").compactMap({ Double($0) }), place.count == 2 {
            location.standIn = Fix(coordinate: Coordinate(lon: place[1], lat: place[0]), accuracyM: 5)
        }
        opening = Opening(tab: asked.string(forKey: "igo.tab"), select: asked.string(forKey: "igo.select"), encounter: asked.string(forKey: "igo.encounter"),
                          keeper: asked.string(forKey: "igo.keeper"), moment: asked.string(forKey: "igo.moment"),
                          spike: asked.string(forKey: "igo.spike"), freeze: asked.string(forKey: "igo.freeze"))
    }
    #endif
}
