import Foundation
import RealityKit
import UIKit

/// Something that happens on the stage. The view turns each into a sound, a tick in the hand and a line of its
/// log, so that every moment of a meeting can be heard, felt or read.
enum StageEvent: String, CaseIterable {
    case rattle, pop, tell, hop, land, hide, tap, accept, proud, refuse, slip, crate, open, part
}

/// Everything of a meeting that RealityKit shows: the keeper with its behaviour, the patch where it will land, the
/// marker once it lies on the ground, the crate, and the sparks. The stage knows no camera. It places things on
/// the ground of a host, which is a photograph in the simulator and will be the phone's camera later.
final class EncounterStage {
    let root = Entity()
    var onEvent: ((StageEvent) -> Void)?
    /// The time of the keeper's behaviour, which the judge reads when the finger lets go.
    private(set) var time = 0.0
    private(set) var isLive = false

    private let host: VirtualHost
    private let keeper: Keeper?
    private let timeline: Timeline
    private let pulse: Bool
    private var actor: KeeperActor?
    private let body = Entity()
    private let shade: ModelEntity
    private let patch: ModelEntity
    private let marker = Entity()
    private let crate = Entity()
    private let lid = Entity()
    private var sparks: [(part: ModelEntity, way: SIMD3<Float>, age: Double, life: Double)] = []
    private var parts: [(part: ModelEntity, from: SIMD3<Float>, start: Double)] = []

    private enum Mode { case waiting, entering, live, accepting, vaulting, refusing, slipping, gone }
    private var mode = Mode.waiting
    private var clock = 0.0
    private var since = 0.0
    private var running = false
    private var lastBeat: Beat?
    private var standing = 1
    private var awaitsLanding = false
    private var whenDone: (() -> Void)?
    private var doneAt = Double.infinity
    private var crateSince: Double?
    private var crateAt = SIMD3<Float>(0, 0, 0)
    private var lidSince: Double?
    private var markerSince: Double?
    private var markerFades = false
    private var said: Set<String> = []

    private let alongs = [-0.58, 0.0, 0.58]
    private let lean: Float = -0.3

    init(host: VirtualHost, plan: MeetingPlan) {
        self.host = host
        keeper = plan.keeper
        timeline = plan.timeline
        pulse = plan.pulse
        standing = plan.timeline.beat(at: 0).spot

        var dark = UnlitMaterial(color: .black)
        dark.blending = .transparent(opacity: 0.30)
        shade = ModelEntity(mesh: .generateCylinder(height: 0.002, radius: 0.16), materials: [dark])
        var glow = UnlitMaterial(color: UIColor(red: 0.95, green: 0.65, blue: 0.10, alpha: 1))
        glow.blending = .transparent(opacity: 0.55)
        patch = ModelEntity(mesh: .generateCylinder(height: 0.003, radius: 0.17), materials: [glow])
        patch.isEnabled = false
        shade.isEnabled = false
        body.isEnabled = false
        root.addChild(shade)
        root.addChild(patch)
        root.addChild(body)
        buildMarker()
        buildCrate()
    }

    /// Load the keeper's model. A keeper whose files are missing gets the round stand-in, so the meeting still plays.
    func load() async {
        guard let keeper else { return }
        if let loaded = await KeeperActor.load(keeper.model, heightM: keeper.heightM) {
            actor = loaded
            body.addChild(loaded.root)
        } else {
            body.addChild(CreatureFactory.fallback(heightM: keeper.heightM))
        }
    }

    // MARK: places

    func place(ofSpot spot: Int) -> SIMD3<Float> {
        host.place(along: alongs[max(0, min(alongs.count - 1, spot))], across: 0.1)
    }

    /// How high above the grate the keeper stays, which is not at all unless it flies.
    private var hover: SIMD3<Float> { [0, Float(keeper?.hoverM ?? 0), 0] }

    /// Where a marker thrown at the keeper comes to lie, a little in front of its feet.
    func placeInFront(ofSpot spot: Int) -> SIMD3<Float> {
        host.place(along: alongs[max(0, min(alongs.count - 1, spot))], across: 0.62)
    }

    /// The crate rises at the kerb, on the side of the grate where the keeper is not standing.
    private var cratePlace: SIMD3<Float> { host.place(along: standing >= 1 && body.isEnabled ? -0.6 : 0.6, across: -0.45) }

    private func turn(at place: SIMD3<Float>, lean: Float) -> simd_quatf {
        simd_quatf(angle: host.facing(from: place), axis: [0, 1, 0]) * simd_quatf(angle: lean, axis: [1, 0, 0])
    }

