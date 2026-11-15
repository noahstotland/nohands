import Foundation

/// A position spoken as a target name ("first video", "the 3rd link", "last result"), read from a `target_name`
/// the model should have sent as a label number. Resolved over the element list the model was shown.
public struct OrdinalTarget: Equatable, Sendable {
    public enum Position: Equatable, Sendable { case nth(Int), last }
    public let position: Position
    /// Roles the noun narrows to (lowercased, no AX prefix). nil means page results: long-titled links.
    let roles: Set<String>?

    private static let words = ["first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth"]
    private static let roleNouns: [String: Set<String>] = [
        "link": ["link"], "button": ["button"], "checkbox": ["checkbox"], "tab": ["tab"],
        "field": ["textfield", "textarea", "searchfield", "combobox"],
        "text field": ["textfield", "textarea", "searchfield", "combobox"],
        "box": ["textfield", "textarea", "searchfield", "combobox"],
        "menu item": ["menuitem"],
    ]
    private static let minResultTitleWords = 3

    public static func parse(_ name: String) -> OrdinalTarget? {
        var tokens = name.lowercased().split(whereSeparator: { $0.isWhitespace }).map {
            $0.trimmingCharacters(in: .punctuationCharacters)
        }.filter { !$0.isEmpty }
        if tokens.first == "the" { tokens.removeFirst() }
        guard let head = tokens.first, let position = position(of: head) else { return nil }
        let noun = Array(tokens.dropFirst())
        guard noun.count <= 2 else { return nil }
        let phrase = noun.enumerated().map { $0.offset == noun.count - 1 ? singular($0.element) : $0.element }
            .joined(separator: " ")
        return OrdinalTarget(position: position, roles: roleNouns[phrase])
    }

    /// The label number of the match in `labels` (in label order), or nil when there are too few candidates.
    public func label(in labels: [Int: UIElementInfo]) -> Int? {
        let ordered = labels.keys.sorted().compactMap { n in labels[n].map { (n, $0) } }
        var candidates: [(Int, UIElementInfo)] = []
        if let roles {
            candidates = ordered.filter { roles.contains(Self.role($0.1)) }
        } else {
            var seen: Set<String> = []
            for (n, e) in ordered where Self.role(e) == "link" {
                let title = e.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard title.split(whereSeparator: { $0.isWhitespace }).count >= Self.minResultTitleWords else { continue }
                guard seen.insert(title).inserted else { continue }   // a thumbnail and its title link are one result
                candidates.append((n, e))
            }
        }
        switch position {
        case .last: return candidates.last?.0
        case .nth(let n): return n <= candidates.count ? candidates[n - 1].0 : nil
        }
    }

    private static func role(_ e: UIElementInfo) -> String {
        var r = e.role.lowercased()
        if r.hasPrefix("ax") { r.removeFirst(2) }
        return r
    }

    private static func singular(_ w: String) -> String {
        if roleNouns[w] != nil || !w.hasSuffix("s") { return w }
        if w.hasSuffix("es"), roleNouns[String(w.dropLast(2))] != nil { return String(w.dropLast(2)) }
        return String(w.dropLast())
    }

    private static func position(of w: String) -> Position? {
        if w == "last" { return .last }
        if let i = words.firstIndex(of: w) { return .nth(i + 1) }
        for suffix in ["st", "nd", "rd", "th"] where w.hasSuffix(suffix) {
            if let n = Int(w.dropLast(2)), n >= 1 { return .nth(n) }
        }
        return nil
    }
}
