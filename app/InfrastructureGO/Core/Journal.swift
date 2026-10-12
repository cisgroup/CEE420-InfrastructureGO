import Foundation

/// How well a player knows a keeper. Every rung is reached by meeting it a number of times.
nonisolated enum Rung: Int, Sendable, Comparable, CaseIterable {
    case stranger = 0
    case met
    case known
    case friend
    case oldFriend

    static func < (a: Rung, b: Rung) -> Bool { a.rawValue < b.rawValue }

    var name: String {
        switch self {
        case .stranger: "Not met yet"
        case .met: "Met"
        case .known: "Known"
        case .friend: "Friend"
        case .oldFriend: "Old friend"
        }
    }
}

/// A keeper's page in the journal.
nonisolated struct Page: Sendable, Equatable {
    let keeper: String
    let meetings: Int
    let seals: Int
    let rung: Rung
    let nextRung: Rung?
    let nextAt: Int?            // the meetings the next rung needs
    let firstAt: Date?
    let firstSite: String?
}

/// The journal. A page grows with every meeting, so that meeting a keeper again is never a copy to throw away.
/// Met, known, friend and old friend come with the meetings. The seal stands apart and is earned by a mastered
/// catch, and every further mastered catch adds to its tally.
nonisolated enum Journal {
    static func rung(meetings: Int, rungs: [Int]) -> Rung {
        Rung(rawValue: rungs.prefix(4).filter { meetings >= $0 }.count) ?? .stranger
    }

    static func page(of keeper: String, in progress: PlayerProgress, rungs: [Int]) -> Page {
        let mine = progress.meetings.filter { $0.keeper == keeper && ($0.outcome == .caught || $0.outcome == .mastered) }
        let rung = rung(meetings: mine.count, rungs: rungs)
        let next = Rung(rawValue: rung.rawValue + 1)
        let first = mine.min { $0.at < $1.at }
        return Page(keeper: keeper, meetings: mine.count, seals: mine.filter { $0.outcome == .mastered }.count, rung: rung,
                    nextRung: next, nextAt: next.flatMap { rungs.indices.contains($0.rawValue - 1) ? rungs[$0.rawValue - 1] : nil },
                    firstAt: first?.at, firstSite: first?.site)
    }

    /// The one sentence a result leads with, which says what the meeting changed.
    static func line(_ keeper: Keeper, before: Page, after: Page, mastered: Bool) -> String {
        if before.meetings == 0 { return "New in your journal." }
        if mastered && before.seals == 0 { return "That \(keeper.pose.lowercased()) belongs in your journal." }
        if after.rung > before.rung {
            switch after.rung {
            case .known: return "You know its \(keeper.tellWord) now."
            case .friend: return "\(keeper.name) counts you as a friend now."
            case .oldFriend: return "An old friend by now."
            default: break
            }
        }
        if mastered { return "Another \(keeper.pose.lowercased()). \(Words.count(after.seals, "seal", "seals")) now." }
        if let next = after.nextRung, let at = after.nextAt {
            switch next {
            case .known: return "\(after.meetings) of \(at) meetings until you know its \(keeper.tellWord)."
            case .friend: return "\(after.meetings) of \(at) meetings until it is a friend."
            case .oldFriend: return "\(after.meetings) of \(at) meetings until it is an old friend."
            default: break
            }
        }
        return keeper.returning
    }
}
