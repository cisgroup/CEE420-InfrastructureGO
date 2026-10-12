import Foundation
import Testing
@testable import InfrastructureGO

@Suite("A meeting from start to finish")
struct PlayTests {
    let now = try! instant("2026-11-10T15:00:00-05:00")

    func site(_ id: String) throws -> Inlet { try #require(try Repo.inlets()[id]) }

    /// A book with a larger cast than the file has yet, so that new kinds and visitors can be tried.
    func bigBook() throws -> Book {
        let book = try Repo.book()
        let cast = book.keepers + [madeUpKeeper("glub", kind: "uncommon"), madeUpKeeper("heron", kind: "rare"), madeUpKeeper("dragon", kind: "visitor")]
        return Book(rules: book.rules, world: book.world, keepers: cast, gear: book.gear, jobs: book.jobs)
    }

    @Test func theFirstKeeperOfEveryPlayerIsTheFrog() throws {
        let book = try bigBook()
        for id in ["in1375", "in1376", "in1356", "in1403"] {
            #expect(Play.keeper(at: try site(id), grates: 1, progress: PlayerProgress(), now: now, book: book)?.id == "frog")
        }
    }

    @Test func aFirstLookWinsTheKeeperAFullCrateAndTheFirstPieceOfGear() throws {
        let book = try Repo.book(), drain = try site("in1375")
        let frog = try #require(Play.keeper(at: drain, grates: 1, progress: PlayerProgress(), now: now, book: book))
        let (result, grown) = Play.settle(site: drain, keeper: frog, outcome: .caught, progress: PlayerProgress(), now: now, book: book)
        #expect(result.need == .rare && result.meeting.points == 80, "30 for a first look and 50 for a keeper new to the player")
        #expect(result.line == "New in your journal." && result.look == "30 points for your first look at this drain.")
        #expect(result.crateParts == 3 && result.finished.map(\.id) == ["boots"] && result.thanks == 0)
        #expect(result.page?.meetings == 1 && result.page?.rung == .met && result.pageBefore?.meetings == 0)
        #expect(grown.points == 80 && grown.meetings.count == 1 && grown.known.contains("in1375") && grown.hasMetAnyone)
        #expect(Gear.opens("wide_veil", parts: grown.parts, in: book.gear))
    }

    @Test func afterALookTheDrainRestsForTheDay() throws {
        let book = try Repo.book(), drain = try site("in1375")
        let frog = try #require(book.keeper("frog"))
        let (_, grown) = Play.settle(site: drain, keeper: frog, outcome: .caught, progress: PlayerProgress(), now: now, book: book)
        let later = now.addingTimeInterval(3600)
        #expect(Play.rests(site: "in1375", progress: grown, now: later, rules: book.rules))
        #expect(Play.keeper(at: drain, grates: 1, progress: grown, now: later, book: book) == nil)
        let (again, twice) = Play.settle(site: drain, keeper: nil, outcome: .looked, progress: grown, now: later, book: book)
        #expect(again.need == .resting && again.meeting.points == 2 && again.crateParts == 0 && again.filled.isEmpty)
        #expect(again.look == "2 points. You already looked here today." && again.line == "A look that counts.")
        #expect(twice.points == 82)
        let tomorrow = now.addingTimeInterval(86_400)
        #expect(Play.need(site: "in1375", progress: twice, now: tomorrow, rules: book.rules) == .common)
        #expect(Play.crateParts(need: .common, world: book.world) == 1)
        #expect(Play.keeper(at: drain, grates: 1, progress: twice, now: tomorrow, book: book) != nil, "a keeper is there again the next day")
        #expect(Play.need(site: "in1375", progress: twice, now: now.addingTimeInterval(5 * 86_400), rules: book.rules) == .uncommon)
        #expect(Play.need(site: "in1375", progress: twice, now: now.addingTimeInterval(15 * 86_400), rules: book.rules) == .rare, "a forgotten drain pays in full again")
    }

    @Test func aMasteredCatchPaysMoreAndEarnsTheSeal() throws {
        let book = try Repo.book(), frog = try #require(book.keeper("frog"))
        var progress = PlayerProgress()
        (_, progress) = Play.settle(site: try site("in1375"), keeper: frog, outcome: .caught, progress: progress, now: now, book: book)
        let (result, grown) = Play.settle(site: try site("in1376"), keeper: frog, outcome: .mastered, progress: progress, now: now.addingTimeInterval(120), book: book)
        #expect(result.meeting.points == 55, "30 for the look and 25 for the mastered catch, the frog is no longer new")
        #expect(result.line == "That proud hop belongs in your journal." && result.page?.seals == 1)
        #expect(grown.points == 135 && result.levelParts == 1, "the second look crossed 100 points, and the level handed over a part")
        #expect(result.before.level == 1 && result.after.level == 2)
    }

    @Test func aKeeperThatSlippedAwayWaitsAtTheOtherDrainAndTheLookStillCounts() throws {
        let book = try bigBook(), glub = try #require(book.keeper("glub")), frog = try #require(book.keeper("frog"))
        var progress = PlayerProgress()
        (_, progress) = Play.settle(site: try site("in1375"), keeper: frog, outcome: .caught, progress: progress, now: now, book: book)
        let (result, grown) = Play.settle(site: try site("in1376"), keeper: glub, outcome: .slipped, slipTo: try site("in1350"), progress: progress, now: now, book: book)
        #expect(result.slippedTo == "in1350" && result.line == "It slipped away. It waits at another drain close by.")
        #expect(result.meeting.points == 30 && result.crateParts == 3, "the look counts and the crate is there, the keeper is not won")
        #expect(grown.waiting.map(\.keeper) == ["glub"] && grown.waiting[0].site == "in1350" && !grown.met.contains("glub"))
        #expect(Play.keeper(at: try site("in1350"), grates: 1, progress: grown, now: now, book: book)?.id == "glub")
        let (caught, after) = Play.settle(site: try site("in1350"), keeper: glub, outcome: .caught, progress: grown, now: now.addingTimeInterval(600), book: book)
        #expect(after.waiting.isEmpty && caught.line == "New in your journal." && after.met.contains("glub"))
    }

    @Test func noMoreThanThreeKeepersWait() throws {
        let book = try bigBook(), glub = try #require(book.keeper("glub"))
        var progress = PlayerProgress()
        for (k, pair) in [("in1375", "in1350"), ("in1376", "in1351"), ("in1356", "in1352"), ("in1357", "in1353")].enumerated() {
            (_, progress) = Play.settle(site: try site(pair.0), keeper: glub, outcome: .slipped, slipTo: try site(pair.1), progress: progress, now: now.addingTimeInterval(Double(k) * 60), book: book)
        }
        #expect(progress.waiting.map(\.site) == ["in1351", "in1352", "in1353"], "the one that waited longest went home")
    }

    @Test func missesAreKeptWhenThePlayerLeavesAndGoWithTheLook() throws {
        let book = try Repo.book(), frog = try #require(book.keeper("frog"))
        var progress = PlayerProgress()
        progress = Play.missed(at: "in1375", progress: progress, now: now, rules: book.rules)
        progress = Play.missed(at: "in1375", progress: progress, now: now.addingTimeInterval(60), rules: book.rules)
        #expect(Play.misses(at: "in1375", progress: progress, now: now, rules: book.rules) == 2)
        #expect(Play.misses(at: "in1376", progress: progress, now: now, rules: book.rules) == 0)
        #expect(Play.misses(at: "in1375", progress: progress, now: now.addingTimeInterval(86_400), rules: book.rules) == 0, "a new day is a new try")
        (_, progress) = Play.settle(site: try site("in1375"), keeper: frog, outcome: .caught, progress: progress, now: now, book: book)
        #expect(progress.misses.isEmpty)
    }

    @Test func aHuntEndsWhenItsKeeperIsWonAndAVisitorIsMetOnceAWeek() throws {
        let book = try bigBook(), heron = try #require(book.keeper("heron")), dragon = try #require(book.keeper("dragon")), frog = try #require(book.keeper("frog"))
        var progress = PlayerProgress()
        (_, progress) = Play.settle(site: try site("in1375"), keeper: frog, outcome: .caught, progress: progress, now: now, book: book)
        progress.hunt = Hunt(keeper: "heron", site: "in1350", week: "2026-W46")
        (_, progress) = Play.settle(site: try site("in1376"), keeper: frog, outcome: .caught, progress: progress, now: now, book: book)
        #expect(progress.hunt != nil, "another drain does not end the hunt")
        (_, progress) = Play.settle(site: try site("in1350"), keeper: heron, outcome: .caught, progress: progress, now: now, book: book)
        #expect(progress.hunt == nil)
        let visit = (site: try site("in1356"), keeper: dragon)
        #expect(Play.keeper(at: visit.site, grates: 1, progress: progress, now: now, book: book, visitor: visit)?.id == "dragon")
        (_, progress) = Play.settle(site: visit.site, keeper: dragon, outcome: .mastered, progress: progress, now: now, book: book)
        #expect(progress.visitorsMet == ["2026-W46|west"])
        let nextDay = now.addingTimeInterval(86_400)
        #expect(Play.keeper(at: visit.site, grates: 1, progress: progress, now: nextDay, book: book, visitor: visit)?.id != "dragon", "the visitor was met this week")
    }

    @Test func partsThatFindNoPieceBecomeAThankYou() throws {
        let book = try Repo.book(), frog = try #require(book.keeper("frog"))
        var progress = PlayerProgress()
        for piece in book.gear.pieces { progress.parts[piece.id] = piece.parts }
        let (result, grown) = Play.settle(site: try site("in1375"), keeper: frog, outcome: .caught, progress: progress, now: now, book: book)
        #expect(result.filled.isEmpty && result.thanks == 3 * book.world.points.thanks && grown.bonusPoints == result.thanks)
        #expect(grown.points == 80 + result.thanks)
    }

    @Test func jobsCountALookAndPayAPart() throws {
        let book = try Repo.book(), frog = try #require(book.keeper("frog"))
        var progress = PlayerProgress()
        progress.jobs = [Job(rule: "new_drain", text: "Find a drain you have never been to", kind: "new_sites", count: 1, done: 0, drawnOn: "2026-11-10", finishedOn: nil)]
        let (result, grown) = Play.settle(site: try site("in1375"), keeper: frog, outcome: .caught, progress: progress, now: now, book: book)
        #expect(result.jobsDone.map(\.rule) == ["new_drain"] && result.jobParts == 1)
        #expect(grown.parts["boots"] == 3 && grown.parts["long_coil"] == 1, "three parts from the crate and one from the job")
    }

    /// A walk through the western zone from Mountain Avenue, the nearest drain first, every look a catch.
    func walk(_ looks: Int, book: Book) throws -> (pieces: [Int], emptyBefore: Int?) {
        let store = try Repo.inlets()
        let west = try drainsOfTheGame().filter { $0.zone == "west" }
        var left = west
        var here = Coordinate(lon: -74.672675, lat: 40.356792)
        var progress = PlayerProgress()
        progress.jobs = Jobs.refresh([], day: "2026-11-10", rules: book.jobs, possible: ["looks", "new_sites", "seal", "cells"], slots: book.world.jobs.slots)
        var pieces: [Int] = []
        var emptyBefore: Int?
        for k in 0..<min(looks, west.count) {
            let next = try #require(left.min { Geo.distance(here, $0.coordinate) < Geo.distance(here, $1.coordinate) })
            left.removeAll { $0.id == next.id }
            here = next.coordinate
            let keeper = Play.keeper(at: next, grates: store.members(ofSite: next.id).count, progress: progress, now: now.addingTimeInterval(Double(k) * 90), book: book)
            let (result, grown) = Play.settle(site: next, keeper: keeper, outcome: .caught, progress: progress, now: now.addingTimeInterval(Double(k) * 90), book: book)
            progress = grown
            if result.thanks > 0 && emptyBefore == nil && Gear.missing(parts: progress.parts, in: book.gear) > 0 { emptyBefore = k }
            pieces.append(Gear.owned(parts: progress.parts, in: book.gear).count - 1)
        }
        return (pieces, emptyBefore)
    }

    @Test func aFirstSessionLeavesGearToWantAndAWalkThroughAZoneEarnsItAll() throws {
        let book = try Repo.book()
        let walked = try walk(138, book: book)
        #expect(walked.pieces[0] == 1, "the first drain finishes the first piece, so that gear is felt at once")
        #expect(walked.pieces[14] <= 5 && walked.pieces[14] >= 3, "after fifteen drains \(walked.pieces[14]) pieces are finished")
        let all = book.gear.pieces.count - 1
        let last = try #require(walked.pieces.firstIndex(of: all))
        #expect(last + 1 >= 40 && last + 1 <= 80, "the last piece came with look \(last + 1)")
        #expect(walked.emptyBefore == nil, "no crate is empty while gear is still to be earned")
    }

    @Test func progressComesBackFromItsFileAndAnOldFileIsRefused() throws {
        let book = try Repo.book(), frog = try #require(book.keeper("frog"))
        var progress = PlayerProgress()
        (_, progress) = Play.settle(site: try site("in1375"), keeper: frog, outcome: .mastered, progress: progress, now: now, book: book)
        progress.waiting = [Waiting(keeper: "frog", site: "in1350", from: "in1375", since: now)]
        progress.hunt = Hunt(keeper: "frog", site: "in1351", week: "2026-W46")
        progress.told = ["nearby"]
        let encoder = JSONEncoder(), decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        let back = try decoder.decode(PlayerProgress.self, from: encoder.encode(progress))
        #expect(back == progress)
        let sparse = try decoder.decode(PlayerProgress.self, from: Data(#"{"version": 2}"#.utf8))
        #expect(sparse == PlayerProgress(), "a file that lacks newer parts is read with their start values")
        #expect(throws: (any Error).self) { try decoder.decode(PlayerProgress.self, from: Data(#"{"catches": []}"#.utf8)) }
    }

    @Test func theWordsArePlainAndCarryNoDash() throws {
        let book = try Repo.book()
        var said = [Words.lastLook(nil, now: now), Words.lastLook(now.addingTimeInterval(-3 * 86_400), now: now), Words.crate(parts: 0), Words.crate(parts: 3),
                    Words.hint(road: "Bayard Lane", bearing: 10), Words.hint(road: "", bearing: 200), Words.fence(.walkCloser(distanceM: 34)), Words.grates(2)]
        said += Tier.allCases.map { Words.look(points: 30, need: $0, last: nil, now: now) }
        said += [Reading.State.noFix, .outside, .quiet, .atDrain, .signal].map { Words.detector(Reading(state: $0, site: nil, distanceM: 90, bearing: 0, strength: 0.4, kind: nil)) }
        said += book.keepers.flatMap { [$0.name, $0.keeps, $0.tell, $0.hint, $0.returning, $0.pose, $0.joke] }
        said += book.gear.pieces.flatMap { [$0.name, $0.says] } + book.gear.levels.map(\.rank) + book.jobs.map(\.text)
        for text in said {
            #expect(!text.contains("—") && !text.contains("–") && !text.contains(" - "), "a dash in: \(text)")
        }
        #expect(Words.lastLook(now.addingTimeInterval(-3 * 86_400), now: now) == "You last looked here 3 days ago.")
        #expect(Words.hint(road: "Bayard Lane", bearing: 0) == "Your detector picked up something unusual near Bayard Lane.")
        #expect(Words.hint(road: "", bearing: 200) == "Your detector picked up something unusual in the streets south of you.")
        #expect(Words.hint(road: "", bearing: 350).hasSuffix("north of you."))
        #expect(Words.count(1, "seal", "seals") == "1 seal" && Words.count(2, "seal", "seals") == "2 seals")
    }
}
