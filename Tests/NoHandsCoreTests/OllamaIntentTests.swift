import Testing
import Foundation
@testable import NoHandsCore

@Test func ollamaBodyShape() throws {
    let ctx = IntentContext(frontmostApp: "Finder", mode: .command, labeledElements: [(3, "Back")])
    let data = try OllamaRequestBuilder(model: "qwen2.5:7b-instruct").body(transcript: "go back please", context: ctx)
    let o = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(o["model"] as? String == "qwen2.5:7b-instruct")
    #expect(o["stream"] as? Bool == false)
    #expect(o["keep_alive"] as? String == "30m")
    #expect((o["options"] as? [String: Any])?["temperature"] as? Double == 0)
    // 120 elements plus history is ~4k tokens; Ollama's default 4096 context would silently truncate the system prompt.
    #expect((o["options"] as? [String: Any])?["num_ctx"] as? Int == 8192)
    #expect(o["format"] as? NSDictionary == IntentSchema.actionsJSONSchema as NSDictionary)
    let msgs = try #require(o["messages"] as? [[String: String]])
    #expect(msgs.first == ["role": "system", "content": IntentSchema.systemPrompt])
    #expect(msgs.count == 1 + 2 * IntentExamples.turns.count + 1)
    #expect(msgs.last == ["role": "user", "content": ClaudeRequestBuilder.userMessage(transcript: "go back please", context: ctx)])
}

@Test func examplesAreValidAndCoverKeyCases() throws {
    #expect(IntentExamples.turns.count >= 5)
    for t in IntentExamples.turns {
        #expect(t.user.contains("Request: "))
        #expect(!(try IntentDecoder.actions(fromPayloadText: t.assistant)).isEmpty)
    }
    let users = IntentExamples.turns.map(\.user).joined(separator: "\n")
    for phrase in ["open chrome and go to youtube", "minimize google chrome", "click the back button", "what's the weather"] {
        #expect(users.contains(phrase))
    }
}

@Test func ollamaResponseKeepsValidDropsInvalid() throws {
    let content = #"{"actions":[{"kind":"open_app","app_name":"Google Chrome"},{"kind":"fly"},{"kind":"click","target_kind":"label","target_number":0}]}"#
    let data = try JSONSerialization.data(withJSONObject: ["message": ["role": "assistant", "content": content], "done": true])
    #expect(try IntentDecoder.actions(fromOllamaResponse: data) == [.openApp("Google Chrome")])
}

@Test func ollamaProseContentIsMalformed() throws {
    let data = try JSONSerialization.data(withJSONObject: ["message": ["role": "assistant", "content": "Sure! Here you go."]])
    #expect(throws: IntentDecodeError.self) { try IntentDecoder.actions(fromOllamaResponse: data) }
    #expect(throws: IntentDecodeError.noTextBlock) { try IntentDecoder.actions(fromOllamaResponse: Data(#"{"done":true}"#.utf8)) }
}

/// The warm-up body shares every message but the last with a real request, so Ollama's prompt cache holds the
/// system prompt and examples (~2,200 tokens, 3-20 s of prefill on an M1 Pro) before the first spoken command.
@Test func ollamaWarmBodyIsAPrefixOfRealRequests() throws {
    let b = OllamaRequestBuilder(model: "qwen2.5:7b-instruct")
    let warm = try #require(try JSONSerialization.jsonObject(with: b.warmBody()) as? [String: Any])
    let ctx = IntentContext(frontmostApp: "Finder", mode: .command, labeledElements: [])
    let real = try #require(try JSONSerialization.jsonObject(with: b.body(transcript: "go back", context: ctx)) as? [String: Any])
    let warmMsgs = try #require(warm["messages"] as? [[String: String]])
    let realMsgs = try #require(real["messages"] as? [[String: String]])
    #expect(warmMsgs.count == realMsgs.count)
    #expect(Array(warmMsgs.dropLast()) == Array(realMsgs.dropLast()))
    #expect(warmMsgs.last?["role"] == "user")
    #expect(warm["model"] as? String == "qwen2.5:7b-instruct")
    #expect(warm["stream"] as? Bool == false)
    #expect(warm["keep_alive"] as? String == "30m")
    let opts = try #require(warm["options"] as? [String: Any])
    #expect(opts["num_predict"] as? Int == 1)
    #expect(opts["num_ctx"] as? Int == 8192)
}
