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

/// Parameters without `required`, and parameters with a union type (`anyOf` or a type array), over the whole schema.
private func counts(_ node: Any) -> (optional: Int, union: Int) {
    var optional = 0, union = 0
    if let d = node as? JSON {
        if let props = d["properties"] as? JSON {
            optional += props.count - Set(d["required"] as? [String] ?? []).intersection(props.keys).count
        }
        if d["anyOf"] != nil || d["type"] is [Any] { union += 1 }
        for v in d.values { let c = counts(v); optional += c.optional; union += c.union }
    } else if let a = node as? [Any] {
        for v in a { let c = counts(v); optional += c.optional; union += c.union }
    }
    return (optional, union)
}

@Test(arguments: [false, true])
private func claudeSchemaStaysInsideAnthropicLimits(vision: Bool) {
    let schema = vision ? IntentSchema.visionActionsJSONSchema : IntentSchema.actionsJSONSchema
    let c = counts(schema)
    // Documented limits, https://platform.claude.com/docs/en/build-with-claude/structured-outputs
    #expect(c.optional <= 24)
    #expect(c.union <= 16)
    // Anthropic also rejects a grammar that is too large and does not publish the limit. 13 branches and 57 fields is the
    // largest shape a live call accepted (40 branches and 20 branches with 79 fields were rejected). Re-run
    // `nohands-cli resolve` with a real key before raising either number.
    let b = branches(schema)
    #expect(b.count <= 13)
    #expect(b.reduce(0) { $0 + fields($1).count } <= 57)
    #expect(b.allSatisfy { Set($0["required"] as! [String]) == Set(fields($0).keys) })
    #expect(b.allSatisfy { $0["additionalProperties"] as? Bool == false })
}

@Test func claudeSchemaOffersEveryKindOnceAndLookOnlyWithVision() {
    func offered(_ schema: JSON) -> [String] { branches(schema).flatMap(kinds).filter { $0 != "wait" } + ["wait"] }
    // `wait` is the one kind in two branches (a pause, or a wait for a signal).
    #expect(Set(offered(IntentSchema.actionsJSONSchema)) == Set(IntentSchema.kinds))
    #expect(offered(IntentSchema.actionsJSONSchema).count == IntentSchema.kinds.count)
    #expect(Set(offered(IntentSchema.visionActionsJSONSchema)) == Set(IntentSchema.kinds + ["look"]))
}

private var samples: [JSON] { [
    ["kind": "type_text", "text": "hi"], ["kind": "press_key", "key": "f", "modifiers": ["control", "command"]],
    ["kind": "press_key", "key": "return"],
    ["kind": "click", "target_kind": "label", "target_number": 7, "button": "right", "count": 2],
    ["kind": "click", "target_kind": "element", "target_name": "Reload"],
    ["kind": "click", "target_kind": "point", "x": 10.5, "y": 20],
    ["kind": "press_mouse"], ["kind": "release_mouse", "button": "middle"],
    ["kind": "move_cursor", "target_kind": "relative", "dx": 10, "dy": -5],
    ["kind": "scroll", "direction": "down", "amount": 3], ["kind": "scroll", "direction": "up"],
    ["kind": "show_grid"], ["kind": "zoom_grid", "target_number": 12], ["kind": "show_labels"], ["kind": "hide_overlay"],
    ["kind": "set_mode", "mode": "dictation"], ["kind": "open_app", "app_name": "Notes"],
    ["kind": "open_url", "url": "https://example.com"], ["kind": "open_url", "url": "example.com", "app_name": "Safari"],
    ["kind": "move_window", "placement": "left_half"], ["kind": "search", "text": "cats"],
    ["kind": "wait", "ms": 700], ["kind": "wait", "ms": 0], ["kind": "ignore"], ["kind": "look"],
    ["kind": "wait", "wait_for": "text", "value": "Done", "timeout_ms": 8000],
    ["kind": "wait", "wait_for": "event", "event": "window_opened"], ["kind": "wait", "wait_for": "media_playing"],
    ["kind": "wait", "wait_for": "element", "target_kind": "label", "target_number": 9],
    ["kind": "wait", "wait_for": "element", "target_kind": "element", "target_name": "Play", "value": "enabled"],
    ["kind": "set_value", "target_kind": "label", "target_number": 2, "value": "cats"],
    ["kind": "type_into", "target_kind": "element", "target_name": "Search", "text": "hi"],
    ["kind": "clear", "target_kind": "label", "target_number": 2],
    ["kind": "select", "target_kind": "label", "target_number": 3, "option": "Blue"],
    ["kind": "check", "target_kind": "label", "target_number": 4], ["kind": "uncheck", "target_kind": "label", "target_number": 4],
    ["kind": "toggle", "target_kind": "label", "target_number": 4],
    ["kind": "expand", "target_kind": "label", "target_number": 5], ["kind": "collapse", "target_kind": "label", "target_number": 5],
    ["kind": "focus", "target_kind": "label", "target_number": 6], ["kind": "scroll_to", "target_kind": "label", "target_number": 6],
    ["kind": "scroll_element", "target_kind": "label", "target_number": 7, "direction": "down", "amount": 3],
    ["kind": "scroll_element", "target_kind": "element", "target_name": "List", "direction": "up"],
    ["kind": "drag", "from_number": 1, "target_kind": "point", "x": 10, "y": 20],
    ["kind": "drag", "from_x": 5, "from_y": 6, "target_kind": "label", "target_number": 3],
    ["kind": "click_in", "surface": "dock", "target_name": "Safari"], ["kind": "menu_item", "target_name": "File > Save As…"],
    ["kind": "close_app", "app_name": "Slack"], ["kind": "window", "window_action": "focus", "app_name": "Safari", "title": "GitHub"],
    ["kind": "window", "window_action": "maximize"],
    ["kind": "clipboard_set", "value": "hello"], ["kind": "read_clipboard"],
    ["kind": "read_value", "target_kind": "label", "target_number": 2], ["kind": "read_notifications"],
    ["kind": "dismiss_notifications"], ["kind": "dismiss_notifications", "app_name": "Mail"],
    ["kind": "close_tab", "target_number": 2], ["kind": "close_window", "target_number": 1], ["kind": "select_tab", "target_number": 3],
] }

