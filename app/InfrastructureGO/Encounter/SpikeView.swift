#if DEBUG
import RealityKit
import SwiftUI

/// A look at one model on the backdrop, for checking the art before the game uses it. It is opened by the debug
/// word -igo.spike with the model's name, plays its movements one after another with a fade between them, and
/// writes what it found into spike.json in the app's documents. The word -igo.freeze holds one movement at one
/// moment, for example hop:0.3, so that two pictures can show that the model really moves.
struct SpikeView: View {
    let name: String
    let freeze: String?
    @State private var note = "Loading"

    var body: some View {
        GeometryReader { geometry in
            RealityView { content in
                content.camera = .virtual
                let host = await VirtualHost.make()
                host.fit(screenAspect: geometry.size.width / max(1, geometry.size.height))
                content.add(host.root)
                var dark = UnlitMaterial(color: .black)
                dark.blending = .transparent(opacity: 0.28)
                let shade = ModelEntity(mesh: .generateCylinder(height: 0.002, radius: 0.17), materials: [dark])
                shade.position.y = 0.002
                host.ground.addChild(shade)
                guard let actor = await KeeperActor.load(name, heightM: 0.4) else {
                    note = "No file named \(name)_ and a movement was found in the app."
                    return
                }
                actor.root.orientation = simd_quatf(angle: host.yawTowardCamera, axis: [0, 1, 0]) * simd_quatf(angle: -0.3, axis: [1, 0, 0])
                host.ground.addChild(actor.root)
                report(actor, picture: host.hasPicture)
                if freeze == "bend" {
                    // A look at the skin alone: bend the last joint by hand, with no movement playing.
                    bend(actor.root)
                    note = "\(name), bent by hand"
                    return
                }
                if let freeze, let colon = freeze.firstIndex(of: ":"), let second = Double(freeze[freeze.index(after: colon)...]) {
                    actor.freeze(String(freeze[..<colon]), at: second)
                    note = "\(name), \(freeze)"
                } else {
                    cycle(actor)
                }
            }
            .ignoresSafeArea()
        }
        .overlay(alignment: .top) {
            Text(note).font(.footnote.monospaced()).padding(8).background(.black.opacity(0.55), in: Capsule()).foregroundStyle(.white).padding(.top, 60)
        }
    }

    private func cycle(_ actor: KeeperActor) {
        let names = actor.clips.keys.sorted { a, b in a == "idle" || (b != "idle" && a < b) }
        Task {
            var k = 0
            while !Task.isCancelled {
                let clip = names[k % names.count]
                let long = actor.play(clip, loop: clip == "idle", fade: 0.25)
                note = "\(name), \(clip), \(String(format: "%.2f", long)) s"
                try? await Task.sleep(for: .seconds(clip == "idle" ? 2.0 : max(0.4, long)))
                k += 1
            }
        }
    }

    private func bend(_ entity: Entity) {
        if let model = entity as? ModelEntity, model.jointTransforms.count > 1 {
            var poses = model.jointTransforms
            poses[poses.count - 1].rotation = simd_quatf(angle: 0.9, axis: [1, 0, 0]) * poses[poses.count - 1].rotation
            poses[poses.count - 1].scale = [1.5, 1.5, 1.5]
            model.jointTransforms = poses
        }
        for child in entity.children { bend(child) }
    }

    private func tree(_ entity: Entity, depth: Int = 0) -> [String] {
        let kind = String(describing: type(of: entity))
        let joints = (entity as? ModelEntity)?.jointNames.count ?? 0
        let line = String(repeating: "  ", count: depth) + "\(entity.name.isEmpty ? "(no name)" : entity.name) \(kind) animations \(entity.availableAnimations.count) joints \(joints)"
        return [line] + entity.children.flatMap { tree($0, depth: depth + 1) }
    }

    private func report(_ actor: KeeperActor, picture: Bool) {
        let bounds = actor.root.visualBounds(relativeTo: nil)
        let found: [String: Any] = [
            "name": name, "picture": picture, "joints": actor.joints,
            "clips": actor.seconds.keys.sorted().map { ["name": $0, "seconds": actor.seconds[$0] ?? 0] },
            "height_m": Double(bounds.extents.y), "width_m": Double(bounds.extents.x), "depth_m": Double(bounds.extents.z),
            "tree": tree(actor.root),
        ]
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        if let data = try? JSONSerialization.data(withJSONObject: found, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: folder.appending(path: "spike.json"))
        }
    }
}
#endif
