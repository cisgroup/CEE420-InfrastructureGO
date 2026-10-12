import Foundation
import RealityKit
import Testing
import UIKit
@testable import InfrastructureGO

/// What only the app itself can show: that its bundle carries every file the game's data names, and that a
/// meeting asks for its sounds and ticks in the right order. These run inside the simulator. None of them loads
/// a model or a picture into RealityKit, because that was seen to stall a test run for minutes. The meetings
/// here are played by the round stand-in on the modelled drain, which exercises the same stage.
@MainActor
@Suite("What the app carries and plays")
struct BundleTests {
    @Test func everyKeeperHasItsMovementsAndItsPictures() throws {
        let content = try GameContent.bundled()
        #expect(!content.keepers.isEmpty)
        for keeper in content.keepers {
            for clip in Set(keeper.clips.values) {
                #expect(Bundle.main.url(forResource: "\(keeper.model)_\(clip)", withExtension: "usdz") != nil, "\(keeper.model)_\(clip).usdz is not in the app")
            }
            #expect(Look.picture(of: keeper.id) != nil, "\(keeper.id) has no portrait")
            #expect(Look.picture(of: keeper.id, pose: true) != nil, "\(keeper.id) has no second pose")
        }
        #expect(Look.picture(of: "no such keeper") == nil, "a keeper without a picture is noticed")
    }

    @Test func everySoundIsInTheAppAndHasALength() {
        let lengths = SoundBox.lengths()
        for name in SoundBox.names {
            #expect((lengths[name] ?? 0) > 0.02, "the sound \(name) is missing or empty")
        }
        #expect(lengths["no such sound"] == nil)
    }

