import Foundation

public struct OllamaRequestBuilder: Sendable {
    public static let ollamaKeepAlive = "30m"

    public let model: String
    public init(model: String) { self.model = model }

    /// Serialized with OrderedJSON so the `format` schema keeps `intent` before `actions`: Ollama's constrained
    /// decoder emits properties in schema order, which is what makes the model restate the request first.
    public func body(transcript: String, context: IntentContext) throws -> Data {
        var messages: [OrderedJSON] = [Self.message("system", IntentSchema.systemPrompt)]
        for t in IntentExamples.turns {
            messages.append(Self.message("user", t.user))
            messages.append(Self.message("assistant", t.assistant))
        }
        messages.append(Self.message("user", ClaudeRequestBuilder.userMessage(transcript: transcript, context: context)))
        let obj: OrderedJSON = .object([
            ("model", .string(model)),
            ("stream", .bool(false)),
            ("format", IntentSchema.orderedSchema),
            ("options", .object([("temperature", .int(0))])),
            ("keep_alive", .string(Self.ollamaKeepAlive)),
            ("messages", .array(messages)),
        ])
        return obj.data
    }

    private static func message(_ role: String, _ content: String) -> OrderedJSON {
        .object([("role", .string(role)), ("content", .string(content))])
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
         #"{"intent":"Open Google Chrome and navigate to youtube.com.","actions":[{"kind":"open_app","app_name":"Google Chrome"},{"kind":"press_key","key":"l","modifiers":["command"]},{"kind":"type_text","text":"youtube.com"},{"kind":"press_key","key":"return"}]}"#),
        (Self.msg("Safari", request: "minimize google chrome"),
         #"{"intent":"Minimize the Google Chrome window.","actions":[{"kind":"open_app","app_name":"Google Chrome"},{"kind":"press_key","key":"m","modifiers":["command"]}]}"#),
        (Self.msg("Safari", elements: [(1, "Back"), (2, "Forward"), (3, "Reload")], overlay: "labels", request: "click the back button"),
         #"{"intent":"Click the Back button, which is visible element 1.","actions":[{"kind":"click","target_kind":"label","target_number":1}]}"#),
        (Self.msg("Notes", request: "scroll down a lot"),
         #"{"intent":"Scroll down by a large amount.","actions":[{"kind":"scroll","direction":"down","amount":15}]}"#),
        (Self.msg("Mail", request: "write hello there and press enter"),
         #"{"intent":"Type the text \"hello there\" and then press Return.","actions":[{"kind":"type_text","text":"hello there"},{"kind":"press_key","key":"return"}]}"#),
        (Self.msg("Safari", elements: [(1, "Back"), (4, "Sign in"), (9, "Search")], overlay: "labels", request: "um click the uh no scroll scroll up a bit"),
         #"{"intent":"The user started to say click but corrected themselves: scroll up a little.","actions":[{"kind":"scroll","direction":"up","amount":3}]}"#),
        (Self.msg("Finder", request: "what's the weather"),
         #"{"intent":"The user asked a question about the weather; this is not a computer action.","actions":[{"kind":"ignore"}]}"#),
    ]
}
