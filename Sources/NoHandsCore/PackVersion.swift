import Foundation

/// A registry pack version: 1 to 4 dot-separated numbers of up to 6 digits, compared numerically with missing
/// parts as 0 (`1.2` equals `1.2.0` and is below `1.10`). Anything else has no value, so it is never compared.
public struct PackVersion: Comparable, Sendable {
    private let parts: [Int]

    public init?(_ text: String) {
        let pieces = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(pieces.count),
              pieces.allSatisfy({ (1...6).contains($0.count) && $0.allSatisfy { $0.isASCII && $0.isNumber } }) else { return nil }
        parts = pieces.compactMap { Int($0) } + Array(repeating: 0, count: 4 - pieces.count)
    }

    public static func < (a: PackVersion, b: PackVersion) -> Bool { a.parts.lexicographicallyPrecedes(b.parts) }
}
