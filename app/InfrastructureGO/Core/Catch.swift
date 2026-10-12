import Foundation

/// What a keeper is doing at a moment of a meeting.
nonisolated enum Phase: String, Sendable, Equatable {
    case watch      // it sits on the grate and looks at the player
    case tell       // it gives its tell, a crouch for the frog, and is still on the grate
    case air        // it has left its place and is on the way to the next
    case settle     // it has just landed
    case hidden     // it is under the grate
}

/// One stretch of a keeper's behaviour. Spot is where it is, next where it is going during a tell or in the air.
nonisolated struct Beat: Sendable, Equatable {
    let phase: Phase
    let start: Double
    let end: Double
    let spot: Int
    let next: Int
}

/// How a keeper behaves through a meeting, laid out ahead of time from a seed. The same drain, day and attempt
/// give the same behaviour, so a throw can be judged again and tested.
nonisolated struct Timeline: Sendable, Equatable {
    let beats: [Beat]
    let spots: Int

    var length: Double { beats.last?.end ?? 0 }

    /// The behaviour of a keeper for a good while, after which it starts over.
    static func make(seed: String, timing: Keeper.Timing, spots: Int = 3, seconds: Double = 90) -> Timeline {
        var beats: [Beat] = []
        var clock = 0.0
        var spot = Hash.index("\(seed)|start", count: spots)
        var round = 0
        let shortest = timing.watchS.first ?? 1.5
        let longest = timing.watchS.last ?? shortest
        func add(_ phase: Phase, _ long: Double, to next: Int) {
            guard long > 0 else { return }
            beats.append(Beat(phase: phase, start: clock, end: clock + long, spot: spot, next: next))
            clock += long
        }
        while clock < seconds {
            add(.watch, shortest + (longest - shortest) * Hash.unit("\(seed)|watch|\(round)"), to: spot)
            if timing.feintEvery > 0 && round % timing.feintEvery == timing.feintEvery - 1 {
                // A feint. The keeper gives its tell and stays where it is.
                add(.tell, timing.tellS, to: spot)
            } else {
                let next = spots > 1 ? (spot + 1 + Hash.index("\(seed)|hop|\(round)", count: spots - 1)) % spots : spot
                add(.tell, timing.tellS, to: next)
                add(.air, timing.airS, to: next)
                spot = next
                add(.settle, timing.settleS, to: spot)
                if timing.hideEvery > 0 && round % timing.hideEvery == timing.hideEvery - 1 {
                    add(.hidden, timing.hideS, to: spot)
                }
            }
            round += 1
        }
        return Timeline(beats: beats, spots: spots)
    }

    /// A keeper that only sits and watches, for a player's very first meeting.
    static func sitting(spot: Int = 1, spots: Int = 3, seconds: Double = 3600) -> Timeline {
        Timeline(beats: [Beat(phase: .watch, start: 0, end: seconds, spot: spot, next: spot)], spots: spots)
    }

    /// What the keeper is doing at a time. Past its end the behaviour starts over.
    func beat(at time: Double) -> Beat {
        guard let last = beats.last, last.end > 0 else { return Beat(phase: .watch, start: 0, end: 1, spot: 0, next: 0) }
        let turns = (max(0, time) / last.end).rounded(.down)
        let inside = max(0, time) - turns * last.end
        let found = beats.first { inside < $0.end } ?? last
        return Beat(phase: found.phase, start: found.start + turns * last.end, end: found.end + turns * last.end, spot: found.spot, next: found.next)
    }

    /// The share of the time the keeper is on the grate, where an aimed throw wins it.
    var sittingShare: Double {
        guard length > 0 else { return 1 }
        let sitting = beats.filter { $0.phase == .watch || $0.phase == .tell || $0.phase == .settle }.reduce(0) { $0 + ($1.end - $1.start) }
        return sitting / length
    }
}

/// What a throw was aimed at.
nonisolated enum Aim: Sendable, Equatable {
    case keeper
    case patch
    case nothing
}

/// What a throw came to.
nonisolated enum Throw: Sendable, Equatable {
    case short          // the swipe was too short to be a throw
    case wide           // it flew past everything
    case gone           // it landed where the keeper had just been, or the keeper was under the grate
    case caught         // it landed at the keeper's feet and the keeper accepted
    case mastered       // it lay on the landing patch before the keeper landed there

    var isMiss: Bool { self == .short || self == .wide || self == .gone }
}

/// The judge of a throw. Nothing here is physics. The result follows from what the keeper was doing when the
/// finger let go and from where the swipe pointed, so the same throw always gives the same result.
nonisolated enum Judge {
    /// What a swipe points at. The swipe and the places are in screen points with y growing downward. The swipe
    /// starts at the marker's resting place. Of the keeper and the landing patch, the one the swipe points at more
    /// closely is meant, and neither when both lie outside the tolerance.
    static func aim(swipeDX: Double, swipeDY: Double, restX: Double, restY: Double, keeperX: Double, keeperY: Double,
                    patch: (x: Double, y: Double)?, toleranceDeg: Double) -> Aim {
        func off(_ x: Double, _ y: Double) -> Double {
            let ax = x - restX, ay = y - restY
            let swipe = (swipeDX * swipeDX + swipeDY * swipeDY).squareRoot()
            let reach = (ax * ax + ay * ay).squareRoot()
            guard swipe > 0, reach > 0 else { return 180 }
            return acos(max(-1, min(1, (swipeDX * ax + swipeDY * ay) / (swipe * reach)))) * 180 / .pi
        }
        let toKeeper = off(keeperX, keeperY)
        let toPatch = patch.map { off($0.x, $0.y) } ?? 360
        if min(toKeeper, toPatch) > toleranceDeg { return .nothing }
        return toPatch < toKeeper ? .patch : .keeper
    }

    /// What a throw comes to.
    ///
    /// A keeper that sits on the grate when the finger lets go stays until the marker lands, so an aimed throw
    /// at a sitting keeper always wins it. During its tell and while it is in the air a patch shows where it will
    /// land. A marker thrown onto that patch is the mastered catch when it gets there before the keeper does, and
    /// an ordinary catch when the keeper is already down. A throw at the place a keeper has left, or at a keeper
    /// under the grate, is a miss. With the easy catch every aimed throw wins the keeper.
    static func judge(release: Double, timeline: Timeline, aim: Aim, swipePt: Double, rule: WorldRules.CatchRule, easy: Bool = false) -> Throw {
        guard swipePt >= rule.minSwipePt else { return .short }
        guard aim != .nothing else { return .wide }
        let beat = timeline.beat(at: release)
        let leaving = beat.next != beat.spot
        switch beat.phase {
        case .watch, .settle:
            return .caught
        case .tell:
            return aim == .patch && leaving ? .mastered : .caught
        case .air:
            if aim == .patch { return release + rule.flightS <= beat.end + rule.graceS ? .mastered : .caught }
            return easy ? .caught : .gone
        case .hidden:
            return easy ? .caught : .gone
        }
    }

    /// The tolerance of the aim with and without the wide marker.
    static func tolerance(rule: WorldRules.CatchRule, wide: Bool) -> Double {
        wide ? rule.wideAimDeg : rule.aimDeg
    }
}
