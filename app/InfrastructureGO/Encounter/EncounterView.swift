import RealityKit
import SwiftUI

/// The catch. A creature stands on the drain, a ring shrinks around it, and the player swipes the marker up at it.
/// A throw while the ring is small is a great catch. The third throw always lands, so no walk to a drain is wasted.
struct EncounterView: View {
    @Environment(GameModel.self) private var game
    @Environment(\.dismiss) private var dismiss
    let head: Inlet

    @State private var scene = DrainScene()
    @State private var species: Species?
    @State private var tier: Tier = .common
    @State private var throwNumber = 1
    @State private var ringStart = Date()
    @State private var pull: CGSize = .zero
    @State private var flight: CGSize?
    @State private var busy = false
    @State private var note = "Swipe the marker up at the creature."
    @State private var result: CatchResult?
    @State private var gone = false

    var body: some View {
        GeometryReader { geometry in
            let centre = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let rest = CGPoint(x: geometry.size.width / 2, y: geometry.size.height - 150)
            ZStack {
                RealityView { content in
                    content.camera = .virtual
                    scene.build(species: species)
                    content.add(scene.root)
                    scene.subscription = content.subscribe(to: SceneEvents.Update.self) { event in
                        scene.tick(event.deltaTime)
                    }
                }
                .ignoresSafeArea()

                if !gone, let rules = game.content?.rules {
                    TimelineView(.animation) { timeline in
                        let scale = Ring.scale(elapsed: timeline.date.timeIntervalSince(ringStart), rules: rules.ring)
                        let great = throwNumber == 1 && scale <= rules.greatCatch.ringScaleMax
                        Circle()
                            .stroke(great ? Look.gold : .white, lineWidth: great ? 7 : 4)
                            .frame(width: 210 * scale, height: 210 * scale)
                            .shadow(color: .black.opacity(0.35), radius: 3)
                            .position(centre)
                    }
                    .allowsHitTesting(false)
                }

                if !gone {
                    marker(rest: rest, centre: centre)
                }
                hud
            }
        }
        .background(Color.black)
        .onAppear(perform: meet)
        .sheet(item: $result) { result in
            ResultCard(result: result) { dismiss() }
                .presentationDetents([.medium, .large])
                .interactiveDismissDisabled()
        }
    }

    /// The marker the player throws. It follows the finger, and when let go it flies where the swipe sent it.
    private func marker(rest: CGPoint, centre: CGPoint) -> some View {
        let moved = flight ?? pull
        let far = flight != nil
        return ZStack {
            Circle().fill(Look.zone).frame(width: 64, height: 64).overlay(Circle().stroke(.white, lineWidth: 3))
            Image(systemName: "mappin").font(.system(size: 28, weight: .bold)).foregroundStyle(.white)
        }
        .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
        .scaleEffect(far ? 0.35 : 1)
        .position(x: rest.x + moved.width, y: rest.y + moved.height)
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in if !busy { pull = value.translation } }
                .onEnded { value in if !busy { let_go(value.translation, rest: rest, centre: centre) } }
        )
        .accessibilityLabel("The marker to throw")
    }

    private var hud: some View {
        VStack {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(species?.name ?? "A drain").font(.title2.weight(.bold)).foregroundStyle(.white)
                    TierBadge(tier: tier)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark").font(.headline).foregroundStyle(.white).frame(width: 44, height: 44).background(.black.opacity(0.45), in: Circle())
                }
                .accessibilityLabel("Leave")
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            Spacer()
            if !gone {
                VStack(spacing: 4) {
                    Text(note).font(.subheadline.weight(.semibold))
                    Text(throwNumber >= (game.content?.rules.throwing.count ?? 3) ? "This throw always lands." : "Throw while the ring is small for a great catch.")
                        .font(.caption)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.black.opacity(0.5), in: Capsule())
                .padding(.bottom, 26)
            }
        }
    }

    private func meet() {
        tier = game.outlook(of: head)?.tier ?? .common
        species = game.species(of: head)
        #if DEBUG
        if let asked = game.opening.species, let forced = game.content?.species.first(where: { $0.id == asked }) {
            species = forced
            tier = Tier(rawValue: forced.tier) ?? tier
        }
        #endif
        ringStart = Date()
    }

    private func let_go(_ swipe: CGSize, rest: CGPoint, centre: CGPoint) {
        guard let rules = game.content?.rules else { return }
        let scale = Ring.scale(elapsed: Date().timeIntervalSince(ringStart), rules: rules.ring)
        let outcome = Throwing.outcome(throwNumber: throwNumber, swipeDX: swipe.width, swipeDY: swipe.height,
                                       aimDX: centre.x - rest.x, aimDY: centre.y - rest.y, ringScale: scale, rules: rules)
        busy = true
        let length = max(1, (swipe.width * swipe.width + swipe.height * swipe.height).squareRoot())
        let reach = (centre.y - rest.y).magnitude
        switch outcome {
        case .hit(let great):
            withAnimation(.easeOut(duration: 0.32)) { flight = CGSize(width: centre.x - rest.x, height: centre.y - rest.y) }
            after(0.32) {
                gone = true
                scene.caught()
                note = great ? "Great catch." : "Caught."
                after(0.85) { result = game.settle(head, great: great) }
            }
        case .miss:
            withAnimation(.easeOut(duration: 0.4)) { flight = CGSize(width: swipe.width / length * reach * 1.25, height: swipe.height / length * reach * 1.25) }
            after(0.4) {
                scene.miss()
                throwNumber += 1
                note = "Missed. Throw again."
                flight = nil
                pull = .zero
                ringStart = Date()
                busy = false
            }
        }
    }

    private func after(_ seconds: Double, _ work: @escaping () -> Void) {
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            work()
        }
    }
}
