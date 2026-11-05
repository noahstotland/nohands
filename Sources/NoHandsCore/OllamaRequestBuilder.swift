import Foundation

public struct OllamaRequestBuilder: Sendable {
    public static let ollamaKeepAlive = "30m"
    /// Ollama's default context is 4096 tokens; a 120-element observation plus history is already ~4k, and an
    /// overflow silently drops the system prompt. The model (qwen2.5) is trained to 32k.
    public static let numCtx = 8192

    public let model: String
    public init(model: String) { self.model = model }

    /// Serialized with OrderedJSON so the `format` schema keeps `intent` before `actions`: Ollama's constrained
    /// decoder emits properties in schema order, which is what makes the model restate the request first.
    public func body(transcript: String, context: IntentContext) throws -> Data {
        try body(request: StepRequest(oneShot: transcript, context: context))
    }

    public func body(request: StepRequest) throws -> Data {
        let obj: OrderedJSON = .object([
            ("model", .string(model)),
            ("stream", .bool(false)),
            ("format", IntentSchema.orderedSchema),
            ("options", .object([("temperature", .int(0)), ("num_ctx", .int(Self.numCtx))])),
            ("keep_alive", .string(Self.ollamaKeepAlive)),
            ("messages", .array(Self.messages(ending: ClaudeRequestBuilder.userMessage(request: request),
                                              harness: request.observation.harness))),
        ])
        return obj.data
    }

    /// A one-token request whose messages match a real request's up to the final user turn. Running it loads the
    /// model *and* leaves the system prompt and examples (~2,200 tokens) in Ollama's prompt cache, so the first
    /// spoken command does not pay that prefill (3-20 s cold on an M1 Pro). Ollama's bare "load" request does not.
    /// `harness` must match the harness tasks will run with, or the cached prefix is useless.
    public func warmBody(harness: HarnessKind = .native) -> Data {
        var placeholder = StepRequest(oneShot: "warm up", context: IntentContext(frontmostApp: "Finder", mode: .command, labeledElements: []))
        placeholder.observation.harness = harness
        let obj: OrderedJSON = .object([
            ("model", .string(model)),
            ("stream", .bool(false)),
            ("options", .object([("temperature", .int(0)), ("num_ctx", .int(Self.numCtx)), ("num_predict", .int(1))])),
            ("keep_alive", .string(Self.ollamaKeepAlive)),
            ("messages", .array(Self.messages(ending: ClaudeRequestBuilder.userMessage(request: placeholder), harness: harness))),
        ])
        return obj.data
    }

    /// System prompt, the few-shot examples, then `user` as the final turn.
    private static func messages(ending user: String, harness: HarnessKind) -> [OrderedJSON] {
        var messages: [OrderedJSON] = [message("system", IntentSchema.systemPrompt(for: harness))]
        for t in IntentExamples.turns(for: harness) {
            messages.append(message("user", t.user))
            messages.append(message("assistant", t.assistant))
        }
        messages.append(message("user", user))
        return messages
    }

    private static func message(_ role: String, _ content: String) -> OrderedJSON {
        .object([("role", .string(role)), ("content", .string(content))])
    }
}

public enum IntentExamples {
    private static func msg(_ app: String, elements: [(Int, String)] = [], overlay: String = "none", request: String) -> String {
        ClaudeRequestBuilder.userMessage(request: StepRequest(
            oneShot: request,
            context: IntentContext(frontmostApp: app, mode: .command,
                                   labeledElements: elements.map { (number: $0.0, title: $0.1) }, overlay: overlay)))
    }

    private static let veritasiumGoal = "open veritasium's latest video"
    private static let veritasiumTitle = "How Electricity Actually Works"

