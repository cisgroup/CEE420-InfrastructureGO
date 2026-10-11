import Foundation

/// The tier of a drain and the points of a catch. The server decides both when a report arrives. The phone
/// computes the same answer beforehand to draw the map and to show a result while it is offline.
nonisolated enum SpawnRules {
    static let secondsPerDay = 86_400.0

    /// The tier of a drain for one player at one instant.
    ///
    /// The drain rests when the player already reported it on the same local day. Otherwise it is rare during a
    /// storm window, rare when nobody ever reported it, and after that its tier follows the elapsed time since
    /// the last report by anyone. A last report stamped after now counts as an age of zero.
    static func tier(now: Date, lastAnyAt: Date?, myLastAt: Date?, stormOpen: Bool, rules: GameRules, days: LocalDays? = nil) -> Tier {
        let days = days ?? rules.days
        if let mine = myLastAt, days.day(of: mine) == days.day(of: now) { return .resting }
        guard !stormOpen, let last = lastAnyAt else { return .rare }
        let age = max(0, now.timeIntervalSince(last))
        let byAge = rules.tiers
            .compactMap { rule in rule.minAgeDays.map { (tier: rule.tier, minAge: $0 * secondsPerDay) } }
            .sorted { $0.minAge > $1.minAge }
        for rule in byAge where age >= rule.minAge {
            return Tier(rawValue: rule.tier) ?? .common
        }
        return .common
    }

    /// The points of a catch. A great catch adds its bonus at every tier but the resting one.
    static func points(tier: Tier, greatCatch: Bool, rules: GameRules) -> Int {
        let base = rules.tiers.first { $0.tier == tier.rawValue }?.points ?? 0
        return base + (greatCatch && tier > .resting ? rules.greatCatch.points : 0)
    }
}

/// Whether the player stands close enough to a drain to catch there.
nonisolated enum FenceState: Sendable, Equatable {
    case noFix
    case walkCloser(distanceM: Double)
    case roughFix(accuracyM: Double)
    case inside(distanceM: Double)
}

nonisolated enum Fence {
    /// The state of the fence from the distance to the targeted drain and the accuracy of the fix. A player who
    /// is far away is told to walk, whatever the accuracy. A player who is near with a rough fix is told to wait.
    static func state(distanceM: Double?, accuracyM: Double?, rules: GameRules) -> FenceState {
        guard let distance = distanceM, let accuracy = accuracyM, accuracy >= 0 else { return .noFix }
        if distance > rules.fence.radiusM { return .walkCloser(distanceM: distance) }
        if accuracy > rules.fence.maxAccuracyM { return .roughFix(accuracyM: accuracy) }
        return .inside(distanceM: distance)
    }
}
