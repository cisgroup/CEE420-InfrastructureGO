import RealityKit
import SwiftUI

/// A meeting at a drain. The keeper comes out and behaves the way its kind does, the player throws the survey
/// marker to its feet as an invitation, and the keeper accepts. A throw that reads the keeper's tell, onto the
/// patch where it is about to land, is the mastered catch. After three misses the keeper slips away to another
/// drain. Then the crate of the drain rises, and the result says what the meeting changed.
struct EncounterView: View {
    @Environment(GameModel.self) private var game
    @Environment(\.dismiss) private var dismiss
    let head: Inlet

    private enum Step { case loading, entering, live, flying, reacting, crate, opening, done }

    @State private var plan: MeetingPlan?
    @State private var host: VirtualHost?
    @State private var stage: EncounterStage?
    @State private var updates: EventSubscription?
    @State private var step = Step.loading
    @State private var misses = 0
    @State private var pull: CGSize = .zero
    @State private var flight: CGSize?
    @State private var hasThrown = false
    @State private var note = ""
    @State private var outcome: Outcome?
    @State private var result: MeetingResult?
    @State private var log: [String] = []
    @State private var ghost = false

    var body: some View {
        ZStack {
            GeometryReader { geometry in
                let rest = CGPoint(x: geometry.size.width / 2, y: geometry.size.height - 190)
                ZStack {
                    RealityView { content in
                        content.camera = .virtual
                        guard let plan = game.plan(for: head) else { return }
                        let host = await VirtualHost.make()
                        host.fit(screenAspect: geometry.size.width / max(1, geometry.size.height))
                        let stage = EncounterStage(host: host, plan: plan)
                        await stage.load()
                        host.root.addChild(stage.root)
                        content.add(host.root)
                        stage.onEvent = { event in heard(event) }
                        updates = content.subscribe(to: SceneEvents.Update.self) { event in stage.tick(event.deltaTime) }
                        self.plan = plan
                        self.host = host
                        self.stage = stage
                        misses = plan.misses
                        begin(size: geometry.size)
                    }
                    if step == .crate {
                        Color.clear.contentShape(Rectangle()).onTapGesture { openCrate() }
                    }
                    if step == .live || step == .flying {
                        marker(rest: rest, size: geometry.size)
                    }
                    if plan?.isFirst == true, step == .live, !hasThrown {
                        Image(systemName: "hand.point.up.left.fill").font(.system(size: 40)).foregroundStyle(.white).shadow(color: .black.opacity(0.5), radius: 4)
                            .position(x: rest.x + 26, y: rest.y + 30 - (ghost ? 205 : 0)).opacity(ghost ? 0.15 : 0.95).allowsHitTesting(false)
                            .onAppear { withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: false)) { ghost = true } }
                    }
                }
            }
            .ignoresSafeArea()
            hud
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
        .onAppear { game.inMeeting = true }
        .onDisappear {
            game.inMeeting = false
            updates?.cancel()
        }
        .sheet(item: $result) { result in
            ResultCard(result: result) { dismiss() }
                .presentationDetents([.large])
                .interactiveDismissDisabled()
        }
    }

    // MARK: what is on top of the picture

    /// The marker the player throws. It follows the finger, and when let go it flies to where the throw ends.
    private func marker(rest: CGPoint, size: CGSize) -> some View {
        let moved = flight ?? pull
        return ZStack {
            Circle().fill(Color(red: 0.93, green: 0.42, blue: 0.10)).frame(width: 68, height: 68).overlay(Circle().stroke(.white, lineWidth: 3))
            Circle().fill(.white).frame(width: 24, height: 24)
        }
        .shadow(color: .black.opacity(0.45), radius: 5, y: 3)
        .scaleEffect(flight != nil ? 0.42 : 1)
        .position(x: rest.x + moved.width, y: rest.y + moved.height)
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in if step == .live { pull = value.translation } }
                .onEnded { value in if step == .live { letGo(value.translation, rest: rest, size: size) } }
        )
        .accessibilityLabel("The marker to throw")
    }

    private var hud: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    if let keeper = plan?.keeper {
                        let known = game.progress.met.contains(keeper.id)
                        Text(known ? keeper.name : "???").font(Look.title(28)).foregroundStyle(.white)
                        if known {
                            Text(keeper.keeps).font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.9))
                            KindBadge(kind: keeper.kind)
                        }
                    }
                }
                .shadow(color: .black.opacity(0.6), radius: 4)
                Spacer()
                VStack(alignment: .trailing, spacing: 10) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark").font(.headline).foregroundStyle(.white).frame(width: 44, height: 44).background(.black.opacity(0.45), in: Circle())
                    }
                    .accessibilityLabel("Leave")
                    if plan?.isFirst == false, plan?.keeper != nil, let allowed = game.content?.world.catching.misses {
                        HStack(spacing: 5) {
                            ForEach(0..<allowed, id: \.self) { k in
                                Circle().fill(k < misses ? Color.white.opacity(0.25) : Color.white).frame(width: 9, height: 9)
                            }
                        }
                        .padding(7).background(.black.opacity(0.4), in: Capsule())
                        .accessibilityLabel("\(max(0, allowed - misses)) throws left before it slips away")
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            #if DEBUG
            if game.opening.moment != nil {
                Text("sound \(game.sound.last), tick \(game.haptics.last)").font(.caption2.monospaced()).foregroundStyle(.white).padding(4).background(.black.opacity(0.5))
            }
            #endif
            Spacer()
            if !note.isEmpty {
                Text(note).font(.subheadline.weight(.semibold)).multilineTextAlignment(.center).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 9).background(.black.opacity(0.55), in: Capsule()).padding(.horizontal, 20)
            }
            Text("Desk play. The picture shows another Princeton drain. No observation is recorded.")
                .font(.caption2).foregroundStyle(.white.opacity(0.85)).multilineTextAlignment(.center).padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 4)
                .shadow(color: .black.opacity(0.7), radius: 3)
        }
    }

    // MARK: the meeting

    private func begin(size: CGSize) {
        guard let plan, let stage else { return }
        game.haptics.ready()
        guard plan.keeper != nil else {
            outcome = .looked
            toCrate()
            return
        }
        step = .entering
        stage.enter()
        after(1.4) {
            step = .live
            note = plan.isFirst ? "Drag the marker to the frog and let go." : hint(plan)
            #if DEBUG
            if let moment = game.opening.moment { hold(at: moment, size: size) }
            #endif
        }
    }

    private func hint(_ plan: MeetingPlan) -> String {
        guard let keeper = plan.keeper else { return "" }
        let page = Journal.page(of: keeper.id, in: game.progress, rungs: game.content?.world.rungs ?? [1, 3, 7, 15])
        if page.meetings == 0 { return "Throw the marker to its feet." }
        if page.seals == 0 { return keeper.tell }
        return keeper.returning
    }

    private func screen(_ place: SIMD3<Float>, lift: Double, size: CGSize) -> CGPoint? {
        host?.backdrop.project(x: Double(place.x), z: Double(place.z), lift: lift, screenAspect: size.width / max(1, size.height))
            .map { CGPoint(x: $0.u * size.width, y: $0.v * size.height) }
    }

    private func letGo(_ swipe: CGSize, rest: CGPoint, size: CGSize) {
        guard let plan, let stage, let host, let rule = game.content?.world.catching else { return }
        let time = stage.time
        let beat = plan.timeline.beat(at: time)
        let leaving = (beat.phase == .tell || beat.phase == .air) && beat.next != beat.spot
        guard let keeperAt = screen(stage.placeInFront(ofSpot: beat.spot), lift: 0, size: size) else { return }
        let patchAt = leaving ? screen(stage.place(ofSpot: beat.next), lift: 0, size: size) : nil
        let aim = Judge.aim(swipeDX: swipe.width, swipeDY: swipe.height, restX: rest.x, restY: rest.y, keeperX: keeperAt.x, keeperY: keeperAt.y,
                            patch: patchAt.map { (x: Double($0.x), y: Double($0.y)) }, toleranceDeg: plan.aimDeg)
        let length = (swipe.width * swipe.width + swipe.height * swipe.height).squareRoot()
        let thrown = Judge.judge(release: time, timeline: plan.timeline, aim: aim, swipePt: length, rule: rule, easy: plan.easy)

        // Where the marker comes down, on the screen and on the ground.
        var end = keeperAt
        var ground = stage.placeInFront(ofSpot: beat.spot)
        switch thrown {
        case .mastered:
            end = patchAt ?? keeperAt
            ground = stage.place(ofSpot: beat.next)
        case .caught, .gone:
            if aim == .patch, let patchAt {
                end = patchAt
                ground = stage.place(ofSpot: beat.next)
            }
        case .short, .wide:
            let reach = (keeperAt.y - rest.y).magnitude * (thrown == .short ? 0.45 : 1.2)
            end = CGPoint(x: rest.x + swipe.width / max(1, length) * reach, y: rest.y + swipe.height / max(1, length) * reach)
            if let fell = host.backdrop.ground(u: end.x / size.width, v: end.y / size.height, screenAspect: size.width / max(1, size.height)) {
                ground = [Float(fell.x), 0, Float(fell.z)]
            }
        }
        hasThrown = true
        step = .flying
        note = ""
        if thrown == .caught { stage.holdStill() }
        game.sound.play("swish", volume: 0.8)
        log.append("throw \(thrown) sound=swish")
        withAnimation(.easeOut(duration: rule.flightS)) { flight = CGSize(width: end.x - rest.x, height: end.y - rest.y) }
        after(rule.flightS) {
            step = .reacting
            flight = nil
            pull = .zero
            stage.resolve(thrown, at: ground) { settled(thrown) }
        }
    }

    private func settled(_ thrown: Throw) {
        guard let plan, let stage, let rule = game.content?.world.catching else { return }
        switch thrown {
        case .caught, .mastered:
            outcome = thrown == .mastered ? .mastered : .caught
            toCrate()
        case .short, .wide, .gone:
            if plan.isFirst {
                note = "Almost. Drag the marker to the frog and let go."
                step = .live
                return
            }
            misses = game.missed(at: head)
            if misses >= rule.misses {
                note = "It slipped away. It waits at another drain close by."
                stage.slip {
                    outcome = .slipped
                    toCrate()
                }
            } else {
                switch thrown {
                case .short: note = "Too short. Swipe further."
                case .wide: note = "Past it. Aim at its feet."
                default: note = "It was not there. Wait until it sits, or throw to the patch."
                }
                step = .live
            }
        }
    }

    private func toCrate() {
        guard let plan, let stage else { return }
        guard plan.crateParts > 0 else {
            finish()
            return
        }
        after(plan.keeper == nil ? 0.3 : 0.5) {
            step = .crate
            stage.showCrate()
            note = "Tap the crate."
        }
    }

    private func openCrate() {
        guard step == .crate, let plan, let stage else { return }
        step = .opening
        note = ""
        stage.openCrate(parts: plan.crateParts) { finish() }
    }

    private func finish() {
        guard step != .done, let plan else { return }
        step = .done
        note = ""
        result = game.settle(head, keeper: plan.keeper, outcome: outcome ?? .looked)
        #if DEBUG
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        if let data = try? JSONSerialization.data(withJSONObject: ["drain": head.id, "events": log], options: [.prettyPrinted]) {
            try? data.write(to: folder.appending(path: "meeting.json"))
        }
        #endif
    }

    /// Something happened on the stage. It gets its sound and its tick, and a line in the log of the meeting.
    private func heard(_ event: StageEvent) {
        let sound = MeetingSounds.sound(for: event)
        if let sound { game.sound.play(sound.name, volume: sound.volume) }
        switch MeetingSounds.tick(for: event) {
        case "tap": game.haptics.tap()
        case "thud": game.haptics.thud()
        case "success": game.haptics.success()
        case "warning": game.haptics.warning()
        case "tick": game.haptics.tick()
        default: break
        }
        log.append("\(event.rawValue) sound=\(sound?.name ?? "none") tick=\(MeetingSounds.tick(for: event) ?? "none")")
    }

    private func after(_ seconds: Double, _ work: @escaping () -> Void) {
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            work()
        }
    }

    #if DEBUG
    /// Bring the meeting to a named moment and leave it there, for a picture of that moment.
    private func hold(at moment: String, size: CGSize) {
        guard let plan, let stage else { return }
        switch moment {
        case "crouch", "air", "land":
            stage.hold(at: moment)
            note = "held at \(moment)"
        case "hit":
            let beat = plan.timeline.beat(at: stage.time)
            stage.holdStill()
            step = .reacting
            stage.resolve(.caught, at: stage.placeInFront(ofSpot: beat.spot)) { outcome = .caught }
        case "mastered":
            guard let tell = plan.timeline.beats.first(where: { $0.phase == .tell && $0.next != $0.spot }) else { return }
            stage.hold(at: "crouch")
            step = .reacting
            stage.resolve(.mastered, at: stage.place(ofSpot: tell.next)) { outcome = .mastered }
        case "miss":
            let beat = plan.timeline.beat(at: stage.time)
            step = .reacting
            stage.resolve(.wide, at: stage.placeInFront(ofSpot: (beat.spot + 1) % 3)) { step = .live }
        case "slip":
            step = .reacting
            stage.slip { outcome = .slipped }
        case "crate":
            outcome = .caught
            toCrate()
        case "open":
            outcome = .caught
            toCrate()
            after(1.2) { openCrate() }
        default:
            break
        }
    }
    #endif
}

/// The sound and the tick of each thing that happens in a meeting, in one table.
enum MeetingSounds {
    static func sound(for event: StageEvent) -> (name: String, volume: Float)? {
        switch event {
        case .rattle: ("rattle", 0.8)
        case .pop: ("pop", 0.9)
        case .tell: nil
        case .hop: nil
        case .land: ("hop", 0.7)
        case .hide: ("slip", 0.4)
        case .tap: ("tap", 0.9)
        case .accept: ("accept", 0.9)
        case .proud: ("hello", 0.9)
        case .refuse: ("refuse", 0.7)
        case .slip: ("slip", 0.9)
        case .crate: ("crate", 0.9)
        case .open: ("open", 0.9)
        case .part: ("part", 0.8)
        }
    }

    static func tick(for event: StageEvent) -> String? {
        switch event {
        case .rattle, .part, .tell: "tick"
        case .tap, .land: "tap"
        case .proud, .open: "thud"
        case .accept: "success"
        case .refuse, .slip: "warning"
        case .pop, .hop, .hide, .crate: nil
        }
    }
}
