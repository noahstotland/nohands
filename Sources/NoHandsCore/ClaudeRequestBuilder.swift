import Foundation

public struct ClaudeRequestBuilder: Sendable {
    public let model: String
    public init(model: String) { self.model = model }

    public func body(transcript: String, context: IntentContext) throws -> Data {
        let user = Self.userMessage(transcript: transcript, context: context)
        let obj: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "fallbacks": "default",
            "system": IntentSchema.systemPrompt,
            "output_config": [
                "effort": "low",
                "format": ["type": "json_schema", "schema": IntentSchema.actionsJSONSchema] as [String: Any],
            ] as [String: Any],
            "messages": [["role": "user", "content": user]],
        ]
        return try JSONSerialization.data(withJSONObject: obj)
    }

    public static func userMessage(transcript: String, context: IntentContext) -> String {
        var user = "App: \(Self.sanitize(context.frontmostApp))\nMode: \(context.mode.rawValue)\nOverlay: \(Self.sanitize(context.overlay))\nVisible elements:\n"
        for e in context.labeledElements { user += "\(e.number): \(Self.sanitize(e.title))\n" }
        user += "\nRequest: \(transcript)"
        return user
    }

    static func sanitize(_ s: String) -> String {
        let mapped = String(String.UnicodeScalarView(s.unicodeScalars.map {
            CharacterSet.controlCharacters.contains($0) || CharacterSet.newlines.contains($0) ? " " : $0
        }))
        let collapsed = mapped.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return String(collapsed.prefix(80))
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
