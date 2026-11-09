import Testing
import Foundation
import CoreGraphics
@testable import NoHandsCore

private typealias JSON = [String: Any]

private func branches(_ schema: JSON) -> [JSON] {
    let actions = (schema["properties"] as! JSON)["actions"] as! JSON
    return (actions["items"] as! JSON)["anyOf"] as! [JSON]
}
private func fields(_ branch: JSON) -> JSON { branch["properties"] as! JSON }
private func kinds(_ branch: JSON) -> [String] { (fields(branch)["kind"] as! JSON)["enum"] as! [String] }
private func schema(vision: Bool) -> JSON { vision ? IntentSchema.visionActionsJSONSchema : IntentSchema.actionsJSONSchema }

/// Parameters without `required`, and parameters with a union type (`anyOf` or a type array), over the whole schema.
private func counts(_ node: Any) -> (optional: Int, union: Int) {
    var optional = 0, union = 0
    if let d = node as? JSON {
        if let props = d["properties"] as? JSON { optional += props.count - Set(d["required"] as? [String] ?? []).intersection(props.keys).count }
        if d["anyOf"] != nil || d["type"] is [Any] { union += 1 }
        for v in d.values { let c = counts(v); optional += c.optional; union += c.union }
    } else if let a = node as? [Any] {
        for v in a { let c = counts(v); optional += c.optional; union += c.union }
    }
    return (optional, union)
}

@Test(arguments: [false, true])
private func claudeSchemaStaysInsideAnthropicLimits(vision: Bool) {
    let c = counts(schema(vision: vision)), b = branches(schema(vision: vision))
    // Documented limits, https://platform.claude.com/docs/en/build-with-claude/structured-outputs
    #expect(c.optional <= 24)
    #expect(c.union <= 16)
    // Anthropic also rejects a grammar that is too large and does not publish the limit. 13 branches and 57 fields is the
    // largest shape a live call accepted (40 branches, and 20 branches with 79 fields, were rejected). Re-run
    // `nohands-cli resolve` with a real key before raising either number.
    #expect(b.count <= 13)
    #expect(b.reduce(0) { $0 + fields($1).count } <= 57)
    #expect(b.allSatisfy { Set($0["required"] as! [String]) == Set(fields($0).keys) && $0["additionalProperties"] as? Bool == false })
}

@Test func claudeSchemaOffersEveryKindOnceAndLookOnlyWithVision() {
    for vision in [false, true] {
        let b = branches(schema(vision: vision)), all = b.flatMap(kinds)
        // `wait` is the one kind in two branches (a pause, or a wait for a signal).
        #expect(all.filter { $0 == "wait" }.count == 2)
        #expect(all.filter { $0 != "wait" }.sorted() == (IntentSchema.kinds.filter { $0 != "wait" } + (vision ? ["look"] : [])).sorted())
    }
}

/// What the model sends for `sample`: the one branch that offers its kind and names, with every field the sample leaves
/// out blank the way the schema forces (`""`, `0`, `[]`, the first enum value). Nil when no single branch fits.
private func sent(_ sample: JSON, in schema: JSON) -> (action: JSON, branch: Int)? {
    let match = branches(schema).enumerated().filter { _, b in
        kinds(b).contains(sample["kind"] as! String) && Set(sample.keys).isSubset(of: Set(fields(b).keys))
    }
    guard match.count == 1 else { return nil }
    var out = sample
    for (name, spec) in fields(match[0].element) {
        let s = spec as! JSON, enums = s["enum"] as? [String]
        if let v = out[name] as? String, let enums, !enums.contains(v) { return nil }
        if out[name] == nil { out[name] = enums?[0] ?? (s["type"] as! String == "string" ? "" : s["type"] as! String == "array" ? [] : 0) }
    }
    return (out, match[0].offset)
}

/// One sample per branch, and the kinds that read several fields; a `0` or `""` is what the schema made the model send.
private var reachable: [(JSON, Action)] { [
    (["kind": "show_grid"], .showGrid), (["kind": "look"], .look), (["kind": "search", "text": "cats"], .search("cats")),
    (["kind": "press_key", "key": "f", "modifiers": ["control", "command"]], .pressKey(KeyChord(.f, [.control, .command]))),
    (["kind": "click", "target_kind": "label", "target_number": 7, "button": "right", "count": 2], .click(.label(7), button: .right, count: 2)),
    (["kind": "click", "target_kind": "element", "target_name": "Reload"], .click(.element(named: "Reload"), button: .left, count: 1)),
    (["kind": "drag", "from_number": 1, "target_kind": "point", "x": 10, "y": 20], .drag(from: .label(1), to: .point(CGPoint(x: 10, y: 20)))),
    (["kind": "scroll", "direction": "down", "amount": 3], .scroll(.down, amount: 3)),
    (["kind": "scroll", "direction": "up"], .scroll(.up, amount: 1)),
    (["kind": "scroll_element", "target_kind": "element", "target_name": "List", "direction": "up"], .scrollIn(.named("List"), .up, amount: 3)),
    (["kind": "set_mode", "mode": "dictation"], .setMode(.dictation)),
    (["kind": "open_url", "url": "example.com"], .openURL(URL(string: "https://example.com")!, app: nil)),
    (["kind": "move_window", "placement": "left_half"], .moveWindow(.leftHalf)),
    (["kind": "wait", "ms": 700], .wait(ms: 700)), (["kind": "wait", "ms": 0], .wait(ms: 1000)),
    (["kind": "wait", "wait_for": "element", "target_kind": "label", "target_number": 9], .waitFor(.element(.label(9), predicate: "exists"), timeoutMs: 5000)),
    (["kind": "wait", "wait_for": "event", "event": "window_opened", "timeout_ms": 8000], .waitFor(.event(.windowOpened), timeoutMs: 8000)),
    (["kind": "type_into", "target_kind": "element", "target_name": "Search", "text": "hi"], .typeInto(.named("Search"), "hi")),
    (["kind": "set_value", "target_kind": "label", "target_number": 2, "value": "cats"], .setValue(.label(2), "cats")),
    (["kind": "click_in", "surface": "dock", "target_name": "Safari"], .clickIn(.dock, name: "Safari")),
    (["kind": "window", "window_action": "focus", "app_name": "Safari", "title": "GitHub"], .windowAction(.focus, app: "Safari", title: "GitHub")),
] }

