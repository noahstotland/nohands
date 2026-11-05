import Foundation
import CoreGraphics

public struct UIElementInfo: Equatable, Sendable {
    public var id: Int
    public var frame: CGRect
    public var title: String
    public var role: String
    /// agent-desktop's qualified ref (`@s8f3k2p9:e5`) when the element came from a harness snapshot.
    public var ref: String?
    /// Current value (a field's text, a checkbox's 1/0) when the snapshot reported one.
    public var value: String?
    /// agent-desktop state tokens: checked, selected, disabled, expanded, collapsed, focused, offscreen, …
    public var states: [String]

    public init(id: Int, frame: CGRect, title: String, role: String,
                ref: String? = nil, value: String? = nil, states: [String] = []) {
        self.id = id
        self.frame = frame
        self.title = title
        self.role = role
        self.ref = ref
        self.value = value
        self.states = states
    }
}

public enum LabelAssigner {
    static let rowTolerance: CGFloat = 8

    /// Dedupes by frame (first wins), sorts top-to-bottom then left-to-right
    /// (row tolerance 8 pt), caps at `limit`, numbers from 1.
    public static func assign(_ elements: [UIElementInfo], limit: Int = 200) -> [Int: UIElementInfo] {
        var seen: [CGRect] = []
        var unique: [UIElementInfo] = []
        for e in elements where !seen.contains(e.frame) {
            seen.append(e.frame)
            unique.append(e)
        }
        // Bucket into rows: sort by y, start a new row when y is >= tolerance
        // away from the row's first element. Then sort each row by x.
        let byY = unique.enumerated().sorted {
            $0.element.frame.minY != $1.element.frame.minY
                ? $0.element.frame.minY < $1.element.frame.minY
                : $0.offset < $1.offset
        }.map(\.element)
        var rowsList: [[UIElementInfo]] = []
        var anchorY: CGFloat = 0
        for e in byY {
            if let _ = rowsList.last, e.frame.minY - anchorY < rowTolerance {
                rowsList[rowsList.count - 1].append(e)
            } else {
                rowsList.append([e])
                anchorY = e.frame.minY
            }
        }
        var ordered: [UIElementInfo] = []
        for row in rowsList {
            let sorted = row.enumerated().sorted {
                $0.element.frame.minX != $1.element.frame.minX
                    ? $0.element.frame.minX < $1.element.frame.minX
                    : $0.offset < $1.offset
            }.map(\.element)
            ordered.append(contentsOf: sorted)
        }
        var result: [Int: UIElementInfo] = [:]
        for (i, e) in ordered.prefix(max(0, limit)).enumerated() {
            result[i + 1] = e
        }
        return result
    }

    /// Exact (case-insensitive) title match first, then prefix, then contains; nil if none.
    public static func find(named name: String, in elements: [UIElementInfo]) -> UIElementInfo? {
        let q = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return nil }
        let titled = elements.map { ($0, $0.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) }
        if let m = titled.first(where: { $0.1 == q }) { return m.0 }
        if let m = titled.first(where: { $0.1.hasPrefix(q) }) { return m.0 }
        if let m = titled.first(where: { $0.1.contains(q) }) { return m.0 }
        return nil
    }
}
