import Foundation

/// The shrinking ring of the encounter and what a throw comes to. Nothing here is physics. The result of a throw
/// follows from the swipe and the size of the ring at that moment, so the same swipe always gives the same result.
nonisolated enum Ring {
    /// The size of the ring a while after it started, from its start scale down to its end scale and around again.
    static func scale(elapsed: TimeInterval, rules: GameRules.Ring) -> Double {
        guard rules.periodS > 0 else { return rules.endScale }
        let phase = max(0, elapsed).truncatingRemainder(dividingBy: rules.periodS) / rules.periodS
        return rules.startScale + (rules.endScale - rules.startScale) * phase
    }
}

nonisolated enum ThrowOutcome: Sendable, Equatable {
    case miss
    case hit(great: Bool)
}

nonisolated enum Throwing {
    /// What a throw comes to.
    ///
    /// The swipe and the aim are in screen points with y growing downwards. The aim is the way from where the
    /// swipe began to the creature. A throw lands when the swipe is long enough and points at the creature within
    /// the tolerance. The last throw always lands, so that no walk to a drain is wasted. Only the first throw can
    /// be a great catch, and only while the ring is small.
    static func outcome(throwNumber: Int, swipeDX: Double, swipeDY: Double, aimDX: Double, aimDY: Double, ringScale: Double, rules: GameRules) -> ThrowOutcome {
        if throwNumber >= rules.throwing.count { return .hit(great: false) }
        let swipe = (swipeDX * swipeDX + swipeDY * swipeDY).squareRoot()
        let aim = (aimDX * aimDX + aimDY * aimDY).squareRoot()
        guard swipe >= rules.throwing.minSwipePt, aim > 0 else { return .miss }
        let cosine = max(-1, min(1, (swipeDX * aimDX + swipeDY * aimDY) / (swipe * aim)))
        let off = acos(cosine) * 180 / .pi
        guard off <= rules.throwing.aimToleranceDeg else { return .miss }
        return .hit(great: throwNumber == 1 && ringScale <= rules.greatCatch.ringScaleMax)
    }
}
