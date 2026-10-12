import Foundation

/// A small job of the crew as jobs.json states it.
nonisolated struct JobRule: Sendable, Decodable, Equatable, Identifiable {
    let id: String
    let text: String
    let kind: String        // looks, new_sites, new_keeper, seal or cells
    let count: Int
}

nonisolated struct JobFile: Sendable, Decodable {
    let version: Int
    let jobs: [JobRule]

    init(json: Data) throws {
        self = try GameData.decoder.decode(JobFile.self, from: json)
    }
}

/// A job a player has open or has finished.
nonisolated struct Job: Sendable, Codable, Equatable, Identifiable {
    let rule: String
    let text: String
    let kind: String
    let count: Int
    var done: Int
    let drawnOn: String
    var finishedOn: String?
    var id: String { rule }
    var isFinished: Bool { finishedOn != nil }
}

/// Something a player did that a job may count.
nonisolated enum JobEvent: Sendable, Equatable {
    case look(newSite: Bool)
    case newKeeper
    case seal
    case cells(Int)
}

/// The jobs of a player. A few are open at a time. A finished job stays on the list until the next day and then
/// makes room, an unfinished job stays as long as it takes, and nothing is lost by not playing.
nonisolated enum Jobs {
    /// Clear out the jobs finished on an earlier day and fill the free places. Only kinds named as possible are
    /// drawn, so that no job asks for something the player cannot do today.
    static func refresh(_ jobs: [Job], day: String, rules: [JobRule], possible: Set<String>, slots: Int) -> [Job] {
        var kept = jobs.filter { $0.finishedOn == nil || $0.finishedOn == day }
        var round = 0
        while kept.count < slots {
            let open = Set(kept.map(\.kind))
            let having = Set(kept.map(\.rule))
            // One job of a kind at a time, so that the three are three different things to do.
            let choices = rules.filter { possible.contains($0.kind) && !open.contains($0.kind) && !having.contains($0.id) }
            guard !choices.isEmpty else { break }
            let pick = choices[Hash.index("\(day)|job|\(kept.count)|\(round)", count: choices.count)]
            kept.append(Job(rule: pick.id, text: pick.text, kind: pick.kind, count: pick.count, done: 0, drawnOn: day, finishedOn: nil))
            round += 1
        }
        return kept
    }

    /// Count something the player did. Returns the jobs it finished.
    @discardableResult
    static func record(_ event: JobEvent, in jobs: inout [Job], day: String) -> [Job] {
        var finished: [Job] = []
        for k in jobs.indices where jobs[k].finishedOn == nil {
            let step: Int
            switch (event, jobs[k].kind) {
            case (.look, "looks"): step = 1
            case (.look(let newSite), "new_sites"): step = newSite ? 1 : 0
            case (.newKeeper, "new_keeper"): step = 1
            case (.seal, "seal"): step = 1
            case (.cells(let count), "cells"): step = count
            default: step = 0
            }
            guard step > 0 else { continue }
            jobs[k].done = min(jobs[k].count, jobs[k].done + step)
            if jobs[k].done >= jobs[k].count {
                jobs[k].finishedOn = day
                finished.append(jobs[k])
            }
        }
        return finished
    }

    /// Put another job in the place of an open one. Returns nil when no other job can be drawn.
    static func swapped(_ jobs: [Job], at index: Int, day: String, rules: [JobRule], possible: Set<String>) -> [Job]? {
        guard jobs.indices.contains(index), jobs[index].finishedOn == nil else { return nil }
        let others = Set(jobs.enumerated().filter { $0.offset != index }.map(\.element.kind))
        let choices = rules.filter { possible.contains($0.kind) && !others.contains($0.kind) && $0.id != jobs[index].rule }
        guard !choices.isEmpty else { return nil }
        let pick = choices[Hash.index("\(day)|swap|\(jobs[index].rule)", count: choices.count)]
        var changed = jobs
        changed[index] = Job(rule: pick.id, text: pick.text, kind: pick.kind, count: pick.count, done: 0, drawnOn: day, finishedOn: nil)
        return changed
    }
}
