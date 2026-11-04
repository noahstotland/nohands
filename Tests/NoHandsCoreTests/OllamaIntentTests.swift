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