    private func clip(_ role: String) -> String? {
        guard let name = keeper?.clips[role], actor?.clips[name] != nil else { return nil }
        return name
    }

    private func say(_ event: StageEvent) {
        onEvent?(event)
    }

    // MARK: the meeting

    /// The grate rattles and the keeper pops out. A drain without a keeper has nothing to show here.
    func enter() {
        guard keeper != nil else {
            mode = .gone
            return
        }
        mode = .entering
        since = clock
        say(.rattle)
    }

    /// The finger let go of a throw that will win the keeper, so the keeper stays where it is until the marker lands.
    func holdStill() {
        guard mode == .live else { return }
        running = false
        let beat = timeline.beat(at: time)
        standing = beat.phase == .air ? beat.next : beat.spot
        patch.isEnabled = false
        if let idle = clip("idle") { actor?.play(idle, loop: true, fade: 0.15) }
    }

    /// The marker has landed. What follows depends on what the throw came to.
    func resolve(_ outcome: Throw, at place: SIMD3<Float>, done: @escaping () -> Void) {
        showMarker(at: place, fades: outcome.isMiss)
        say(.tap)
        whenDone = done
        switch outcome {
        case .caught:
            mode = .accepting
            since = clock
            running = false
            doneAt = clock + 2.1
        case .mastered:
            // The keeper is on its way. It lands on the marker, and that is the moment. A keeper that touched
            // down a blink before the marker is proud all the same.
            let beat = timeline.beat(at: time)
            if beat.phase == .settle || beat.phase == .watch {
                mode = .vaulting
                since = clock
                running = false
                standing = beat.spot
                patch.isEnabled = false
                doneAt = clock + 2.2
                burst(at: self.place(ofSpot: beat.spot) + [0, 0.1, 0], count: 22, colour: UIColor(red: 0.95, green: 0.65, blue: 0.10, alpha: 1), speed: 0.9)
            } else {
                awaitsLanding = true
                running = true
            }
        case .short, .wide, .gone:
            mode = .refusing
            since = clock
            doneAt = clock + 1.35
        }
    }

    /// The keeper slips away under the grate.
    func slip(done: @escaping () -> Void) {
        mode = .slipping
        since = clock
        running = false
        whenDone = done
        doneAt = clock + 1.0
        patch.isEnabled = false
        if let tell = clip("tell") { actor?.play(tell, loop: false, fade: 0.1, speed: 2) }
        say(.slip)
    }

    /// The crate rises at the kerb. A keeper that was won makes room for it.
    func showCrate() {
        crateAt = cratePlace
        crate.position = crateAt
        crate.orientation = simd_quatf(angle: host.facing(from: crateAt), axis: [0, 1, 0])
        crate.isEnabled = true
        crateSince = clock
        marker.isEnabled = false
        say(.crate)
    }

    /// The crate opens and its parts fly out. Calls back when the last part is gone.
    func openCrate(parts count: Int, done: @escaping () -> Void) {
        lidSince = clock
        say(.open)
        for k in 0..<max(0, count) {
            let piece = ModelEntity(mesh: .generateBox(size: 0.055, cornerRadius: 0.012), materials: [UnlitMaterial(color: UIColor(red: 0.95, green: 0.65, blue: 0.10, alpha: 1))])
            piece.isEnabled = false
            root.addChild(piece)
            parts.append((piece, crateAt + [Float(k - count / 2) * 0.03, 0.18, 0], clock + 0.3 + Double(k) * 0.22))
        }
        whenDone = done
        doneAt = clock + 0.3 + Double(count) * 0.22 + 0.75
        if mode == .accepting || mode == .vaulting, let goodbye = clip("goodbye") { actor?.play(goodbye, loop: false, fade: 0.2) }
    }

    // MARK: time

    /// One step of time, called for every frame.
    func tick(_ step: Double) {
        clock += step
        switch mode {
        case .waiting, .gone: break
        case .entering: stepEntrance()
        case .live: stepLive(step)
        case .accepting: stepAccepting()
        case .vaulting: stepVaulting()
        case .refusing: stepRefusing(step)
        case .slipping: stepSlipping()
        }
        stepMarker()
        stepCrate()
        stepSparks(step)
        if clock >= doneAt {
            doneAt = .infinity
            let call = whenDone
            whenDone = nil
            call?()
        }
    }

