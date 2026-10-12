import Foundation
import Testing
@testable import InfrastructureGO

@Suite("The small jobs")
struct JobsTests {
    let all: Set<String> = ["looks", "new_sites", "new_keeper", "seal", "cells"]

    @Test func threeDifferentJobsAreDrawnAndTheSameOnesOnTheSameDay() throws {
        let rules = try Repo.jobs()
        let jobs = Jobs.refresh([], day: "2026-11-10", rules: rules, possible: all, slots: 3)
        #expect(jobs.count == 3 && Set(jobs.map(\.kind)).count == 3)
        #expect(jobs == Jobs.refresh([], day: "2026-11-10", rules: rules, possible: all, slots: 3))
        #expect(jobs.allSatisfy { $0.done == 0 && $0.finishedOn == nil && $0.drawnOn == "2026-11-10" })
        let days = (1...30).map { Jobs.refresh([], day: String(format: "2026-11-%02d", $0), rules: rules, possible: all, slots: 3).map(\.rule) }
        #expect(Set(days).count > 5, "the jobs change from day to day")
    }

    @Test func onlyJobsThatCanBeDoneAreDrawn() throws {
        let rules = try Repo.jobs()
        for day in (1...30).map({ String(format: "2026-11-%02d", $0) }) {
            let jobs = Jobs.refresh([], day: day, rules: rules, possible: ["looks", "cells"], slots: 3)
            #expect(jobs.count == 2 && Set(jobs.map(\.kind)) == ["looks", "cells"])
        }
        #expect(Jobs.refresh([], day: "2026-11-10", rules: rules, possible: [], slots: 3).isEmpty)
    }

    @Test func aLookCountsAndANewDrainCountsTwice() throws {
        var jobs = [Job(rule: "look_3", text: "Look at three drains", kind: "looks", count: 3, done: 0, drawnOn: "d", finishedOn: nil),
                    Job(rule: "new_drain", text: "Find a drain you have never been to", kind: "new_sites", count: 1, done: 0, drawnOn: "d", finishedOn: nil)]
        #expect(Jobs.record(.look(newSite: false), in: &jobs, day: "d").isEmpty)
        #expect(jobs.map(\.done) == [1, 0])
        let finished = Jobs.record(.look(newSite: true), in: &jobs, day: "d")
        #expect(finished.map(\.rule) == ["new_drain"] && jobs.map(\.done) == [2, 1])
        #expect(Jobs.record(.look(newSite: true), in: &jobs, day: "d").map(\.rule) == ["look_3"])
        #expect(Jobs.record(.look(newSite: true), in: &jobs, day: "d").isEmpty, "a finished job counts no further")
        #expect(jobs.allSatisfy { $0.done == $0.count && $0.finishedOn == "d" })
    }

    @Test func sealsKeepersAndSquaresCountForTheirOwnJobs() {
        var jobs = [Job(rule: "seal", text: "", kind: "seal", count: 1, done: 0, drawnOn: "d", finishedOn: nil),
                    Job(rule: "new_keeper", text: "", kind: "new_keeper", count: 1, done: 0, drawnOn: "d", finishedOn: nil),
                    Job(rule: "squares_20", text: "", kind: "cells", count: 20, done: 0, drawnOn: "d", finishedOn: nil)]
        #expect(Jobs.record(.cells(12), in: &jobs, day: "d").isEmpty && jobs[2].done == 12)
        #expect(Jobs.record(.cells(30), in: &jobs, day: "d").map(\.rule) == ["squares_20"] && jobs[2].done == 20)
        #expect(Jobs.record(.seal, in: &jobs, day: "d").map(\.rule) == ["seal"])
        #expect(Jobs.record(.newKeeper, in: &jobs, day: "d").map(\.rule) == ["new_keeper"])
    }

    @Test func aFinishedJobMakesRoomOnTheNextDayAndAnUnfinishedOneStays() throws {
        let rules = try Repo.jobs()
        var jobs = Jobs.refresh([], day: "2026-11-10", rules: rules, possible: all, slots: 3)
        let open = jobs[1].rule
        jobs[0].done = jobs[0].count
        jobs[0].finishedOn = "2026-11-10"
        #expect(Jobs.refresh(jobs, day: "2026-11-10", rules: rules, possible: all, slots: 3) == jobs, "on the same day the finished job stays to be seen")
        let next = Jobs.refresh(jobs, day: "2026-11-11", rules: rules, possible: all, slots: 3)
        #expect(next.count == 3 && next.contains { $0.rule == open } && next.allSatisfy { $0.finishedOn == nil })
        #expect(Set(next.map(\.kind)).count == 3)
    }

    @Test func anOpenJobCanBeSwappedForAnother() throws {
        let rules = try Repo.jobs()
        let jobs = Jobs.refresh([], day: "2026-11-10", rules: rules, possible: all, slots: 3)
        let swapped = try #require(Jobs.swapped(jobs, at: 0, day: "2026-11-10", rules: rules, possible: all))
        #expect(swapped[0].rule != jobs[0].rule && swapped[1] == jobs[1] && swapped[2] == jobs[2])
        #expect(Set(swapped.map(\.kind)).count == 3)
        var done = jobs
        done[0].finishedOn = "2026-11-10"
        #expect(Jobs.swapped(done, at: 0, day: "2026-11-10", rules: rules, possible: all) == nil)
        #expect(Jobs.swapped(jobs, at: 9, day: "2026-11-10", rules: rules, possible: all) == nil)
    }
}