private let expected: [Action] = [
    .typeText("hi"), .pressKey(KeyChord(.f, [.control, .command])), .pressKey(KeyChord(.return)),
    .click(.label(7), button: .right, count: 2), .click(.element(named: "Reload"), button: .left, count: 1),
    .click(.point(CGPoint(x: 10.5, y: 20)), button: .left, count: 1),
    .pressMouse(.left), .releaseMouse(.middle), .moveCursor(.relative(dx: 10, dy: -5)),
    .scroll(.down, amount: 3), .scroll(.up, amount: 1),
    .showGrid, .zoomGrid(12), .showLabels, .hideOverlay, .setMode(.dictation), .openApp("Notes"),
    .openURL(URL(string: "https://example.com")!, app: nil), .openURL(URL(string: "https://example.com")!, app: "Safari"),
    .moveWindow(.leftHalf), .search("cats"), .wait(ms: 700), .wait(ms: 100), .ignore, .look,
    .waitFor(.text("Done"), timeoutMs: 8000), .waitFor(.event(.windowOpened), timeoutMs: 500), .waitFor(.mediaPlaying, timeoutMs: 500),
    .waitFor(.element(.label(9), predicate: "exists"), timeoutMs: 500),
    .waitFor(.element(.named("Play"), predicate: "enabled"), timeoutMs: 500),
    .setValue(.label(2), "cats"), .typeInto(.named("Search"), "hi"), .clearField(.label(2)), .selectOption(.label(3), "Blue"),
    .setChecked(.label(4), true), .setChecked(.label(4), false), .setChecked(.label(4), nil),
    .setExpanded(.label(5), true), .setExpanded(.label(5), false), .focusElement(.label(6)), .scrollTo(.label(6)),
    .scrollIn(.label(7), .down, amount: 3), .scrollIn(.named("List"), .up, amount: 1),
    .drag(from: .label(1), to: .point(CGPoint(x: 10, y: 20))), .drag(from: .point(CGPoint(x: 5, y: 6)), to: .label(3)),
    .clickIn(.dock, name: "Safari"), .menuItem("File > Save As…"), .closeApp("Slack"),
    .windowAction(.focus, app: "Safari", title: "GitHub"), .windowAction(.maximize, app: nil, title: nil),
    .clipboardSet("hello"), .readClipboard, .readValue(.label(2)), .readNotifications,
    .dismissNotifications(app: nil), .dismissNotifications(app: "Mail"),
    .closeTab(2), .closeWindow(1), .selectTab(3),
]