    private func once(_ key: String, _ work: () -> Void) {
        guard said.insert(key).inserted else { return }
        work()
    }

    private func stepEntrance() {
        let age = clock - since
        let place = place(ofSpot: standing)
        guard age >= 0.5 else { return }
        once("pop") {
            body.isEnabled = true
            shade.isEnabled = true
            say(.pop)
            if let leap = clip("leap") { actor?.play(leap, loop: false, fade: 0) }
            burst(at: place + [0, 0.05, 0], count: 10, colour: UIColor(white: 1, alpha: 1), speed: 0.5)
        }
        let part = Float(min(1, (age - 0.5) / 0.42))
        let grown = 1 + 2.70158 * pow(part - 1, 3) + 1.70158 * pow(part - 1, 2)      // rises past its size and settles back
        body.scale = [grown, grown, grown]
        body.position = place + hover + [0, 0.14 * sin(part * .pi) - 0.1 * (1 - part), 0]
        body.orientation = turn(at: place, lean: lean)
        shade.position = [place.x, 0.004, place.z]
        if age >= 0.95 { once("landed") { if let land = clip("land") { actor?.play(land, loop: false, fade: 0.05) } } }
        if age >= 1.3 {
            mode = .live
            isLive = true
            running = true
            time = 0
            lastBeat = nil
        }
    }

    private func stepLive(_ step: Double) {
        if running { time += step }
        let beat = timeline.beat(at: time)
        if lastBeat?.start != beat.start || lastBeat?.phase != beat.phase {
            begin(beat)
            lastBeat = beat
        }
        var place = place(ofSpot: beat.spot)
        var scale: Float = 1
        var tilt = lean
        switch beat.phase {
        case .watch, .settle:
            break
        case .tell:
            if actor == nil { scale = 0.78 }
            if pulse, patch.isEnabled {
                let beatPart = Float((time - beat.start) / max(0.01, beat.end - beat.start))
                let swell = 1 + 0.25 * sin(beatPart * .pi * 4)
                patch.scale = [swell, 1, swell]
            }
        case .air:
            let part = Float((time - beat.start) / max(0.01, beat.end - beat.start))
            let eased = part * part * (3 - 2 * part)
            let from = self.place(ofSpot: beat.spot), to = self.place(ofSpot: beat.next)
            place = from + (to - from) * eased
            place.y = 0.3 * sin(part * .pi)
            tilt = lean - 0.15 * sin(part * .pi)
        case .hidden:
            let part = Float(min(1, (time - beat.start) / 0.18))
            let back = Float(min(1, max(0, (beat.end - time) / 0.18)))
            let down = min(part, back)
            place.y = -0.3 * down
            scale = 1 - 0.75 * down
        }
        body.position = place + hover
        body.scale = [scale, scale, scale]
        body.orientation = turn(at: place, lean: tilt)
        shade.position = [place.x, 0.004, place.z]
        let high = max(0, min(1, (place.y + hover.y) / 0.3))
        shade.scale = [1 - 0.45 * high, 1, 1 - 0.45 * high]
        shade.isEnabled = beat.phase != .hidden
    }

    private func begin(_ beat: Beat) {
        switch beat.phase {
        case .watch:
            if let idle = clip("idle") { actor?.play(idle, loop: true, fade: 0.2) }
        case .tell:
            if let tell = clip("tell"), let long = actor?.seconds[tell], long > 0 {
                actor?.play(tell, loop: false, fade: 0.12, speed: Float(long / max(0.2, beat.end - beat.start)))
            }
            if beat.next != beat.spot {
                let goal = place(ofSpot: beat.next)
                patch.position = [goal.x, 0.006, goal.z]
                patch.scale = [1, 1, 1]
                patch.isEnabled = true
            }
            say(.tell)
        case .air:
            if let leap = clip("leap") { actor?.play(leap, loop: false, fade: 0.06) }
            say(.hop)
        case .settle:
            if let land = clip("land") { actor?.play(land, loop: false, fade: 0.05) }
            patch.isEnabled = false
            say(.land)
            if awaitsLanding {
                awaitsLanding = false
                mode = .vaulting
                since = clock
                running = false
                standing = beat.spot
                doneAt = clock + 2.2
                burst(at: place(ofSpot: beat.spot) + [0, 0.1, 0], count: 22, colour: UIColor(red: 0.95, green: 0.65, blue: 0.10, alpha: 1), speed: 0.9)
            }
        case .hidden:
            say(.hide)
        }
    }

