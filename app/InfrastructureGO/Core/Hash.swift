import CryptoKit
import Foundation

/// The one way the game draws lots. Who lives at a drain, which job is offered and how a keeper behaves all follow
/// from a text and nothing else, so that every phone and one day the server come to the same answer.
nonisolated enum Hash {
    /// The first four bytes of the MD5 of the key as a big endian number. MD5 is used because Swift, Python and
    /// Postgres all compute it without anything added. Nothing here is a secret.
    static func number(_ key: String) -> UInt32 {
        Array(Insecure.MD5.hash(data: Data(key.utf8)).prefix(4)).reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
    }

    /// A place in a list of a given length, the same for the same key.
    static func index(_ key: String, count: Int) -> Int {
        count > 0 ? Int(number(key) % UInt32(count)) : 0
    }

    /// A number from 0 up to but not reaching 1, the same for the same key.
    static func unit(_ key: String) -> Double {
        Double(number(key)) / 4_294_967_296.0
    }
}
