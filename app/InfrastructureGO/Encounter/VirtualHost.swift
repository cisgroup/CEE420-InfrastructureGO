import Foundation
import RealityKit
import UIKit

/// What stands in for the phone's camera where there is none, in the simulator and at a desk.
///
/// A photograph of a real Princeton drain fills the view, and a camera is set where the photographer stood, so
/// that anything placed on the ground entity sits on the photographed grate. The photographs are private and
/// stay on the developer's Mac. Without them the host has no picture and the caller builds a modelled drain on
/// the ground entity instead. On a phone a host with the real camera takes this one's place and the stage on the
/// ground entity stays the same.
final class VirtualHost {
    let root = Entity()
    /// The middle of the grate, turned with it. Its x runs along the kerb to the right and its z toward the street.
    let ground = Entity()
    let backdrop: Backdrop
    let hasPicture: Bool
    private let camera = PerspectiveCamera()

    /// The backdrops of the bundle, which are there only on a Mac that holds the private photographs.
    static func backdrops(in bundle: Bundle = .main) -> [Backdrop] {
        guard let url = bundle.url(forResource: "backdrops", withExtension: "json"), let data = try? Data(contentsOf: url) else { return [] }
        return (try? BackdropFile(json: data).backdrops) ?? []
    }

    static func make(preferred id: String? = nil, in bundle: Bundle = .main) async -> VirtualHost {
        let all = backdrops(in: bundle)
        let pick = all.first { $0.id == id } ?? all.first
        if let pick, let url = bundle.url(forResource: pick.file, withExtension: "jpg"), let picture = try? await TextureResource(contentsOf: url) {
            return VirtualHost(backdrop: pick, picture: picture)
        }
        return VirtualHost(backdrop: .modelled, picture: nil)
    }

    /// A host for a given view. Without a picture the modelled drain is built, which needs no file at all.
    init(backdrop: Backdrop, picture: TextureResource?) {
        self.backdrop = backdrop
        hasPicture = picture != nil
        let pitch = Float(backdrop.pitchDeg * .pi / 180)
        camera.position = [0, Float(backdrop.heightM), 0]
        camera.orientation = simd_quatf(angle: -pitch, axis: [1, 0, 0])
        camera.camera.fieldOfViewOrientation = .vertical
        camera.camera.fieldOfViewInDegrees = Float(backdrop.fovVerticalDeg)
        camera.camera.near = 0.05
        camera.camera.far = 200
        root.addChild(camera)

        if let picture {
            // The picture hangs far behind everything, fixed to the camera, exactly as large as the camera's view.
            let far: Float = 60
            let tall = 2 * far * tan(Float(backdrop.fovVerticalDeg) * .pi / 360)
            var paint = UnlitMaterial(applyPostProcessToneMap: false)
            paint.color = .init(texture: .init(picture))
            let plane = ModelEntity(mesh: .generatePlane(width: tall * Float(backdrop.aspect), height: tall), materials: [paint])
            plane.position = [0, 0, -far]
            camera.addChild(plane)
        }

        ground.position = [Float(backdrop.grateXM), 0, Float(backdrop.grateZM)]
        ground.orientation = simd_quatf(angle: -Float(backdrop.grateYawDeg * .pi / 180), axis: [0, 1, 0])
        root.addChild(ground)
        if picture == nil { ground.addChild(ModelledDrain.build()) }

        let sun = DirectionalLight()
        sun.light.intensity = 1700
        sun.look(at: ground.position, from: ground.position + [1.0, 2.6, 1.4], relativeTo: nil)
        root.addChild(sun)
        let sky = DirectionalLight()
        sky.light.intensity = 450
        sky.look(at: ground.position, from: ground.position + [-1.6, 1.6, 1.0], relativeTo: nil)
        root.addChild(sky)
    }

    /// Set the camera so that the picture fills a screen of this shape.
    func fit(screenAspect: Double) {
        camera.camera.fieldOfViewInDegrees = Float(backdrop.cameraFovDeg(screenAspect: screenAspect))
    }

    /// The direction on the ground from the grate toward the camera, as an angle about the vertical for an entity
    /// below the ground entity, so that a keeper can turn to face the player.
    var yawTowardCamera: Float {
        let toCamera = SIMD3<Float>(-Float(backdrop.grateXM), 0, -Float(backdrop.grateZM))
        let local = ground.orientation.inverse.act(toCamera)
        return atan2(local.x, local.z)
    }

    /// The place of a spot of the grate in the scene, on the ground. Along runs from minus one at the left end of
    /// the grate to one at its right end, across from minus one at the kerb to one at the street side.
    func place(along: Double, across: Double) -> SIMD3<Float> {
        let spot = backdrop.spot(along: along, across: across)
        return [Float(spot.x), 0, Float(spot.z)]
    }

    /// The turn about the vertical that makes something at a place face the camera.
    func facing(from place: SIMD3<Float>) -> Float {
        atan2(-place.x, -place.z)
    }
}