    /// The keeper startles at the marker, looks at it closely, and accepts.
    private func stepAccepting() {
        let age = clock - since
        let place = place(ofSpot: standing)
        var scale: Float = 1
        var tilt = lean
        if age < 0.22 {
            scale = 1 + 0.16 * sin(Float(age / 0.22) * .pi)
            body.position = place + hover + [0, 0.06 * sin(Float(age / 0.22) * .pi), 0]
        } else if age < 0.95 {
            // It comes down to the marker for a close look, which a flyer does by sinking toward it.
            let part = Float((age - 0.22) / 0.73)
            body.position = place + hover * (1 - 0.6 * sin(part * .pi))
            tilt = lean + 0.55 * sin(part * .pi)
        } else {
            body.position = place + hover
            once("accept") {
                say(.accept)
                if let accept = clip("accept") { actor?.play(accept, loop: false, fade: 0.15) }
                burst(at: place + [0, Float(keeper?.heightM ?? 0.4) * 0.7, 0], count: 16, colour: UIColor(white: 1, alpha: 1), speed: 0.7)
            }
        }
        body.scale = [scale, scale, scale]
        body.orientation = turn(at: place, lean: tilt)
    }

    /// The keeper has landed on the marker and is proud of it.
    private func stepVaulting() {
        let age = clock - since
        let place = place(ofSpot: standing)
        let squash = age < 0.25 ? 1 - 0.22 * sin(Float(age / 0.25) * .pi) : 1
        body.position = place + hover
        body.scale = [2 - squash, squash, 2 - squash]
        body.orientation = turn(at: place, lean: lean)
        if age >= 0.3 {
            once("proud") {
                say(.proud)
                if let proud = clip("goodbye") { actor?.play(proud, loop: false, fade: 0.15) }
            }
        }
    }

    private func stepRefusing(_ step: Double) {
        let age = clock - since
        // A keeper in the air finishes its hop first, then shakes its head.
        let beat = timeline.beat(at: time)
        if beat.phase == .air || beat.phase == .hidden {
            stepLive(step)
            since = clock
            doneAt = clock + 1.35
            return
        }
        if age >= 0.1 {
            once("refuse \(since)") {
                running = false
                say(.refuse)
                if let refuse = clip("refuse"), let long = actor?.seconds[refuse], long > 0 { actor?.play(refuse, loop: false, fade: 0.12, speed: Float(long / 1.1)) }
            }
        }
        if age >= 1.3 {
            mode = .live
            running = true
            lastBeat = nil
        }
    }

    private func stepSlipping() {
        let age = clock - since
        let place = place(ofSpot: standing)
        let part = Float(min(1, max(0, (age - 0.25) / 0.45)))
        body.position = place + hover * (1 - part) + [0, -0.35 * part, 0]
        let small = 1 - 0.85 * part
        body.scale = [small, small, small]
        shade.scale = [small, 1, small]
        if part >= 1 {
            once("splash") {
                body.isEnabled = false
                shade.isEnabled = false
                burst(at: place + [0, 0.04, 0], count: 18, colour: UIColor(red: 0.30, green: 0.55, blue: 0.70, alpha: 1), speed: 0.8)
            }
        }
    }

    // MARK: the marker, the crate and the sparks

    private func buildMarker() {
        let disc = ModelEntity(mesh: .generateCylinder(height: 0.016, radius: 0.075), materials: [SimpleMaterial(color: UIColor(red: 0.93, green: 0.42, blue: 0.10, alpha: 1), roughness: 0.35, isMetallic: false)])
        disc.position.y = 0.008
        let dot = ModelEntity(mesh: .generateCylinder(height: 0.018, radius: 0.028), materials: [SimpleMaterial(color: .white, roughness: 0.3, isMetallic: false)])
        dot.position.y = 0.009
        marker.addChild(disc)
        marker.addChild(dot)
        marker.isEnabled = false
        root.addChild(marker)
    }

    private func showMarker(at place: SIMD3<Float>, fades: Bool) {
        marker.position = [place.x, 0.004, place.z]
        marker.scale = [1, 1, 1]
        marker.isEnabled = true
        markerSince = clock
        markerFades = fades
    }

    private func stepMarker() {
        guard let since = markerSince, marker.isEnabled else { return }
        let age = Float(clock - since)
        if age < 0.3 {
            // It lands flat and springs back, which gives the landing its weight.
            let squash = 1 - 0.6 * (1 - age / 0.3) * abs(cos(age * 26))
            marker.scale = [2 - squash, squash, 2 - squash]
        } else if markerFades {
            let left = max(0, 1 - (age - 0.6) / 0.4)
            marker.scale = [left, left, left]
            if left <= 0 { marker.isEnabled = false }
        } else {
            marker.scale = [1, 1, 1]
        }
    }