    public static let turns: [(user: String, assistant: String)] = [
        (Self.msg("Finder", request: "open chrome and go to youtube"),
         #"{"intent":"Open youtube.com in Google Chrome.","status":"done","actions":[{"kind":"open_url","url":"https://www.youtube.com","app_name":"Google Chrome"}]}"#),
        (Self.msg("Finder", request: "open youtube"),
         #"{"intent":"Open youtube.com in the default browser.","status":"done","actions":[{"kind":"open_url","url":"https://www.youtube.com"}]}"#),
        (Self.msg("Safari", request: "minimize google chrome"),
         #"{"intent":"Minimize the Google Chrome window.","status":"done","actions":[{"kind":"open_app","app_name":"Google Chrome"},{"kind":"press_key","key":"m","modifiers":["command"]}]}"#),
        (Self.msg("Safari", elements: [(1, "Back"), (2, "Forward"), (3, "Reload")], overlay: "labels", request: "click the back button"),
         #"{"intent":"Click the Back button, which is visible element 1.","status":"done","actions":[{"kind":"click","target_kind":"label","target_number":1}]}"#),
        (Self.msg("Notes", request: "scroll down a lot"),
         #"{"intent":"Scroll down by a large amount.","status":"done","actions":[{"kind":"scroll","direction":"down","amount":15}]}"#),
        (Self.msg("Mail", request: "write hello there and press enter"),
         #"{"intent":"Type the text \"hello there\" and then press Return.","status":"done","actions":[{"kind":"type_text","text":"hello there"},{"kind":"press_key","key":"return"}]}"#),
        (Self.msg("Safari", elements: [(1, "Back"), (4, "Sign in"), (9, "Search")], overlay: "labels", request: "um click the uh no scroll scroll up a bit"),
         #"{"intent":"The user started to say click but corrected themselves: scroll up a little.","status":"done","actions":[{"kind":"scroll","direction":"up","amount":3}]}"#),
        (Self.msg("Google Chrome", elements: [(1, "Back"), (2, "Forward"), (3, "Reload")],
                  request: "make the window half width and snap to the left side of the screen"),
         #"{"intent":"Move the Google Chrome window to the left half of the screen.","status":"done","actions":[{"kind":"move_window","placement":"left_half"}]}"#),
        (Self.msg("Finder", request: "what's the weather"),
         #"{"intent":"The user asked a question about the weather; this is not a computer action.","status":"ignore","actions":[{"kind":"ignore"}]}"#),
        // Two-step task: step 1 navigates and continues; step 2 sees the channel page and finishes.
        (ClaudeRequestBuilder.userMessage(request: StepRequest(
            goal: veritasiumGoal, step: 1, maxSteps: 12, history: [],
            observation: ScreenObservation(app: "Finder", mode: .command))),
         #"{"intent":"Go to the Veritasium channel's Videos tab, where the newest upload is first.","status":"continue","actions":[{"kind":"open_url","url":"https://www.youtube.com/@veritasium/videos"},{"kind":"wait","ms":1500}]}"#),
        (ClaudeRequestBuilder.userMessage(request: StepRequest(
            goal: veritasiumGoal, step: 2, maxSteps: 12,
            history: [StepRecord(
                intent: "Go to the Veritasium channel's Videos tab, where the newest upload is first.",
                actions: [.openURL(URL(string: "https://www.youtube.com/@veritasium/videos")!, app: nil), .wait(ms: 1500)])],
            observation: ScreenObservation(
                app: "Google Chrome", windowTitle: "Veritasium - YouTube", url: "https://www.youtube.com/@veritasium/videos",
                mode: .command,
                elements: [ObservedElement(number: 1, role: "AXLink", title: "Home"),
                           ObservedElement(number: 2, role: "AXLink", title: "Videos"),
                           ObservedElement(number: 3, role: "AXLink", title: "Shorts"),
                           ObservedElement(number: 4, role: "AXLink", title: veritasiumTitle)]))),
         #"{"intent":"The Videos tab is showing; open the first (newest) video.","status":"done","actions":[{"kind":"click","target_kind":"label","target_number":4}]}"#),
        // A site request from a non-browser app with a distracting element list: small models otherwise answer ignore.
        // Kept last (closest to the live request): qwen2.5:7b ignores such requests when this sits earlier.
        (Self.msg("Xcode", elements: [(1, "Run"), (2, "Stop"), (3, "Navigator"), (4, "Inspectors")], request: "go to netflix"),
         #"{"intent":"Open netflix.com in the default browser; the current app does not matter.","status":"done","actions":[{"kind":"open_url","url":"https://www.netflix.com"}]}"#),
    ]

    /// Examples that exist only for the agent-desktop harness: the message carries `Harness: agent-desktop` and the
    /// answer uses harness kinds. Sent after `turns`, with the harness prompt.
    public static let harnessTurns: [(user: String, assistant: String)] = [
        (harnessMsg("TextEdit", windowTitle: "Untitled", elements: [
            ObservedElement(number: 1, role: "textarea", title: "", value: "Meeting notes")], request: "save this as a new file"),
         #"{"intent":"Run the Save As… command from the File menu.","status":"continue","actions":[{"kind":"menu_item","target_name":"File > Save As…"},{"kind":"wait","wait_for":"window","value":"Save","app_name":"TextEdit","timeout_ms":5000}]}"#),
        (harnessMsg("Safari", windowTitle: "Start Page", elements: [
            ObservedElement(number: 1, role: "button", title: "Back", states: ["disabled"]),
            ObservedElement(number: 2, role: "textfield", title: "Address and Search", value: ""),
            ObservedElement(number: 3, role: "button", title: "Search")], request: "search for cats"),
         #"{"intent":"Put \"cats\" in the search field and run the search.","status":"done","actions":[{"kind":"set_value","target_kind":"label","target_number":2,"value":"cats"},{"kind":"click","target_kind":"label","target_number":3}]}"#),
    ]

    /// The few-shot turns for a harness: the native set, plus the harness turns when agent-desktop observes.
    public static func turns(for harness: HarnessKind) -> [(user: String, assistant: String)] {
        harness == .agentDesktop ? turns + harnessTurns : turns
    }

    private static func harnessMsg(_ app: String, windowTitle: String, elements: [ObservedElement], request: String) -> String {
        var o = ScreenObservation(app: app, windowTitle: windowTitle, mode: .command, elements: elements)
        o.harness = .agentDesktop
        return ClaudeRequestBuilder.userMessage(request: StepRequest(goal: request, step: 1, maxSteps: 12, history: [], observation: o))
    }
}
