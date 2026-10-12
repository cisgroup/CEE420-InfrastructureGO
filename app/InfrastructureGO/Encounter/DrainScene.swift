import RealityKit
import UIKit

/// A drain built from simple blocks, for a build that has no photograph to stand behind a meeting: a fresh clone
/// of the repository, or the tests. The grate lies at the origin, the kerb behind it and the street toward the
/// camera, which is how the ground of the host is laid out too.
enum ModelledDrain {
    static func build() -> Entity {
        let root = Entity()
        func paint(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> UIColor {
            UIColor(red: red / 255, green: green / 255, blue: blue / 255, alpha: 1)
        }
        func block(_ size: SIMD3<Float>, _ colour: UIColor, at place: SIMD3<Float>, corner: Float = 0.004, turn: Float = 0) {
            let part = ModelEntity(mesh: .generateBox(size: size, cornerRadius: corner), materials: [SimpleMaterial(color: colour, roughness: 0.95, isMetallic: false)])
            part.position = place
            part.orientation = simd_quatf(angle: turn, axis: [0, 1, 0])
            root.addChild(part)
        }
        block([40, 0.04, 12], paint(72, 76, 82), at: [0, -0.045, 4.4])                       // the street
        block([40, 0.04, 1.3], paint(128, 126, 120), at: [0, 0.105, -1.2])                   // the pavement behind the kerb
        block([40, 0.04, 40], paint(94, 150, 72), at: [0, 0.103, -21.8])                     // the lawn
        block([40, 0.17, 0.22], paint(176, 180, 184), at: [0, 0.04, -0.44], corner: 0.02)    // the kerb
        block([1.16, 0.2, 0.26], paint(121, 68, 41), at: [0, 0.06, -0.43], corner: 0.03)     // the cast iron hood
        for k in 0..<4 {
            block([0.16, 0.035, 0.02], .black, at: [-0.39 + Float(k) * 0.26, 0.05, -0.297])
        }
        block([1.1, 0.02, 0.62], .black, at: [0, -0.021, 0.0])                               // the dark below the grate
        block([1.14, 0.04, 0.05], paint(110, 62, 38), at: [0, -0.02, -0.3])
        block([1.14, 0.04, 0.05], paint(110, 62, 38), at: [0, -0.02, 0.31])
        block([1.14, 0.04, 0.035], paint(110, 62, 38), at: [0, -0.02, 0.005])
        for k in 0..<9 {
            block([0.045, 0.04, 0.64], paint(121, 68, 41), at: [-0.548 + Float(k) * 0.137, -0.02, 0.005])
        }
        let leaves: [(Float, Float, Float, UIColor)] = [
            (-0.78, 0.5, 0.4, paint(214, 122, 28)), (0.74, 0.62, 0.9, paint(230, 170, 50)), (0.3, 0.9, 0.2, paint(214, 122, 28)), (-0.2, 0.95, 1.1, paint(230, 170, 50)),
            (-0.5, 0.82, 2.9, paint(160, 90, 40)), (0.56, 0.84, 1.5, paint(200, 100, 30)), (-0.9, 0.9, 0.7, paint(190, 70, 30)), (1.1, 0.5, 1.3, paint(170, 84, 30)),
        ]
        for (x, z, turn, colour) in leaves {
            block([0.085, 0.006, 0.055], colour, at: [x, -0.02, z], corner: 0.002, turn: turn)
        }
        return root
    }
}
