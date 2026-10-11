import RealityKit
import UIKit

/// The little world of an encounter when there is no camera to look through, in the simulator and at a desk. A
/// drain at a kerb with a grate, a hood and a few leaves, and the creature standing on the grate. On a phone the
/// camera's picture of the real drain takes the place of everything here but the creature.
final class DrainScene {
    let root = Entity()
    var subscription: EventSubscription?
    private var creature = Entity()
    private var idle = "hop"
    private var clock: Double = 0
    private var hopping: Double?
    private var leaving: Double?
    private var sparks: [(part: ModelEntity, way: SIMD3<Float>)] = []
    private let spot = SIMD3<Float>(0, 0.045, 0.02)
    private let size: Float = 2.0

    func build(species: Species?) {
        ground()
        light()
        idle = species?.idle ?? "hop"
        creature = CreatureFactory.make(species)
        creature.position = spot
        creature.scale = [size, size, size]
        root.addChild(creature)
        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = 68
        camera.look(at: [0, 0.14, -0.02], from: [0, 1.75, 1.7], relativeTo: nil)
        root.addChild(camera)
    }

    // MARK: the drain

    private func paint(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> UIColor {
        UIColor(red: red / 255, green: green / 255, blue: blue / 255, alpha: 1)
    }

    private func block(_ size: SIMD3<Float>, _ colour: UIColor, at place: SIMD3<Float>, corner: Float = 0.004, turn: Float = 0) {
        let part = ModelEntity(mesh: .generateBox(size: size, cornerRadius: corner), materials: [SimpleMaterial(color: colour, roughness: 0.95, isMetallic: false)])
        part.position = place
        part.orientation = simd_quatf(angle: turn, axis: [0, 1, 0])
        root.addChild(part)
    }

    private func ground() {
        block([40, 0.04, 12], paint(72, 76, 82), at: [0, -0.02, 4.4])                       // the street
        block([40, 0.04, 1.3], paint(128, 126, 120), at: [0, 0.13, -1.2])                  // the pavement behind the kerb
        block([40, 0.04, 40], paint(94, 150, 72), at: [0, 0.128, -21.8])                   // the lawn, far enough that no edge shows
        block([40, 0.17, 0.22], paint(176, 180, 184), at: [0, 0.065, -0.44], corner: 0.02) // the kerb
        block([1.16, 0.2, 0.26], paint(121, 68, 41), at: [0, 0.085, -0.43], corner: 0.03)  // the cast iron hood
        for k in 0..<4 {
            block([0.16, 0.035, 0.02], .black, at: [-0.39 + Float(k) * 0.26, 0.075, -0.297])
        }
        block([1.1, 0.02, 0.62], .black, at: [0, 0.004, 0.0])                              // the dark below the grate
        block([1.14, 0.04, 0.05], paint(110, 62, 38), at: [0, 0.02, -0.3])
        block([1.14, 0.04, 0.05], paint(110, 62, 38), at: [0, 0.02, 0.31])
        block([1.14, 0.04, 0.035], paint(110, 62, 38), at: [0, 0.02, 0.005])
        for k in 0..<9 {
            block([0.045, 0.04, 0.64], paint(121, 68, 41), at: [-0.548 + Float(k) * 0.137, 0.02, 0.005])
        }
        let leaves: [(Float, Float, Float, UIColor)] = [
            (-0.78, 0.1, 0.4, paint(214, 122, 28)), (-0.66, -0.14, 1.9, paint(170, 84, 30)), (0.74, 0.22, 0.9, paint(230, 170, 50)),
            (0.82, -0.2, 2.4, paint(190, 70, 30)), (0.3, 0.5, 0.2, paint(214, 122, 28)), (-0.2, 0.55, 1.1, paint(230, 170, 50)),
            (-0.5, 0.42, 2.9, paint(160, 90, 40)), (0.56, 0.44, 1.5, paint(200, 100, 30)), (-0.9, 0.5, 0.7, paint(190, 70, 30)),
            (0.1, -0.24, 0.5, paint(230, 170, 50)), (-0.36, -0.2, 2.2, paint(214, 122, 28)), (1.1, 0.1, 1.3, paint(170, 84, 30)),
            (-1.2, 0.2, 0.3, paint(230, 170, 50)), (0.46, 0.14, 2.0, paint(190, 70, 30)),
        ]
        for (x, z, turn, colour) in leaves {
            block([0.085, 0.006, 0.055], colour, at: [x, 0.044, z], corner: 0.002, turn: turn)
        }
    }

    private func light() {
        let sun = DirectionalLight()
        sun.light.intensity = 5200
        sun.look(at: [0, 0, 0], from: [1.2, 2.4, 1.6], relativeTo: nil)
        root.addChild(sun)
        let sky = DirectionalLight()
        sky.light.intensity = 2200
        sky.look(at: [0, 0, 0], from: [-1.6, 1.4, 1.2], relativeTo: nil)
        root.addChild(sky)
    }

    // MARK: what happens

    /// The throw missed. The creature jumps aside and comes back.
    func miss() {
        hopping = 0
    }

    /// The throw landed. The creature spins, shrinks and is gone in a puff of sparks.
    func caught() {
        leaving = 0
        for k in 0..<14 {
            let angle = Float(k) / 14 * 2 * .pi
            let part = ModelEntity(mesh: .generateSphere(radius: 0.018), materials: [UnlitMaterial(color: k % 2 == 0 ? paint(255, 214, 64) : .white)])
            part.position = [spot.x, spot.y + 0.14, spot.z]
            root.addChild(part)
            sparks.append((part, [cos(angle) * 0.55, 0.55 + Float(k % 3) * 0.25, sin(angle) * 0.55]))
        }
    }

    /// One step of time. Every creature moves a little in its own way, so that it is alive before anything is thrown.
    func tick(_ step: Double) {
        clock += step
        let t = Float(clock)
        var place = spot
        var yaw: Float = 0
        switch idle {
        case "hop": place.y += 0.05 * pow(abs(sin(t * 1.9)), 8)
        case "skate":
            place.x += 0.1 * sin(t * 1.3)
            place.z += 0.04 * sin(t * 2.1)
        case "sidle":
            place.x += 0.06 * sin(t * 1.5)
            yaw = 0.2 * sin(t * 1.5)
        case "turn": yaw = 0.5 * sin(t * 0.7)
        case "curl": yaw = 0.4 * sin(t * 0.9)
        case "step":
            place.x += 0.035 * sin(t * 0.8)
            yaw = 0.22 * sin(t * 0.8)
        case "rise":
            place.y += 0.02 + 0.02 * sin(t * 2)
            yaw = t * 0.7
        case "swirl":
            place.y += 0.03 + 0.015 * sin(t * 3)
            yaw = t * 1.5
        default: place.y += 0.01 * sin(t * 2)
        }
        var grown = size
        if let since = hopping {
            let part = Float(since / 0.5)
            place.y += 0.22 * sin(part * .pi)
            place.x += 0.16 * sin(part * .pi)
            hopping = since + step >= 0.5 ? nil : since + step
        }
        if let since = leaving {
            let part = Float(min(1, since / 0.6))
            grown = size * (1 - part)
            yaw += part * 9
            place.y += 0.2 * part
            leaving = since + step
            for k in sparks.indices {
                sparks[k].part.position += sparks[k].way * Float(step)
                sparks[k].way.y -= 1.6 * Float(step)
                let fade = max(0, 1 - Float(since / 0.9))
                sparks[k].part.scale = [fade, fade, fade]
            }
        }
        creature.position = place
        creature.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
        creature.scale = [grown, grown, grown]
    }
}
