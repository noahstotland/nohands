import Foundation

/// One acceptable answer to a case: the actions, and optionally the step status it must have. An entry with a status
/// matches only a step with that status; for `ask` the actions are not compared (the model writes none).
public struct EvalAnswer: Sendable {
    public var actions: [Action]
    public var status: StepStatus?
    public init(actions: [Action], status: StepStatus? = nil) { self.actions = actions; self.status = status }
}

/// One evaluation case. `accept` lists acceptable answers; each is decoded from a wire-format
/// `{"actions":[...],"status":"..."}` object (the status is optional).
public struct EvalCase: Decodable, Sendable {
    public var say: String
    public var app: String
    public var elements: [String]
    public var overlay: String
    public var accept: [EvalAnswer]

    private enum CodingKeys: String, CodingKey { case say, app, elements, overlay, accept }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        say = try c.decode(String.self, forKey: .say)
        app = try c.decodeIfPresent(String.self, forKey: .app) ?? "Finder"
        elements = try c.decodeIfPresent([String].self, forKey: .elements) ?? []
        overlay = try c.decodeIfPresent(String.self, forKey: .overlay) ?? "none"
        var list = try c.nestedUnkeyedContainer(forKey: .accept)
        var out: [EvalAnswer] = []
        while !list.isAtEnd {
            let raw = try list.decode(AnyJSON.self)
            let data = try JSONSerialization.data(withJSONObject: raw.value)
            guard let text = String(data: data, encoding: .utf8) else {
                throw DecodingError.dataCorruptedError(in: list, debugDescription: "accept entry is not UTF-8")
            }
            let status = (raw.value as? [String: Any])?["status"] as? String
            guard status == nil || StepStatus(rawValue: status!) != nil else {
                throw DecodingError.dataCorruptedError(in: list, debugDescription: "accept entry has an unknown status")
            }
            out.append(EvalAnswer(actions: try IntentDecoder.actions(fromPayloadText: text), status: status.flatMap(StepStatus.init(rawValue:))))
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
    /// `status` is the step's. An `ask` entry matches an `ask` step whatever its actions; any other entry with a
    /// status also needs the actions to match; an entry without a status matches on actions alone.
    public static func matches(_ got: [Action], status: StepStatus, anyOf: [EvalAnswer]) -> Bool {
        anyOf.contains { want in
            if let wanted = want.status {
                guard wanted == status else { return false }
                if wanted == .ask { return true }
            }
            return matches(got, anyOf: [want.actions])
        }
    }

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
        case (.openURL(let u, let x), .openURL(let v, let y)):
            return normalizeText(u.absoluteString) == normalizeText(v.absoluteString) && x.map(normalizeApp) == y.map(normalizeApp)
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

/// Pass rate and latency of one eval run.
public struct EvalSummary: Equatable, Sendable {
    public var passed: Int
    public var total: Int
    public var p50Ms: Int
    public var p95Ms: Int

    /// `dropFirst` leaves the first N calls out of the latency figures only (a cold model load); pass counts use every call.
    public init(results: [(passed: Bool, ms: Int)], dropFirst: Int = 0) {
        total = results.count
        passed = results.filter(\.passed).count
        let sorted = results.dropFirst(min(max(dropFirst, 0), max(results.count - 1, 0))).map(\.ms).sorted()
        p50Ms = Self.nearestRank(sorted, 0.50)
        p95Ms = Self.nearestRank(sorted, 0.95)
    }

    /// The `ceil(p * n)`-th smallest value; 0 when empty.
    static func nearestRank(_ sorted: [Int], _ p: Double) -> Int {
        guard !sorted.isEmpty else { return 0 }
        return sorted[min(max(Int((p * Double(sorted.count)).rounded(.up)), 1), sorted.count) - 1]
    }

    public var line: String {
        "pass=\(passed)/\(total) (\(total == 0 ? 0 : passed * 100 / total)%) p50=\(p50Ms)ms p95=\(p95Ms)ms"
    }
}
