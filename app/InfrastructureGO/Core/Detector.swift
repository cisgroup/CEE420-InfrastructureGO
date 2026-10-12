import Foundation

/// What the detector says at a moment.
nonisolated struct Reading: Sendable, Equatable {
    nonisolated enum State: Sendable, Equatable {
        case noFix          // the phone does not know where it is
        case outside        // the player stands outside the play area
        case quiet          // nothing within reach still holds something
        case signal         // something is within reach
        case atDrain        // the player stands at a drain that holds something
    }

    let state: State
    let site: String?
    let distanceM: Double?
    let bearing: Double?        // degrees clockwise from north toward the thing
    let strength: Double        // from 0, nothing, to 1, standing on it
    let kind: String?           // the kind of the keeper there, which only the tuned coil shows

    static let nothing = Reading(state: .quiet, site: nil, distanceM: nil, bearing: nil, strength: 0, kind: nil)
}

/// A drain the detector can find, with the kind of keeper it holds today.
nonisolated struct Findable: Sendable, Equatable {
    let site: String
    let at: Coordinate
    let kind: String?
}

/// The detector, the worker's pipe locator. It points at the nearest drain that still holds something, also under
/// the veil, which is what pulls a player into streets they do not know.
nonisolated enum Detector {
    /// - Parameters:
    ///   - things: the drains that still hold something for this player today.
    ///   - justLooked: the place of the drain the player looked at last. Drains near it are passed over until
    ///     the player has moved on, because they are mostly the pair on the opposite kerb, which the fence
    ///     already reaches from this side.
    ///   - hunted: the drain of an open hunt, which is found from twice the range.
    static func read(here: Coordinate?, inPlay: Bool, things: [Findable], rangeM: Double, fenceM: Double,
                     justLooked: Coordinate? = nil, quietM: Double = 0, hunted: String? = nil) -> Reading {
        guard let here else { return Reading(state: .noFix, site: nil, distanceM: nil, bearing: nil, strength: 0, kind: nil) }
        var best: (thing: Findable, distance: Double, reach: Double)?
        for thing in things {
            if let justLooked, Geo.distance(justLooked, thing.at) <= quietM { continue }
            let reach = thing.site == hunted ? rangeM * 2 : rangeM
            let distance = Geo.distance(here, thing.at)
            guard distance <= reach else { continue }
            if let known = best, (known.distance / known.reach, known.thing.site) <= (distance / reach, thing.site) { continue }
            best = (thing, distance, reach)
        }
        guard let found = best else {
            return Reading(state: inPlay ? .quiet : .outside, site: nil, distanceM: nil, bearing: nil, strength: 0, kind: nil)
        }
        return Reading(state: found.distance <= fenceM ? .atDrain : .signal, site: found.thing.site, distanceM: found.distance,
                       bearing: Geo.bearing(from: here, to: found.thing.at), strength: max(0, min(1, 1 - found.distance / found.reach)), kind: found.thing.kind)
    }

    /// The seconds between two ticks. A stronger reading ticks faster.
    static func tickEvery(strength: Double, rule: WorldRules.DetectorRule) -> Double {
        let s = max(0, min(1, strength))
        return rule.slowTickS + (rule.fastTickS - rule.slowTickS) * s * s.squareRoot()
    }
}
