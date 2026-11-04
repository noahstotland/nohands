import Testing
import Foundation
@testable import NoHandsCore

@Test func requestBodyMatchesConstraints() throws {
    let ctx = IntentContext(frontmostApp: "Safari", mode: .command, labeledElements: [(3, "Back"), (7, "Reload")])
    let data = try ClaudeRequestBuilder(model: "claude-opus-5-5").body(transcript: "go back", context: ctx)
    let obj = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(obj["model"] as? String == "claude-opus-5-5")
    #expect(obj["max_tokens"] as? Int == 1024)
    #expect(obj["fallbacks"] as? String == "default")
    let oc = try #require(obj["output_config"] as? [String: Any])
    #expect(oc["effort"] as? String == "low")
    let fmt = try #require(oc["format"] as? [String: Any])
    #expect(fmt["type"] as? String == "json_schema")
    #expect(fmt["schema"] != nil)
    #expect(obj["temperature"] == nil); #expect(obj["thinking"] == nil); #expect(obj["tool_choice"] == nil)
    let msgs = try #require(obj["messages"] as? [[String: Any]])
    #expect(msgs.count == 1)
    let text = try #require(msgs[0]["content"] as? String)
    #expect(text.contains("Safari")); #expect(text.contains("7: Reload")); #expect(text.hasSuffix("go back"))
    let h = ClaudeRequestBuilder.headers("k")
    #expect(h["x-api-key"] == "k"); #expect(h["anthropic-version"] == "2026-10-21"); #expect(h["anthropic-beta"] == "server-side-fallback-2026-07-01")
}

@Test func schemaHasNoRecursionAndClosesObjects() throws {
    let data = try JSONSerialization.data(withJSONObject: IntentSchema.actionsJSONSchema)
    let s = String(decoding: data, as: UTF8.self)
    #expect(!s.contains("$ref"))
    #expect(s.contains("\"additionalProperties\":false"))
    #expect(!s.contains("minimum")); #expect(!s.contains("maxLength"))
}

func response(_ json: String, stop: String = "end_turn") -> Data {
    #"{"id":"msg_1","type":"message","role":"assistant","model":"claude-opus-5-5","stop_reason":"\#(stop)","content":[{"type":"text","text":\#(json)}],"usage":{"input_tokens":1,"output_tokens":1}}"#.data(using: .utf8)!
}

@Test func decodesEveryKind() throws {
    let body = #""{\"actions\":[{\"kind\":\"press_key\",\"key\":\"f\",\"modifiers\":[\"control\",\"command\"]},{\"kind\":\"click\",\"target_kind\":\"label\",\"target_number\":7,\"button\":\"left\",\"count\":1},{\"kind\":\"click\",\"target_kind\":\"element\",\"target_name\":\"Reload\"},{\"kind\":\"move_cursor\",\"target_kind\":\"relative\",\"dx\":10,\"dy\":-5},{\"kind\":\"scroll\",\"direction\":\"down\",\"amount\":3},{\"kind\":\"type_text\",\"text\":\"hi\"},{\"kind\":\"set_mode\",\"mode\":\"dictation\"},{\"kind\":\"open_app\",\"app_name\":\"Notes\"},{\"kind\":\"zoom_grid\",\"target_number\":12},{\"kind\":\"ignore\"}]}""#
    let actions = try IntentDecoder.actions(fromResponse: response(body))
    #expect(actions == [
        .pressKey(KeyChord(.f, [.control, .command])),
        .click(.numbered(7), button: .left, count: 1),
        .click(.element(named: "Reload"), button: .left, count: 1),
        .moveCursor(.relative(dx: 10, dy: -5)),
        .scroll(.down, amount: 3),
        .typeText("hi"),
        .setMode(.dictation),
        .openApp("Notes"),
        .zoomGrid(12),
        .ignore,
    ])
}

@Test func unknownKindYieldsNoActions() throws {
    let body = #""{\"actions\":[{\"kind\":\"launch_missiles\"},{\"kind\":\"press_key\"},{\"kind\":\"click\",\"target_kind\":\"label\"}]}""#
    #expect(try IntentDecoder.actions(fromResponse: response(body)) == [])
    #expect(try IntentDecoder.actions(fromResponse: response(#""{\"actions\":[]}""#)) == [])
}

@Test func refusalYieldsNoActions() {
    #expect(throws: IntentDecodeError.refusal) {
        try IntentDecoder.actions(fromResponse: response(#""{\"actions\":[]}""#, stop: "refusal"))
    }
    #expect(throws: IntentDecodeError.self) {
        try IntentDecoder.actions(fromResponse: "not json".data(using: .utf8)!)
    }
}

@Test func noTextBlockAndMalformedText() {
    let none = #"{"stop_reason":"end_turn","content":[{"type":"thinking"}]}"#.data(using: .utf8)!
    #expect(throws: IntentDecodeError.noTextBlock) { try IntentDecoder.actions(fromResponse: none) }
    #expect(throws: IntentDecodeError.self) { try IntentDecoder.actions(fromResponse: response(#""nope""#)) }
}
