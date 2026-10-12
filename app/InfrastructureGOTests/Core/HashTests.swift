import Foundation
import Testing
@testable import InfrastructureGO

@Suite("Drawing lots")
struct HashTests {
    @Test("the number is the MD5 any tool computes")
    func knownDigest() {
        // The digest was printed by the md5 command of macOS for the same text.
        #expect(Hash.number("in0742|2026-11-10|3|base") == 0x4d3b_b34d)
        #expect(Hash.index("in0742|2026-11-10|3|base", count: 2) == 1)
    }

    @Test func theSameKeyGivesTheSameLot() {
        #expect(Hash.index("a|b", count: 7) == Hash.index("a|b", count: 7))
        #expect(Hash.index("a|b", count: 0) == 0)
        #expect(Set((0..<200).map { Hash.index("k\($0)", count: 5) }) == [0, 1, 2, 3, 4])
    }

    @Test func aUnitLiesFromZeroUpToOne() {
        let drawn = (0..<500).map { Hash.unit("unit \($0)") }
        #expect(drawn.allSatisfy { $0 >= 0 && $0 < 1 })
        let mean = drawn.reduce(0, +) / 500
        #expect(mean > 0.42 && mean < 0.58)
    }
}
