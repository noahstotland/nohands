import Testing
import Foundation
import CoreGraphics
@testable import NoHandsCore

@Test func decodesEveryHarnessKind() throws {
    let json = #"""
    {"intent":"x","status":"continue","actions":[
      {"kind":"set_value","target_kind":"label","target_number":2,"value":"cats"},
      {"kind":"type_into","target_kind":"element","target_name":"Search","text":"hi"},
      {"kind":"clear","target_kind":"label","target_number":2},
      {"kind":"select","target_kind":"label","target_number":3,"option":"Blue"},
      {"kind":"check","target_kind":"label","target_number":4},{"kind":"uncheck","target_kind":"label","target_number":4},{"kind":"toggle","target_kind":"label","target_number":4},
      {"kind":"expand","target_kind":"label","target_number":5},{"kind":"collapse","target_kind":"label","target_number":5},
      {"kind":"focus","target_kind":"label","target_number":6},{"kind":"scroll_to","target_kind":"label","target_number":6},
      {"kind":"scroll_element","target_kind":"label","target_number":7,"direction":"down","amount":3},
      {"kind":"drag","from_number":1,"target_kind":"point","x":10,"y":20},
      {"kind":"click_in","surface":"dock","target_name":"Safari"},
      {"kind":"menu_item","target_name":"File > Save As…"},
      {"kind":"close_app","app_name":"Slack"},
      {"kind":"window","window_action":"focus","app_name":"Safari","title":"GitHub"},
      {"kind":"clipboard_set","value":"hello"},{"kind":"read_clipboard"},
      {"kind":"read_value","target_kind":"label","target_number":2},
      {"kind":"read_notifications"},{"kind":"dismiss_notifications","app_name":"Mail"},
      {"kind":"wait","wait_for":"text","value":"Done","app_name":"App","timeout_ms":100},
      {"kind":"wait","wait_for":"event","event":"window_opened"},
      {"kind":"wait","wait_for":"element","target_number":9,"value":"actionable"},
      {"kind":"wait","ms":700}]}
    """#
    let a = try IntentDecoder.step(fromPayloadText: json).actions
    #expect(a.count == 26)
    #expect(a[0] == .setValue(.label(2), "cats") && a[1] == .typeInto(.named("Search"), "hi") && a[2] == .clearField(.label(2)))
    #expect(a[3] == .selectOption(.label(3), "Blue"))
    #expect(a[4] == .setChecked(.label(4), true) && a[5] == .setChecked(.label(4), false) && a[6] == .setChecked(.label(4), nil))
    #expect(a[7] == .setExpanded(.label(5), true) && a[8] == .setExpanded(.label(5), false))
    #expect(a[9] == .focusElement(.label(6)) && a[10] == .scrollTo(.label(6)) && a[11] == .scrollIn(.label(7), .down, amount: 3))
    #expect(a[12] == .drag(from: .label(1), to: .point(CGPoint(x: 10, y: 20))))
    #expect(a[13] == .clickIn(.dock, name: "Safari") && a[14] == .menuItem("File > Save As…") && a[15] == .closeApp("Slack"))
    #expect(a[16] == .windowAction(.focus, app: "Safari", title: "GitHub"))
    #expect(a[17] == .clipboardSet("hello") && a[18] == .readClipboard && a[19] == .readValue(.label(2)))
    #expect(a[20] == .readNotifications && a[21] == .dismissNotifications(app: "Mail"))
    #expect(a[22] == .waitFor(.text("Done"), timeoutMs: 500) && a[23] == .waitFor(.event(.windowOpened), timeoutMs: 5000))
    #expect(a[24] == .waitFor(.element(.label(9), predicate: "actionable"), timeoutMs: 5000) && a[25] == .wait(ms: 700))
}

@Test func harnessKindsFailClosedOnMissingFields() throws {
    let json = #"{"actions":[{"kind":"set_value","value":"x"},{"kind":"click_in","target_name":"Safari"},{"kind":"window","app_name":"Safari"},{"kind":"wait","wait_for":"element","value":"exists"},{"kind":"select","target_kind":"label","target_number":1},{"kind":"wait","wait_for":"event","event":"nope"},{"kind":"drag","target_kind":"label","target_number":2},{"kind":"menu_item"},{"kind":"close_app"}]}"#
    #expect(try IntentDecoder.step(fromPayloadText: json).actions.isEmpty)
}

@Test func emptySetValueClearsAndWaitClamps() throws {
    let json = #"{"actions":[{"kind":"set_value","target_kind":"label","target_number":2,"value":""},{"kind":"wait","wait_for":"window","value":"Save","timeout_ms":99999},{"kind":"drag","from_x":1,"from_y":2,"target_kind":"label","target_number":3},{"kind":"drag","from_name":"A","target_kind":"element","target_name":"B"}]}"#
    let a = try IntentDecoder.step(fromPayloadText: json).actions
    #expect(a == [.clearField(.label(2)), .waitFor(.window("Save"), timeoutMs: 30000),
                  .drag(from: .point(CGPoint(x: 1, y: 2)), to: .label(3)), .drag(from: .element(named: "A"), to: .element(named: "B"))])
}

@Test func schemaListsNewKindsAndFieldsAndStaysClosed() {
    let props = (IntentSchema.actionsJSONSchema["properties"] as! [String: Any])["actions"] as! [String: Any]
    let item = props["items"] as! [String: Any]
    let fields = item["properties"] as! [String: Any]
    for f in ["value", "option", "surface", "window_action", "title", "wait_for", "event", "predicate", "timeout_ms", "from_number", "from_name", "from_x", "from_y"] {
        #expect(fields[f] != nil, "\(f)")
    }
    let kinds = ((fields["kind"] as! [String: Any])["enum"] as! [String])
    for k in ["set_value", "type_into", "clear", "select", "check", "uncheck", "toggle", "expand", "collapse", "focus", "scroll_to",
              "scroll_element", "drag", "click_in", "menu_item", "close_app", "window", "clipboard_set", "read_clipboard",
              "read_value", "read_notifications", "dismiss_notifications"] {
        #expect(kinds.contains(k), "\(k)")
    }
    #expect(item["additionalProperties"] as? Bool == false)
    #expect(((fields["surface"] as! [String: Any])["enum"] as! [String]).contains("menu_bar_extras"))
    #expect(((fields["event"] as! [String: Any])["enum"] as! [String]) == DesktopEvent.allCases.map(\.rawValue))
}

@Test func promptAddsHarnessRulesOnlyForAgentDesktop() {
    #expect(IntentSchema.systemPrompt(for: .native) == IntentSchema.systemPrompt)
    let p = IntentSchema.systemPrompt(for: .agentDesktop)
    #expect(p.hasPrefix(IntentSchema.systemPrompt) && p.contains("- menu_item:") && p.contains("Harness rules:"))
    #expect(!IntentSchema.systemPrompt.contains("menu_item"))
    for k in ["set_value", "type_into", "click_in", "close_app", "read_clipboard", "wait_for", "dismiss_notifications"] { #expect(p.contains(k), "\(k)") }
}

@Test func requestBodiesUseTheObservationHarnessPrompt() throws {
    var o = ScreenObservation(app: "Finder", mode: .command); o.harness = .agentDesktop
    let r = StepRequest(goal: "g", step: 1, maxSteps: 2, history: [], observation: o)
    let claude = try JSONSerialization.jsonObject(with: ClaudeRequestBuilder(model: "m").body(request: r)) as! [String: Any]
    #expect((claude["system"] as! String).contains("Harness rules:"))
    let ollama = try JSONSerialization.jsonObject(with: OllamaRequestBuilder(model: "m").body(request: r)) as! [String: Any]
    let msgs = ollama["messages"] as! [[String: Any]]
    #expect((msgs[0]["content"] as! String).contains("Harness rules:"))
    #expect(msgs.count == 1 + 2 * IntentExamples.turns(for: .agentDesktop).count + 1)
    let warm = try JSONSerialization.jsonObject(with: OllamaRequestBuilder(model: "m").warmBody()) as! [String: Any]
    #expect(!(((warm["messages"] as! [[String: Any]])[0]["content"] as! String).contains("Harness rules:")))
    let warmH = try JSONSerialization.jsonObject(with: OllamaRequestBuilder(model: "m").warmBody(harness: .agentDesktop)) as! [String: Any]
    let warmMsgs = warmH["messages"] as! [[String: Any]]
    #expect((warmMsgs[0]["content"] as! String).contains("Harness rules:"))
    #expect(warmMsgs.count == 1 + 2 * IntentExamples.turns(for: .agentDesktop).count + 1)
}

@Test func harnessExamplesDecodeAndShowTheNewKinds() throws {
    #expect(IntentExamples.turns(for: .native).count == IntentExamples.turns.count)
    let all = IntentExamples.turns(for: .agentDesktop)
    #expect(all.count == IntentExamples.turns.count + IntentExamples.harnessTurns.count && IntentExamples.harnessTurns.count >= 2)
    for t in all {
        #expect(!(try IntentDecoder.step(fromPayloadText: t.assistant)).actions.isEmpty)
    }
    let joined = IntentExamples.harnessTurns.map(\.assistant).joined()
    #expect(joined.contains("\"menu_item\"") && joined.contains("\"set_value\""))
    #expect(IntentExamples.harnessTurns.allSatisfy { $0.user.contains("Harness: agent-desktop") })
}
