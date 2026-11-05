import Foundation

public struct ClaudeRequestBuilder: Sendable {
    public let model: String
    /// `output_config.effort`: how much the model thinks before answering. Default "medium" so garbled
    /// transcripts get reasoned about rather than pattern-matched.
    public let effort: String
    public init(model: String, effort: String = "medium") { self.model = model; self.effort = effort }

    public func body(transcript: String, context: IntentContext) throws -> Data {
        try body(request: StepRequest(oneShot: transcript, context: context))
    }

    public func body(request: StepRequest) throws -> Data {
        let user = Self.userMessage(request: request)
        let obj: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "fallbacks": "default",
            "system": IntentSchema.systemPrompt(for: request.observation.harness),
            "output_config": [
                "effort": effort,
                "format": ["type": "json_schema", "schema": IntentSchema.actionsJSONSchema] as [String: Any],
            ] as [String: Any],
            "messages": [["role": "user", "content": user]],
        ]
        return try JSONSerialization.data(withJSONObject: obj)
    }

    public static func userMessage(transcript: String, context: IntentContext) -> String {
        userMessage(request: StepRequest(oneShot: transcript, context: context))
    }

    public static func userMessage(request r: StepRequest) -> String {
        let o = r.observation
        let goal = sanitize(r.goal, limit: 300)
        var s = "Goal: \(goal)\nStep: \(r.step) of \(r.maxSteps)\n"
        if !r.history.isEmpty {
            s += "History:\n"
            for (i, h) in r.history.enumerated() {
                let outcome = h.failure.map { "FAILED: \(sanitize($0))" } ?? "ok"
                s += "  \(i + 1). \(sanitize(h.intent)) -> \(ActionSummary.kinds(h.actions)) (\(outcome))\n"
            }
        }
        s += "App: \(sanitize(o.app))   Window: \(sanitize(o.windowTitle).nonEmpty ?? "-")   URL: \(o.url.map { sanitize($0) } ?? "-")\n"
        s += "Mode: \(o.mode.rawValue)   Overlay: \(sanitize(o.overlay))   Harness: \(o.harness.rawValue)\n"
        if let surface = o.surface { s += "Surface: \(sanitize(surface))\n" }
        if !o.windows.isEmpty { s += "Windows: " + o.windows.map { "\"\(sanitize($0))\"" }.joined(separator: ", ") + "\n" }
        s += "Visible elements:\n"
        for e in o.elements {
            var role = sanitize(e.role).lowercased()
            if role.hasPrefix("ax") { role.removeFirst(2) }
            s += "  \(e.number) [\(role)] \(sanitize(e.title))"
            let states = shownStates.filter { e.states.contains($0) }
            if !states.isEmpty { s += " (" + states.joined(separator: ", ") + ")" }
            if let v = e.value, !v.isEmpty { s += " = \"\(sanitize(v, limit: valueLimit))\"" }
            s += "\n"
        }
        if !o.readings.isEmpty {
            s += "Read:\n"
            for r in o.readings { s += "  \(sanitize(r, limit: readingLimit))\n" }
        }
        s += "\nRequest: \(r.step == 1 ? goal : "Continue toward the goal.")"
        return s
    }

    /// agent-desktop state tokens worth the model's attention, in display order.
    static let shownStates = ["checked", "selected", "expanded", "collapsed", "disabled", "focused", "offscreen"]
    static let valueLimit = 60
    static let readingLimit = 300

    static func sanitize(_ s: String, limit: Int = 80) -> String {
        let mapped = String(String.UnicodeScalarView(s.unicodeScalars.map {
            CharacterSet.controlCharacters.contains($0) || CharacterSet.newlines.contains($0) ? " " : $0
        }))
        let collapsed = mapped.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return String(collapsed.prefix(limit))
    }

    public static let headers: @Sendable (String) -> [String: String] = { apiKey in
        [
            "x-api-key": apiKey,
            "anthropic-version": "2026-10-21",
            "anthropic-beta": "server-side-fallback-2026-07-01",
            "content-type": "application/json",
        ]
    }
}

private extension String { var nonEmpty: String? { isEmpty ? nil : self } }
