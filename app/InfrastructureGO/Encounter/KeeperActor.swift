import Foundation
import RealityKit

/// A keeper as RealityKit shows it, a model with a skeleton and its movements by name.
///
/// The art scripts write one file per movement, named after the keeper and the movement, for example
/// frog_idle.usdz and frog_hop.usdz. The first file gives the body. Every file gives its movement, and all of
/// them play on that one body, fading from one into the next.
final class KeeperActor {
    /// What the stage moves and turns. The model hangs below it, sized and set on its feet.
    let root = Entity()
    private(set) var clips: [String: AnimationResource] = [:]
    private(set) var seconds: [String: Double] = [:]
    private(set) var joints = 0
    private(set) var playing: String?
    private var body: Entity?
    private var mover: Entity?
    private var control: AnimationPlaybackController?

    /// The movements a keeper has in the bundle, read from the names of its files.
    static func clipNames(of keeper: String, in bundle: Bundle = .main) -> [String] {
        let files = bundle.urls(forResourcesWithExtension: "usdz", subdirectory: nil) ?? []
        return files.map { $0.deletingPathExtension().lastPathComponent }
            .filter { $0.hasPrefix(keeper + "_") }
            .map { String($0.dropFirst(keeper.count + 1)) }
            .sorted()
    }

    /// Load a keeper with all its movements, or nil when the bundle has no file for it.
    static func load(_ keeper: String, heightM: Double, in bundle: Bundle = .main) async -> KeeperActor? {
        let names = clipNames(of: keeper, in: bundle)
        guard !names.isEmpty else { return nil }
        let actor = KeeperActor()
        for name in names.sorted(by: { a, _ in a == "idle" }) {
            guard let url = bundle.url(forResource: "\(keeper)_\(name)", withExtension: "usdz"), let loaded = try? await Entity(contentsOf: url) else { continue }
            guard let owner = firstWithAnimation(in: loaded), let clip = owner.availableAnimations.first else { continue }
            if actor.body == nil {
                actor.body = loaded
                actor.mover = owner
                actor.joints = jointCount(in: loaded)
            }
            actor.clips[name] = clip
        }
        guard let body = actor.body, let mover = actor.mover else { return nil }
        var library = AnimationLibraryComponent()
        for (name, clip) in actor.clips { library.animations[name] = clip }
        mover.components.set(library)
        for (name, clip) in actor.clips {
            let probe = mover.playAnimation(clip, transitionDuration: 0, startsPaused: true)
            actor.seconds[name] = probe.duration
            probe.stop()
        }
        // Stand the model on the ground at the height the game wants, whatever size its file has.
        let bounds = body.visualBounds(relativeTo: nil)
        let tall = Double(bounds.extents.y)
        let scale = tall > 0 ? Float(heightM / tall) : 1
        body.scale = [scale, scale, scale]
        body.position = [-bounds.center.x * scale, -bounds.min.y * scale, -bounds.center.z * scale]
        actor.root.addChild(body)
        return actor
    }

    /// Play a movement, fading over from whatever plays now.
    @discardableResult
    func play(_ name: String, loop: Bool, fade: Double = 0.2, speed: Float = 1) -> Double {
        guard let mover, let clip = clips[name] else { return 0 }
        control = mover.playAnimation(loop ? clip.repeat() : clip, transitionDuration: fade, startsPaused: false)
        control?.speed = speed
        playing = name
        return (seconds[name] ?? 0) / Double(max(0.01, speed))
    }

    /// Hold a movement still at one moment, for a picture.
    func freeze(_ name: String, at second: Double) {
        guard let mover, let clip = clips[name] else { return }
        control = mover.playAnimation(clip, transitionDuration: 0, startsPaused: true)
        control?.time = second
        playing = name
    }

    /// The entity a movement plays on. A file's movement drives the entity that carries the skeleton, so that one
    /// is looked for first, and only a file without a skeleton falls back to the first entity with a movement.
    private static func firstWithAnimation(in entity: Entity) -> Entity? {
        skinned(in: entity) ?? anyWithAnimation(in: entity)
    }

    private static func skinned(in entity: Entity) -> Entity? {
        if let model = entity as? ModelEntity, !model.jointNames.isEmpty, !entity.availableAnimations.isEmpty { return entity }
        for child in entity.children {
            if let found = skinned(in: child) { return found }
        }
        return nil
    }

    private static func anyWithAnimation(in entity: Entity) -> Entity? {
        if !entity.availableAnimations.isEmpty { return entity }
        for child in entity.children {
            if let found = anyWithAnimation(in: child) { return found }
        }
        return nil
    }

    private static func jointCount(in entity: Entity) -> Int {
        var most = (entity as? ModelEntity)?.jointNames.count ?? 0
        for child in entity.children { most = max(most, jointCount(in: child)) }
        return most
    }
}
