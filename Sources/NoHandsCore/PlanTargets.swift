import Foundation
import CoreGraphics

/// Picks the element a plan step acts on, from the observed list, by rule only: no word of any site is known here.
public enum PlanTargets {
    /// A link narrower than this is a skip link, a logo or a breadcrumb, not a content item (measured on real lists:
    /// those are 92 to 131 points wide, video cards and search results 340 or more).
    static let minContentWidth: CGFloat = 200
    static let minContentWords = 3
    /// Links in one column with at most this much room between rows beyond their own height form a navigation stack.
    static let stackGap: CGFloat = 16
    static let minStack = 3
    private static let edgeTolerance: CGFloat = 2

    private static func bareRole(_ e: ObservedElement) -> String {
        var r = e.role.lowercased()
        if r.hasPrefix("ax") { r.removeFirst(2) }
        return r
    }

    /// The first element whose title matches `text`; an exact match (after folding) beats a partial one. Menu-bar
    /// items are never plan targets.
    public static func click(text: String, in elements: [ObservedElement]) -> Int? {
        let wanted = PlanText.fold(text)
        guard !wanted.isEmpty else { return nil }
        let candidates = elements.filter { bareRole($0) != "menubaritem" }
        return (candidates.first { PlanText.fold($0.title) == wanted } ?? candidates.first { PlanText.matches(text, in: $0.title) })?.number
    }

    /// The first content link, after the element titled `after` when given. A content link is a link that is not
    /// `offscreen`, has at least three words and is wide enough, and is not part of a navigation stack: three or more
    /// links with the same left edge and width, each row no more than its own height plus 16 points below the last.
    /// Video cards, search results and file rows are told apart from sidebars by that spacing. Without a frame for
    /// the links the stack cannot be told, so there is no pick.
    public static func firstItem(after: String?, in elements: [ObservedElement], frames: [Int: CGRect]) -> Int? {
        var list = elements
        if let after {
            guard let n = click(text: after, in: elements), let i = elements.firstIndex(where: { $0.number == n }) else { return nil }
            list = Array(elements[(i + 1)...])
        }
        let links = elements.filter { bareRole($0) == "link" && frames[$0.number] != nil }
        let inStack = stackMembers(links.map { ($0.number, frames[$0.number]!) })
        return list.first { e in
            guard bareRole(e) == "link", !e.states.contains("offscreen"), let f = frames[e.number], !inStack.contains(e.number),
                  f.width >= minContentWidth else { return false }
            return e.title.split(whereSeparator: { $0.isWhitespace }).count >= minContentWords
        }?.number
    }

    private static func stackMembers(_ links: [(number: Int, frame: CGRect)]) -> Set<Int> {
        var members = Set<Int>()
        var columns: [[(number: Int, frame: CGRect)]] = []
        for l in links.sorted(by: { $0.frame.minY < $1.frame.minY }) {
            if let i = columns.firstIndex(where: { sameColumn($0[0].frame, l.frame) }) { columns[i].append(l) } else { columns.append([l]) }
        }
        for column in columns {
            var chain: [Int] = []
            var previous: CGRect?
            for l in column {
                if let p = previous, l.frame.minY - p.minY <= p.height + stackGap { chain.append(l.number) }
                else { if chain.count >= minStack { members.formUnion(chain) }; chain = [l.number] }
                previous = l.frame
            }
            if chain.count >= minStack { members.formUnion(chain) }
        }
        return members
    }

    private static func sameColumn(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= edgeTolerance && abs(a.width - b.width) <= edgeTolerance
    }
}