/// What a model must send for `sample`: the one branch that offers its kind and every field it names, with each field
/// the sample leaves out blank (`""`, `0`, `[]`, or the first enum value), the way the schema forces.
private func sent(_ sample: JSON, in schema: JSON) -> JSON? {
    let match = branches(schema).filter { b in
        kinds(b).contains(sample["kind"] as! String) && Set(sample.keys).isSubset(of: Set(fields(b).keys))
    }
    guard match.count == 1 else { return nil }
    var out = sample
    for (name, spec) in fields(match[0]) where out[name] == nil {
        let s = spec as! JSON
        if let e = s["enum"] as? [String] { out[name] = e[0] }
        else { out[name] = s["type"] as! String == "string" ? "" : s["type"] as! String == "array" ? [] : 0 }
    }
    for (name, value) in out {
        if let e = (fields(match[0])[name] as! JSON)["enum"] as? [String], let v = value as? String, !e.contains(v) { return nil }
    }
    return out
}

@Test func everyKindCanBeProducedAndDecodes() throws {
    #expect(samples.count == expected.count)
    let covered = Set(samples.map { $0["kind"] as! String })
    #expect(covered == Set(IntentSchema.kinds + ["look"]))
    for (sample, action) in zip(samples, expected) {
        let schema = sample["kind"] as! String == "look" ? IntentSchema.visionActionsJSONSchema : IntentSchema.actionsJSONSchema
        let one = try #require(sent(sample, in: schema), "\(sample)")
        let text = String(decoding: try JSONSerialization.data(withJSONObject: ["intent": "x", "status": "continue", "actions": [one]]), as: UTF8.self)
        #expect(try IntentDecoder.step(fromPayloadText: text).actions == [action], "\(sample)")
    }
    #expect(sent(["kind": "look"], in: IntentSchema.actionsJSONSchema) == nil)
}

@Test func blankValuesTheSchemaForcesDoNotAct() throws {
    let blanks = [
        #"{"kind":"click","target_kind":"label","target_number":0,"button":"left","count":0,"from_number":0,"from_name":"","from_x":0,"from_y":0,"target_name":"","x":0,"y":0,"dx":0,"dy":0}"#,
        #"{"kind":"click","target_kind":"element","target_number":0,"target_name":" "}"#,
        #"{"kind":"drag","target_kind":"label","target_number":3,"from_number":0,"from_name":"","from_x":0,"from_y":0}"#,
        #"{"kind":"scroll_element","target_kind":"label","target_number":0,"target_name":"","direction":"down","amount":0}"#,
        #"{"kind":"zoom_grid","target_kind":"label","target_number":0,"target_name":"","value":"","text":"","option":""}"#,
        #"{"kind":"close_tab","target_kind":"label","target_number":0,"target_name":"","value":"","text":"","option":""}"#,
        #"{"kind":"type_into","target_kind":"label","target_number":2,"target_name":"","value":"","text":"","option":""}"#,
        #"{"kind":"select","target_kind":"label","target_number":2,"target_name":"","value":"","text":"","option":""}"#,
        #"{"kind":"wait","wait_for":"text","event":"window_opened","value":"","timeout_ms":0,"target_kind":"label","target_number":0,"target_name":""}"#,
        #"{"kind":"open_app","app_name":"","url":""}"#, #"{"kind":"open_url","app_name":"Safari","url":""}"#,
        #"{"kind":"close_app","app_name":"","url":""}"#, #"{"kind":"search","text":""}"#, #"{"kind":"menu_item","surface":"menu","target_name":""}"#,
        #"{"kind":"click_in","surface":"dock","target_name":""}"#,
    ]
    for b in blanks {
        #expect(try IntentDecoder.step(fromPayloadText: #"{"actions":[\#(b)]}"#).actions.isEmpty, "\(b)")
    }
}

@Test func claudeRequestsShareOneSchemaAndRulesText() throws {
    let a = IntentContext(frontmostApp: "Finder", mode: .command, labeledElements: [(1, "Back")])
    let b = IntentContext(frontmostApp: "Safari", mode: .dictation, labeledElements: [])
    func format(_ transcript: String, _ context: IntentContext) throws -> NSDictionary {
        let o = try #require(JSONSerialization.jsonObject(with: ClaudeRequestBuilder(model: "m").body(transcript: transcript, context: context)) as? JSON)
        return try #require((o["output_config"] as? JSON)?["format"] as? NSDictionary)
    }
    #expect(try format("go back", a) == format("open the downloads folder", b))
    #expect(ClaudeRequestBuilder.systemText(for: .native).contains(IntentSchema.claudeFieldsRule))
    #expect(!IntentSchema.systemPrompt.contains(IntentSchema.claudeFieldsRule))
}
