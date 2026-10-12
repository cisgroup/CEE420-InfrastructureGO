import UIKit

/// The ticks in the hand. A simulator has no such thing, so nothing in the game depends on them.
final class Haptics {
    var isOn = true
    private(set) var last = ""
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let notice = UINotificationFeedbackGenerator()

    /// A light tick, for the detector.
    func tick(strength: Double = 0.6) {
        last = "tick"
        guard isOn else { return }
        light.impactOccurred(intensity: max(0.2, min(1, strength)))
    }

    /// The marker lands.
    func tap() {
        last = "tap"
        guard isOn else { return }
        medium.impactOccurred()
    }

    /// Something with weight, a keeper landing or a seal.
    func thud() {
        last = "thud"
        guard isOn else { return }
        heavy.impactOccurred()
    }

    func success() {
        last = "success"
        guard isOn else { return }
        notice.notificationOccurred(.success)
    }

    func warning() {
        last = "warning"
        guard isOn else { return }
        notice.notificationOccurred(.warning)
    }

    func ready() {
        medium.prepare()
        heavy.prepare()
    }
}
