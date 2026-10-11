import RealityKit
import UIKit

/// Builds the creatures out of simple shapes. A species whose file says procedural is made here, so the game has
/// every creature from the first day, and a drawn model can take a creature's place later without a change here.
/// A creature stands on the ground at its own origin and looks along the z axis, towards the player.
enum CreatureFactory {
    static func make(_ species: Species?) -> Entity {
        let root = Entity()
        switch species?.id {
        case "green_frog": frog(root)
        case "painted_turtle": turtle(root)
        case "crayfish": crayfish(root)
        case "spotted_salamander": salamander(root)
        case "great_blue_heron": heron(root)
        case "water_strider": strider(root)
        case "storm_eel": eel(root)
        case "leaf_sprite": sprite(root)
        default: blob(root)
        }
        return root
    }

    // MARK: shapes

    private static func paint(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> UIColor {
        UIColor(red: red / 255, green: green / 255, blue: blue / 255, alpha: 1)
    }

    private static func matte(_ colour: UIColor) -> RealityKit.Material {
        SimpleMaterial(color: colour, roughness: 0.75, isMetallic: false)
    }

    private static func glow(_ colour: UIColor) -> RealityKit.Material {
        UnlitMaterial(color: colour)
    }

    @discardableResult
    private static func ball(_ parent: Entity, _ radius: Float, _ colour: UIColor, at place: SIMD3<Float>, stretch: SIMD3<Float> = [1, 1, 1], glowing: Bool = false) -> ModelEntity {
        let part = ModelEntity(mesh: .generateSphere(radius: radius), materials: [glowing ? glow(colour) : matte(colour)])
        part.position = place
        part.scale = stretch
        parent.addChild(part)
        return part
    }

    @discardableResult
    private static func slab(_ parent: Entity, _ size: SIMD3<Float>, _ colour: UIColor, at place: SIMD3<Float>, turn: simd_quatf = simd_quatf(angle: 0, axis: [0, 1, 0]), glowing: Bool = false) -> ModelEntity {
        let part = ModelEntity(mesh: .generateBox(size: size, cornerRadius: min(size.x, size.y, size.z) * 0.3), materials: [glowing ? glow(colour) : matte(colour)])
        part.position = place
        part.orientation = turn
        parent.addChild(part)
        return part
    }

    @discardableResult
    private static func rod(_ parent: Entity, height: Float, radius: Float, _ colour: UIColor, at place: SIMD3<Float>, turn: simd_quatf = simd_quatf(angle: 0, axis: [0, 1, 0])) -> ModelEntity {
        let part = ModelEntity(mesh: .generateCylinder(height: height, radius: radius), materials: [matte(colour)])
        part.position = place
        part.orientation = turn
        parent.addChild(part)
        return part
    }

    /// Two eyes that look at the player. Every creature has them, they are what makes a heap of shapes a someone.
    private static func eyes(_ parent: Entity, at place: SIMD3<Float>, apart: Float, size: Float) {
        for side in [Float(-1), 1] {
            let centre = SIMD3<Float>(place.x + side * apart / 2, place.y, place.z)
            ball(parent, size, .white, at: centre)
            ball(parent, size * 0.55, .black, at: [centre.x, centre.y + size * 0.1, centre.z + size * 0.62])
        }
    }

    // MARK: the species

    private static func frog(_ root: Entity) {
        let green = paint(76, 175, 80)
        ball(root, 0.09, green, at: [0, 0.075, 0], stretch: [1.15, 0.78, 1.25])
        ball(root, 0.07, paint(200, 230, 170), at: [0, 0.055, 0.045], stretch: [1, 0.62, 1])
        for side in [Float(-1), 1] {
            ball(root, 0.048, paint(56, 142, 60), at: [side * 0.09, 0.04, -0.03], stretch: [1, 0.62, 1.35])
            ball(root, 0.022, paint(56, 142, 60), at: [side * 0.062, 0.018, 0.1])
            ball(root, 0.036, green, at: [side * 0.047, 0.14, 0.05])
        }
        eyes(root, at: [0, 0.146, 0.062], apart: 0.094, size: 0.026)
    }

    private static func turtle(_ root: Entity) {
        ball(root, 0.105, paint(249, 168, 37), at: [0, 0.04, 0], stretch: [1.15, 0.2, 1.3])
        ball(root, 0.1, paint(46, 125, 50), at: [0, 0.07, 0], stretch: [1.08, 0.62, 1.22])
        for (x, z) in [(Float(0), Float(0.0)), (0.045, 0.05), (-0.045, 0.05), (0.045, -0.05), (-0.045, -0.05)] {
            ball(root, 0.03, paint(27, 94, 32), at: [x, 0.118 - abs(x) * 0.25, z], stretch: [1, 0.4, 1])
        }
        ball(root, 0.04, paint(130, 119, 23), at: [0, 0.066, 0.14])
        for (x, z) in [(Float(0.09), Float(0.075)), (-0.09, 0.075), (0.09, -0.075), (-0.09, -0.075)] {
            ball(root, 0.03, paint(130, 119, 23), at: [x, 0.022, z], stretch: [1, 0.6, 1.2])
        }
        eyes(root, at: [0, 0.086, 0.162], apart: 0.04, size: 0.014)
    }

    private static func crayfish(_ root: Entity) {
        let shell = paint(178, 60, 23)
        ball(root, 0.05, shell, at: [0, 0.055, 0], stretch: [1, 0.82, 1.9])
        for (k, z) in [Float(-0.1), -0.145, -0.18].enumerated() {
            ball(root, 0.04 - Float(k) * 0.008, paint(150, 48, 18), at: [0, 0.048, z], stretch: [1, 0.7, 1])
        }
        slab(root, [0.09, 0.008, 0.035], paint(216, 67, 21), at: [0, 0.04, -0.215])
        for side in [Float(-1), 1] {
            ball(root, 0.036, paint(216, 67, 21), at: [side * 0.088, 0.062, 0.115], stretch: [0.85, 0.6, 1.45])
            rod(root, height: 0.09, radius: 0.008, shell, at: [side * 0.06, 0.055, 0.07], turn: simd_quatf(angle: side * 0.9, axis: [0, 1, 0]) * simd_quatf(angle: .pi / 2, axis: [1, 0, 0]))
            rod(root, height: 0.11, radius: 0.0025, paint(120, 40, 15), at: [side * 0.03, 0.09, 0.13], turn: simd_quatf(angle: side * -0.35, axis: [0, 0, 1]) * simd_quatf(angle: 1.0, axis: [1, 0, 0]))
            for z in [Float(0.03), -0.01, -0.05] {
                ball(root, 0.012, shell, at: [side * 0.058, 0.018, z], stretch: [1.6, 0.7, 0.7])
            }
        }
        eyes(root, at: [0, 0.102, 0.085], apart: 0.042, size: 0.015)
    }

    private static func salamander(_ root: Entity) {
        let skin = paint(38, 50, 56)
        ball(root, 0.04, skin, at: [0, 0.042, 0], stretch: [1, 0.8, 3.1])
        ball(root, 0.044, skin, at: [0, 0.046, 0.14], stretch: [1.05, 0.8, 1.15])
        for (k, z) in [Float(-0.14), -0.185, -0.225, -0.26].enumerated() {
            ball(root, 0.03 - Float(k) * 0.006, skin, at: [Float(k) * 0.012, 0.035, z])
        }
        for (k, z) in [Float(0.1), 0.05, 0.0, -0.05, -0.1].enumerated() {
            ball(root, 0.012, paint(255, 235, 59), at: [k % 2 == 0 ? 0.02 : -0.02, 0.071, z], stretch: [1, 0.5, 1])
        }
        for (x, z) in [(Float(0.055), Float(0.08)), (-0.055, 0.08), (0.055, -0.07), (-0.055, -0.07)] {
            ball(root, 0.016, skin, at: [x, 0.016, z], stretch: [1.5, 0.7, 0.9])
        }
        eyes(root, at: [0, 0.078, 0.158], apart: 0.044, size: 0.013)
    }

    private static func heron(_ root: Entity) {
        let feathers = paint(96, 125, 139)
        for side in [Float(-1), 1] {
            rod(root, height: 0.2, radius: 0.007, paint(141, 110, 99), at: [side * 0.03, 0.1, 0])
            slab(root, [0.03, 0.006, 0.05], paint(141, 110, 99), at: [side * 0.03, 0.004, 0.015])
        }
        ball(root, 0.08, feathers, at: [0, 0.255, -0.01], stretch: [0.9, 0.95, 1.5])
        ball(root, 0.05, paint(69, 90, 100), at: [0, 0.25, -0.1], stretch: [0.7, 0.5, 1.4])
        rod(root, height: 0.17, radius: 0.016, paint(207, 216, 220), at: [0, 0.37, 0.085], turn: simd_quatf(angle: 0.25, axis: [1, 0, 0]))
        ball(root, 0.036, paint(236, 239, 241), at: [0, 0.462, 0.105])
        slab(root, [0.012, 0.012, 0.07], paint(38, 50, 56), at: [0, 0.482, 0.07])
        let beak = ModelEntity(mesh: .generateCone(height: 0.1, radius: 0.012), materials: [matte(paint(255, 179, 0))])
        beak.position = [0, 0.455, 0.18]
        beak.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        root.addChild(beak)
        eyes(root, at: [0, 0.472, 0.125], apart: 0.05, size: 0.009)
    }

    private static func strider(_ root: Entity) {
        ball(root, 0.02, paint(62, 39, 35), at: [0, 0.04, 0], stretch: [1, 0.7, 3.2])
        for side in [Float(-1), 1] {
            for (z, angle) in [(Float(0.03), Float(0.5)), (-0.03, -0.5)] {
                rod(root, height: 0.19, radius: 0.0025, paint(62, 39, 35), at: [side * 0.07, 0.028, z + side * angle * 0.03],
                    turn: simd_quatf(angle: side * angle, axis: [0, 1, 0]) * simd_quatf(angle: .pi / 2 + side * 0.18, axis: [0, 0, 1]))
                ball(root, 0.022, paint(128, 222, 234), at: [side * 0.15, 0.004, z + side * angle * 0.1], stretch: [1, 0.08, 1])
            }
        }
        eyes(root, at: [0, 0.05, 0.058], apart: 0.024, size: 0.008)
    }

    private static func eel(_ root: Entity) {
        for k in 0..<10 {
            let t = Float(k)
            ball(root, 0.032 - t * 0.0012, paint(0, 229, 255), at: [0.05 * sin(t * 0.85), 0.03 + t * 0.03, 0.03 * cos(t * 0.7)], glowing: true)
        }
        let top = SIMD3<Float>(0.05 * sin(9 * 0.85), 0.03 + 9 * 0.03, 0.03 * cos(9 * 0.7))
        ball(root, 0.04, paint(128, 255, 255), at: [top.x, top.y + 0.03, top.z + 0.01], glowing: true)
        for (x, y) in [(Float(0.11), Float(0.2)), (-0.1, 0.12), (0.08, 0.3)] {
            slab(root, [0.012, 0.07, 0.006], paint(255, 238, 88), at: [x, y, 0.03], turn: simd_quatf(angle: x > 0 ? 0.5 : -0.5, axis: [0, 0, 1]), glowing: true)
        }
        eyes(root, at: [top.x, top.y + 0.04, top.z + 0.04], apart: 0.036, size: 0.012)
    }

    private static func sprite(_ root: Entity) {
        ball(root, 0.06, paint(141, 85, 36), at: [0, 0.1, 0])
        let colours = [paint(230, 81, 0), paint(245, 124, 0), paint(251, 192, 45), paint(191, 54, 12), paint(255, 160, 0)]
        for k in 0..<12 {
            let angle = Float(k) / 12 * 2 * .pi
            let lift = Float(k % 3) * 0.03
            slab(root, [0.085, 0.005, 0.05], colours[k % colours.count], at: [0.085 * cos(angle), 0.07 + lift, 0.085 * sin(angle)],
                 turn: simd_quatf(angle: -angle, axis: [0, 1, 0]) * simd_quatf(angle: 0.6, axis: [0, 0, 1]))
        }
        slab(root, [0.006, 0.07, 0.006], paint(93, 64, 55), at: [0, 0.185, 0])
        eyes(root, at: [0, 0.125, 0.062], apart: 0.05, size: 0.02)
    }

    private static func blob(_ root: Entity) {
        ball(root, 0.08, paint(120, 144, 156), at: [0, 0.07, 0], stretch: [1, 0.85, 1])
        eyes(root, at: [0, 0.1, 0.06], apart: 0.05, size: 0.018)
    }
}
