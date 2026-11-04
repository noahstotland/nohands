import Foundation

/// One evaluation case. `accept` lists acceptable answers; each is decoded from a wire-format `{"actions":[...]}` object.
public struct EvalCase: Decodable, Sendable {
    public var say: String
    public var app: String
    public var elements: [String]
    public var overlay: String
    public var accept: [[Action]]

    private enum CodingKeys: String, CodingKey { case say, app, elements, overlay, accept }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        say = try c.decode(String.self, forKey: .say)
        app = try c.decodeIfPresent(String.self, forKey: .app) ?? "Finder"
        elements = try c.decodeIfPresent([String].self, forKey: .elements) ?? []
        overlay = try c.decodeIfPresent(String.self, forKey: .overlay) ?? "none"
        var list = try c.nestedUnkeyedContainer(forKey: .accept)
        var out: [[Action]] = []
        while !list.isAtEnd {
            let raw = try list.decode(AnyJSON.self)
            let data = try JSONSerialization.data(withJSONObject: raw.value)
            guard let text = String(data: data, encoding: .utf8) else {
                throw DecodingError.dataCorruptedError(in: list, debugDescription: "accept entry is not UTF-8")
            }
            out.append(try IntentDecoder.actions(fromPayloadText: text))
        }
        accept = out
    }
}

private struct AnyJSON: Decodable {
    let value: Any
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { value = NSNull() }
        else if let b = try? c.decode(Bool.self) { value = b }
        else if let i = try? c.decode(Int.self) { value = i }
        else if let d = try? c.decode(Double.self) { value = d }
        else if let s = try? c.decode(String.self) { value = s }
        else if let a = try? c.decode([AnyJSON].self) { value = a.map(\.value) }
        else { value = try c.decode([String: AnyJSON].self).mapValues(\.value) }
    }
}

public enum IntentEval {
    public static func matches(_ got: [Action], anyOf: [[Action]]) -> Bool {
        anyOf.contains { want in
            want.count == got.count && zip(got, want).allSatisfy { equivalent($0, $1) }
        }
    }

    public static func context(for c: EvalCase) -> IntentContext {
        IntentContext(frontmostApp: c.app, mode: .command,
                      labeledElements: c.elements.enumerated().map { (number: $0.offset + 1, title: $0.element) },
                      overlay: c.overlay)
    }

    private static func equivalent(_ a: Action, _ b: Action) -> Bool {
        switch (a, b) {
        case (.typeText(let x), .typeText(let y)): return normalizeText(x) == normalizeText(y)
        case (.openApp(let x), .openApp(let y)): return normalizeApp(x) == normalizeApp(y)
        default: return a == b
        }
    }

    private static func normalizeText(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for p in ["https://", "http://", "www."] where t.hasPrefix(p) { t.removeFirst(p.count) }
        if t.hasSuffix("/") { t.removeLast() }
        return t
    }

    private static func normalizeApp(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return t == "chrome" ? "google chrome" : t
    }
}
