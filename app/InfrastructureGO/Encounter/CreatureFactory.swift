import RealityKit
import UIKit

/// The stand-in for a keeper whose model files are missing from the bundle, a round figure with two eyes. Every
/// keeper of the game has its model, so this is only ever seen when a build went wrong, and it keeps a meeting
/// playable then. It stands on the ground at its own origin and looks along the z axis, toward the player.
enum CreatureFactory {
    static func fallback(heightM: Double) -> Entity {
        let root = Entity()
        let tall = Float(heightM)
        let body = ModelEntity(mesh: .generateSphere(radius: tall / 2), materials: [SimpleMaterial(color: UIColor(red: 0.43, green: 0.60, blue: 0.25, alpha: 1), roughness: 0.4, isMetallic: false)])
        body.position = [0, tall / 2, 0]
        body.scale = [1, 0.92, 0.95]
        root.addChild(body)
        for side in [Float(-1), 1] {
            let eye = ModelEntity(mesh: .generateSphere(radius: tall * 0.09), materials: [SimpleMaterial(color: .white, roughness: 0.2, isMetallic: false)])
            eye.position = [side * tall * 0.17, tall * 0.68, tall * 0.4]
            let pupil = ModelEntity(mesh: .generateSphere(radius: tall * 0.045), materials: [UnlitMaterial(color: .black)])
            pupil.position = [0, 0, tall * 0.06]
            eye.addChild(pupil)
            root.addChild(eye)
        }
        return root
    }
}