    private func buildCrate() {
        let wood = SimpleMaterial(color: UIColor(red: 0.62, green: 0.40, blue: 0.22, alpha: 1), roughness: 0.8, isMetallic: false)
        let band = SimpleMaterial(color: UIColor(red: 0.27, green: 0.58, blue: 0.52, alpha: 1), roughness: 0.5, isMetallic: true)
        let box = ModelEntity(mesh: .generateBox(size: [0.34, 0.2, 0.24], cornerRadius: 0.015), materials: [wood])
        box.position.y = 0.1
        crate.addChild(box)
        for x in [Float(-0.11), 0.11] {
            let strap = ModelEntity(mesh: .generateBox(size: [0.03, 0.205, 0.245]), materials: [band])
            strap.position = [x, 0.1, 0]
            crate.addChild(strap)
        }
        let top = ModelEntity(mesh: .generateBox(size: [0.36, 0.045, 0.26], cornerRadius: 0.012), materials: [wood])
        top.position = [0, 0.022, 0.13]
        lid.addChild(top)
        lid.position = [0, 0.2, -0.13]
        crate.addChild(lid)
        crate.isEnabled = false
        root.addChild(crate)
    }

    private func stepCrate() {
        if let since = crateSince {
            let part = Float(min(1, (clock - since) / 0.45))
            let grown = 1 + 2.70158 * pow(part - 1, 3) + 1.70158 * pow(part - 1, 2)
            crate.scale = [grown, grown, grown]
            crate.position = crateAt + [0, -0.12 * (1 - part), 0]
        }
        if let since = lidSince {
            let part = Float(min(1, (clock - since) / 0.28))
            lid.orientation = simd_quatf(angle: -1.9 * part, axis: [1, 0, 0])
        }
        for k in parts.indices {
            let age = Float(clock - parts[k].start)
            guard age >= 0 else { continue }
            if !parts[k].part.isEnabled && age < 0.75 {
                parts[k].part.isEnabled = true
                say(.part)
            }
            let part = min(1, age / 0.75)
            parts[k].part.position = parts[k].from + [0.12 * sin(Float(k) * 2.1) * part, 0.75 * part - 0.25 * part * part, 0.2 * part]
            parts[k].part.orientation = simd_quatf(angle: age * 7, axis: [0.3, 1, 0.2])
            let size = part < 0.8 ? 1 : max(0, 1 - (part - 0.8) / 0.2)
            parts[k].part.scale = [size, size, size]
            if part >= 1 { parts[k].part.isEnabled = false }
        }
    }

    private func burst(at place: SIMD3<Float>, count: Int, colour: UIColor, speed: Float) {
        for k in 0..<count {
            let angle = Float(k) / Float(count) * 2 * .pi
            let part = ModelEntity(mesh: .generateSphere(radius: 0.013), materials: [UnlitMaterial(color: colour)])
            part.position = place
            root.addChild(part)
            sparks.append((part, [cos(angle) * speed * 0.6, speed * (0.7 + Float(k % 3) * 0.25), sin(angle) * speed * 0.6], 0, 0.7))
        }
    }

    private func stepSparks(_ step: Double) {
        for k in sparks.indices {
            sparks[k].age += step
            sparks[k].part.position += sparks[k].way * Float(step)
            sparks[k].way.y -= 2.2 * Float(step)
            let left = Float(max(0, 1 - sparks[k].age / sparks[k].life))
            sparks[k].part.scale = [left, left, left]
        }
        for spark in sparks where spark.age >= spark.life { spark.part.removeFromParent() }
        sparks.removeAll { $0.age >= $0.life }
    }

    #if DEBUG
    /// Hold the meeting at a named moment, so that a still picture can show it.
    func hold(at moment: String) {
        let pick: Beat?
        switch moment {
        case "crouch": pick = timeline.beats.first { $0.phase == .tell && $0.next != $0.spot }
        case "air": pick = timeline.beats.first { $0.phase == .air }
        case "land": pick = timeline.beats.first { $0.phase == .settle }
        default: pick = nil
        }
        guard let pick else { return }
        time = moment == "land" ? pick.start + 0.02 : (pick.start + pick.end) / 2
        lastBeat = nil
        stepLive(0)
        running = false
    }
    #endif
}
