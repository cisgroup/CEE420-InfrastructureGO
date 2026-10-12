import Foundation
import Testing
@testable import InfrastructureGO

@Suite("The journal")
struct JournalTests {
    let start = try! instant("2026-11-10T15:00:00-05:00")

    func progress(_ outcomes: [Outcome], keeper: String = "frog") -> PlayerProgress {
        var progress = PlayerProgress()
        for (k, outcome) in outcomes.enumerated() {
            progress.meetings.append(Meeting(id: UUID(), site: "in\(1000 + k)", keeper: keeper, outcome: outcome, need: 3, points: 30, parts: 3,
                                             at: start.addingTimeInterval(Double(k) * 600)))
        }
        return progress
    }

    @Test("a rung is reached at exactly its meetings", arguments: [(0, Rung.stranger), (1, .met), (2, .met), (3, .known), (6, .known), (7, .friend), (14, .friend), (15, .oldFriend), (99, .oldFriend)])
    func rung(meetings: Int, rung: Rung) throws {
        #expect(Journal.rung(meetings: meetings, rungs: try Repo.world().rungs) == rung)
    }

    @Test func aPageCountsTheMeetingsThatWonTheKeeper() throws {
        let rungs = try Repo.world().rungs
        let page = Journal.page(of: "frog", in: progress([.caught, .slipped, .mastered, .caught, .slipped]), rungs: rungs)
        #expect(page.meetings == 3 && page.seals == 1 && page.rung == .known && page.nextRung == .friend && page.nextAt == 7)
        #expect(page.firstSite == "in1000" && page.firstAt == start)
        let none = Journal.page(of: "glub", in: progress([.caught]), rungs: rungs)
        #expect(none.meetings == 0 && none.rung == .stranger && none.nextAt == 1 && none.firstAt == nil)
        let old = Journal.page(of: "frog", in: progress(Array(repeating: .caught, count: 15)), rungs: rungs)
        #expect(old.rung == .oldFriend && old.nextRung == nil && old.nextAt == nil)
    }

    @Test func everyMeetingChangesTheLine() throws {
        let rungs = try Repo.world().rungs
        let frog = try #require(try Repo.keepers().first)
        func line(_ before: [Outcome], then last: Outcome) -> String {
            Journal.line(frog, before: Journal.page(of: "frog", in: progress(before), rungs: rungs),
                         after: Journal.page(of: "frog", in: progress(before + [last]), rungs: rungs), mastered: last == .mastered)
        }
        #expect(line([], then: .caught) == "New in your journal.")
        #expect(line([.caught], then: .caught) == "2 of 3 meetings until you know its crouch.")
        #expect(line([.caught, .caught], then: .caught) == "You know its crouch now.")
        #expect(line([.caught, .caught, .caught], then: .caught) == "4 of 7 meetings until it is a friend.")
        #expect(line([.caught], then: .mastered) == "That proud hop belongs in your journal.")
        #expect(line([.caught, .mastered], then: .mastered) == "You know its crouch now.", "a new rung is said before another seal")
        #expect(line([.caught, .mastered, .caught], then: .mastered) == "Another proud hop. 2 seals now.")
        #expect(line(Array(repeating: .caught, count: 6), then: .caught) == "Frog counts you as a friend now.")
        #expect(line(Array(repeating: .caught, count: 14), then: .caught) == "An old friend by now.")
        #expect(line(Array(repeating: .caught, count: 20), then: .caught) == frog.returning)
    }
}
