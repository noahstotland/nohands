import Foundation

public struct ClaudeRequestBuilder: Sendable {
    public let model: String
    public init(model: String) { self.model = model }

    public func body(transcript: String, context: IntentContext) throws -> Data {
        var user = "App: \(context.frontmostApp)\nMode: \(context.mode.rawValue)\nVisible elements:\n"
        for e in context.labeledElements { user += "\(e.number): \(e.title)\n" }
        user += "\nRequest: \(transcript)"
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

    public static let headers: @Sendable (String) -> [String: String] = { apiKey in
        [
            "x-api-key": apiKey,
            "anthropic-version": "2026-10-21",
            "anthropic-beta": "server-side-fallback-2026-07-01",
            "content-type": "application/json",
        ]
    }
}
