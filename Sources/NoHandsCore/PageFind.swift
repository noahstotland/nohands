import Foundation
import CoreGraphics

/// Find on page: matching the spoken words against the texts of a page's elements, and putting the match first in the
/// next observation. Pure logic; the accessibility walk that feeds it lives in `NoHandsMac`.
public enum PageFind {
    /// The most characters of words a find accepts.
    public static let maxWords = 200

    /// Trimmed, lower-cased, without a leading "the" or trailing `.,!?`. Empty when nothing is left.
    public static func normalize(_ words: String) -> String {
        var s = words.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while let last = s.last, ".,!?".contains(last) { s.removeLast() }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if s == "the" { return "" }
        if s.hasPrefix("the ") { s.removeFirst(4) }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The failure line for a find that matched nothing. It does not start with `no element`, so the vision trigger
    /// stays off: a missing text is not an invisible element.
    public static func failure(_ words: String) -> String {
        "no match for \(words.trimmingCharacters(in: .whitespacesAndNewlines)) on this page"
    }

    /// Takes the texts of candidates in walk order. Tiers, all case-insensitive on the trimmed text: exact, then
    /// prefix, then contains; within a tier the first one offered wins. An empty query matches nothing.
    public struct Matcher: Sendable {
        private let query: String
        private var exact: UIElementInfo?
        private var prefix: UIElementInfo?
        private var contains: UIElementInfo?

        public init(words: String) { query = PageFind.normalize(words) }

        /// The winner so far.
        public var best: UIElementInfo? { exact ?? prefix ?? contains }

        private enum Tier { case exact, prefix, contains }

        private func tier(_ text: String) -> Tier? {
            guard !query.isEmpty else { return nil }
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return t == query ? .exact : t.hasPrefix(query) ? .prefix : t.contains(query) ? .contains : nil
        }

        /// Whether offering `text` would change `best`. The walk asks before it reads the element's frame, so only
        /// a candidate that can win costs that read.
        public func wouldTake(_ text: String) -> Bool {
            switch tier(text) {
            case .exact: exact == nil
            case .prefix: prefix == nil
            case .contains: contains == nil
            case nil: false
            }
        }

        /// True on an exact match, so the walk can stop.
        @discardableResult
        public mutating func offer(_ text: String, element: UIElementInfo) -> Bool {
            switch tier(text) {
            case .exact: if exact == nil { exact = element }; return true
            case .prefix: if prefix == nil { prefix = element }
            case .contains: if contains == nil { contains = element }
            case nil: break
            }
            return false
        }
    }

    /// `labels` with `found` as number 1 and the rest shifted down in order. `found` is looked up in the list (same
    /// ref, else same title, case-insensitive, preferring one whose frame meets its frame); when it is not there it is
    /// inserted first and the last element drops off if that passes `limit`.
    public static func pinFirst(_ labels: [Int: UIElementInfo], found: UIElementInfo, limit: Int) -> [Int: UIElementInfo] {
        var ordered = labels.keys.sorted().compactMap { labels[$0] }
        var at: Int?
        if let ref = found.ref { at = ordered.firstIndex { $0.ref == ref } }
        if at == nil {
            let title = found.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !title.isEmpty {
                let same = ordered.indices.filter {
                    ordered[$0].title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == title
                }
                at = same.first { ordered[$0].frame.intersects(found.frame) } ?? same.first
            }
        }
        // The list's own element wins over `found`: it carries the harness ref and state.
        let pinned = at.map { ordered.remove(at: $0) } ?? found
        ordered.insert(pinned, at: 0)
        return Dictionary(uniqueKeysWithValues: ordered.prefix(max(1, limit)).enumerated().map { ($0.offset + 1, $0.element) })
    }
}
