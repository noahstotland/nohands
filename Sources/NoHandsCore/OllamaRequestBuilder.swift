import Foundation

public struct OllamaRequestBuilder: Sendable {
    public static let ollamaKeepAlive = "30m"

    public let model: String
    public init(model: String) { self.model = model }

    public func body(transcript: String, context: IntentContext) throws -> Data {
        var messages: [[String: String]] = [["role": "system", "content": IntentSchema.systemPrompt]]
        for t in IntentExamples.turns {
            messages.append(["role": "user", "content": t.user])
            messages.append(["role": "assistant", "content": t.assistant])
        }
        messages.append(["role": "user", "content": ClaudeRequestBuilder.userMessage(transcript: transcript, context: context)])
        let obj: [String: Any] = [
            "model": model,
            "stream": false,
            "format": IntentSchema.actionsJSONSchema,
            "options": ["temperature": 0] as [String: Any],
            "keep_alive": Self.ollamaKeepAlive,
            "messages": messages,
        ]
        return try JSONSerialization.data(withJSONObject: obj)
    }
}

public enum IntentExamples {
    private static func msg(_ app: String, elements: [(Int, String)] = [], overlay: String = "none", request: String) -> String {
        ClaudeRequestBuilder.userMessage(
            transcript: request,
            context: IntentContext(frontmostApp: app, mode: .command,
                                   labeledElements: elements.map { (number: $0.0, title: $0.1) }, overlay: overlay))
    }

    public static let turns: [(user: String, assistant: String)] = [
        (Self.msg("Finder", request: "open chrome and go to youtube"),
         #"{"actions":[{"kind":"open_app","app_name":"Google Chrome"},{"kind":"press_key","key":"l","modifiers":["command"]},{"kind":"type_text","text":"youtube.com"},{"kind":"press_key","key":"return"}]}"#),
        (Self.msg("Safari", request: "minimize google chrome"),
         #"{"actions":[{"kind":"open_app","app_name":"Google Chrome"},{"kind":"press_key","key":"m","modifiers":["command"]}]}"#),
        (Self.msg("Safari", elements: [(1, "Back"), (2, "Forward"), (3, "Reload")], overlay: "labels", request: "click the back button"),
         #"{"actions":[{"kind":"click","target_kind":"label","target_number":1}]}"#),
        (Self.msg("Notes", request: "scroll down a lot"),
         #"{"actions":[{"kind":"scroll","direction":"down","amount":15}]}"#),
        (Self.msg("Mail", request: "write hello there and press enter"),
         #"{"actions":[{"kind":"type_text","text":"hello there"},{"kind":"press_key","key":"return"}]}"#),
        (Self.msg("Finder", request: "what's the weather"),
         #"{"actions":[{"kind":"ignore"}]}"#),
    ]
}