@Test func everyBranchIsReachableAndDecodes() throws {
    var hit = Set<Int>()
    for (sample, action) in reachable {
        let (one, branch) = try #require(sent(sample, in: schema(vision: true)), "\(sample)")
        hit.insert(branch)
        let text = String(decoding: try JSONSerialization.data(withJSONObject: ["intent": "x", "status": "continue", "actions": [one]]), as: UTF8.self)
        #expect(try IntentDecoder.step(fromPayloadText: text).actions == [action], "\(sample)")
    }
    #expect(hit == Set(0..<branches(schema(vision: true)).count))
}

@Test func blankValuesTheSchemaForcesDoNotAct() throws {
    let blanks = [
        #"{"kind":"click","target_kind":"label","target_number":0,"target_name":"","x":0,"y":0,"dx":0,"dy":0,"button":"left","count":0}"#,
        #"{"kind":"click","target_kind":"element","target_number":0,"target_name":" "}"#,
        #"{"kind":"drag","target_kind":"label","target_number":3,"from_number":0,"from_name":"","from_x":0,"from_y":0}"#,
        #"{"kind":"scroll_element","target_kind":"label","target_number":0,"target_name":"","direction":"down","amount":0}"#,
        #"{"kind":"zoom_grid","target_kind":"label","target_number":0,"target_name":"","value":"","text":"","option":""}"#,
        #"{"kind":"type_into","target_kind":"label","target_number":2,"value":"","text":"","option":""}"#,
        #"{"kind":"select","target_kind":"label","target_number":2,"value":"","text":"","option":""}"#,
        #"{"kind":"wait","wait_for":"text","value":"","timeout_ms":0}"#,
        #"{"kind":"open_app","app_name":"","url":""}"#, #"{"kind":"open_url","app_name":"Safari","url":""}"#,
        #"{"kind":"search","text":""}"#, #"{"kind":"menu_item","surface":"menu","target_name":""}"#,
        // A value filed under the wrong field must not clear a field or the clipboard.
        #"{"kind":"set_value","target_kind":"label","target_number":2,"value":"","text":"hello","option":""}"#,
        #"{"kind":"set_value","target_kind":"label","target_number":2,"value":"","text":"","option":"Blue"}"#,
        #"{"kind":"clipboard_set","target_kind":"label","target_number":0,"value":"","text":"hello","option":""}"#,
    ]
    for b in blanks {
        #expect(try IntentDecoder.step(fromPayloadText: #"{"actions":[\#(b)]}"#).actions.isEmpty, "\(b)")
    }
}

@Test(arguments: [false, true])
private func claudeBodyKeepsSchemaOrderAndIsByteStable(vision: Bool) throws {
    let builder = ClaudeRequestBuilder(model: "m", vision: vision)
    func text(_ transcript: String, _ app: String) throws -> String {
        String(decoding: try builder.body(transcript: transcript, context: IntentContext(frontmostApp: app, mode: .command, labeledElements: [])), as: UTF8.self)
    }
    let first = try text("go back", "Finder")
    // Order is semantic for a constrained decoder: the restatement, then the status, then the actions, and the kind
    // before the fields that depend on it. A dictionary would emit them in a random order.
    let intent = try #require(first.range(of: #""properties":{"intent""#)), status = try #require(first.range(of: #""status":{"#))
    let actions = try #require(first.range(of: #""actions":{"#))
    #expect(intent.lowerBound < status.lowerBound && status.lowerBound < actions.lowerBound)
    #expect(first.contains(#""properties":{"kind":"#))
    // Everything before the user message is the cached prefix: it must not change from one request to the next.
    func prefix(_ body: String) throws -> Substring { body[..<(try #require(body.range(of: #","messages":"#)).lowerBound)] }
    #expect(try prefix(first) == prefix(text("open the downloads folder", "Safari")))
    #expect(ClaudeRequestBuilder.systemText(for: .native).contains(IntentSchema.claudeFieldsRule))
}