    @Test func everyMomentOfAMeetingCanBeHeardOrFelt() {
        let ticks: Set<String> = ["tick", "tap", "thud", "success", "warning"]
        for event in StageEvent.allCases {
            if let sound = MeetingSounds.sound(for: event) { #expect(SoundBox.names.contains(sound.name)) }
            if let tick = MeetingSounds.tick(for: event) { #expect(ticks.contains(tick)) }
        }
        for event in [StageEvent.rattle, .pop, .land, .tap, .accept, .proud, .refuse, .slip, .crate, .open, .part] {
            #expect(MeetingSounds.sound(for: event) != nil, "\(event.rawValue) is silent")
        }
    }

    /// A meeting on the modelled drain with a keeper that has no model file, so that nothing is loaded.
    private func stage(timeline: Timeline, first: Bool) throws -> EncounterStage {
        let content = try GameContent.bundled()
        let head = try #require(content.inlets["in1375"])
        let frog = try #require(content.book.keeper("frog"))
        let standIn = Keeper(id: frog.id, name: frog.name, part: frog.part, keeps: frog.keeps, kind: frog.kind, pattern: frog.pattern, model: "no_such_model",
                             heightM: frog.heightM, hoverM: 0, weight: 1, habitat: frog.habitat, timing: frog.timing, clips: frog.clips, tell: frog.tell,
                             tellWord: frog.tellWord, hint: frog.hint, returning: frog.returning, pose: frog.pose, joke: frog.joke, credit: frog.credit)
        let plan = MeetingPlan(head: head, keeper: standIn, timeline: timeline, isFirst: first, misses: 0, crateParts: 3, aimDeg: 25, pulse: false, easy: false)
        return EncounterStage(host: VirtualHost(backdrop: .modelled, picture: nil), plan: plan)
    }

    @Test func aMeetingAsksForItsSoundsInOrder() async throws {
        let stage = try stage(timeline: .sitting(), first: true)
        await stage.load()
        var heard: [StageEvent] = []
        stage.onEvent = { heard.append($0) }
        func run(_ seconds: Double) { for _ in 0..<Int(seconds * 60) { stage.tick(1.0 / 60) } }

        stage.enter()
        run(1.5)
        #expect(stage.isLive, "the keeper is out and the meeting has begun")
        stage.holdStill()
        var won = false
        stage.resolve(.caught, at: stage.placeInFront(ofSpot: 1)) { won = true }
        run(2.3)
        #expect(won)
        stage.showCrate()
        run(0.6)
        var opened = false
        stage.openCrate(parts: 3) { opened = true }
        run(2.0)
        #expect(opened)
        #expect(heard == [.rattle, .pop, .tap, .accept, .crate, .open, .part, .part, .part])
        #expect(heard.compactMap { MeetingSounds.sound(for: $0)?.name } == ["rattle", "pop", "tap", "accept", "crate", "open", "part", "part", "part"])
    }

    @Test func aKeeperHopsOnItsOwnAndThreeMissesMakeItSlipAway() async throws {
        let frog = try #require(try GameContent.bundled().book.keeper("frog"))
        let stage = try stage(timeline: Timeline.make(seed: "test", timing: frog.timing), first: false)
        await stage.load()
        var heard: [StageEvent] = []
        stage.onEvent = { heard.append($0) }
        func run(_ seconds: Double) { for _ in 0..<Int(seconds * 60) { stage.tick(1.0 / 60) } }
        stage.enter()
        run(1.5)
        run(6)
        #expect(heard.contains(.tell) && heard.contains(.hop) && heard.contains(.land), "left alone, the keeper gives its tell, hops and lands")
        var refused = 0
        for _ in 0..<2 {
            stage.resolve(.wide, at: stage.placeInFront(ofSpot: 0)) { refused += 1 }
            run(3.0)
        }
        #expect(refused == 2 && heard.filter { $0 == .refuse }.count == 2)
        var gone = false
        stage.slip { gone = true }
        run(1.2)
        #expect(gone && heard.contains(.slip))
    }

    @Test func aThrowOntoThePatchIsAnsweredWhenTheKeeperLands() async throws {
        let frog = try #require(try GameContent.bundled().book.keeper("frog"))
        let line = Timeline.make(seed: "patch", timing: frog.timing)
        let tell = try #require(line.beats.first { $0.phase == .tell && $0.next != $0.spot })
        let stage = try stage(timeline: line, first: false)
        await stage.load()
        var heard: [StageEvent] = []
        stage.onEvent = { heard.append($0) }
        func run(_ seconds: Double) { for _ in 0..<Int(seconds * 60) { stage.tick(1.0 / 60) } }
        stage.enter()
        run(1.3 + 1.0 / 60)
        run(tell.start + 0.3)
        var proud = false
        stage.resolve(.mastered, at: stage.place(ofSpot: tell.next)) { proud = true }
        #expect(!heard.contains(.proud), "the keeper is still on its way")
        run(4.0)
        #expect(proud && heard.contains(.proud))
        #expect(heard.firstIndex(of: .proud)! > heard.lastIndex(of: .land)!, "it is proud once it has landed on the marker")
    }

    @Test func theModelledDrainStandsInWhereThereIsNoPhotograph() {
        let host = VirtualHost(backdrop: .modelled, picture: nil)
        #expect(!host.hasPicture && !host.ground.children.isEmpty, "without a photograph the modelled drain is built")
        for backdrop in VirtualHost.backdrops() {
            #expect(backdrop.heightM > 1 && backdrop.pitchDeg > 20 && Bundle.main.url(forResource: backdrop.file, withExtension: "jpg") != nil)
        }
    }

    @Test func aFileOfTheFirstVersionGivesAFreshStart() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "progress-\(UUID().uuidString).json")
        try Data(#"{"catches": [{"id": "A0B1C2D3-0000-0000-0000-000000000000", "site": "in1375", "species": "green_frog", "tier": 3, "points": 30, "great": false, "at": "2026-10-11T12:00:00Z"}]}"#.utf8).write(to: file)
        let store = ProgressStore(file: file)
        #expect(store.load() == PlayerProgress())
        var progress = PlayerProgress()
        progress.figure = "b"
        progress.parts = ["boots": 2]
        store.save(progress)
        #expect(store.load() == progress)
        store.erase()
        #expect(store.load() == PlayerProgress())
    }
}
