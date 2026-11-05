import Testing
import Foundation
import NoHandsCore
@testable import NoHandsMac

private let snapshotData = #"{"app":"Finder","complete":true,"snapshot_id":"s1","ref_count":1,"window":{"id":"w-2","title":"B"},"tree":{"role":"window","children":[{"ref_id":"@s1:e1","role":"button","name":"OK","bounds":{"x":1,"y":2,"width":3,"height":4}}]}}"#
private let ambiguous = #"{"kind":"ambiguous_window","candidates":[{"id":"w-1","is_focused":false,"title":"A","visible":true},{"id":"w-2","is_focused":true,"title":"B","visible":true}]}"#
private let ambiguousUnfocused = #"{"kind":"ambiguous_window","candidates":[{"id":"w-9","is_focused":false,"title":"Hidden","visible":false},{"id":"w-1","is_focused":false,"title":"A","visible":true}]}"#

private func make(headed: Bool = true) -> (AgentDesktopHarness, ScriptedClient) {
    let c = ScriptedClient()
    return (AgentDesktopHarness(client: c, headedFallback: headed), c)
}

@Test func ambiguousSnapshotRetriesWithFocusedOrFirstVisibleWindow() async {
    let (h, c) = make()
    c.responses["snapshot"] = [errorEnvelope("snapshot", code: "AMBIGUOUS_TARGET", details: ambiguous), okEnvelope("snapshot", data: snapshotData)]
    let s = await h.snapshot(app: "Finder", surface: nil, timeoutMs: 3000)
    #expect(s?.elements.first?.ref == "@s1:e1" && s?.windowID == "w-2")
    #expect(c.calls.count == 2 && !c.calls[0].contains("--window-id") && c.calls[1].contains(["--window-id", "w-2"]))
    #expect(c.calls[0].contains(["--app", "Finder"]) && c.calls[0].contains(["--timeout-ms", "3000"]))

    let (h2, c2) = make()
    c2.responses["snapshot"] = [errorEnvelope("snapshot", code: "AMBIGUOUS_TARGET", details: ambiguousUnfocused), okEnvelope("snapshot", data: snapshotData)]
    _ = await h2.snapshot(app: "Finder", surface: nil, timeoutMs: 3000)
    #expect(c2.calls[1].contains(["--window-id", "w-1"]))
}

@Test func snapshotReturnsNilOnOtherErrorsAndPassesSurfaces() async {
    let (h, c) = make()
    c.responses["snapshot"] = [errorEnvelope("snapshot", code: "WINDOW_NOT_FOUND")]
    #expect(await h.snapshot(app: "Finder", surface: nil, timeoutMs: 3000) == nil)
    #expect(c.calls.count == 1)
    let (h2, c2) = make()
    #expect(await h2.snapshot(app: "Finder", surface: .sheet, timeoutMs: 3000) == nil)   // unscripted → PROCESS_FAILED
    #expect(c2.calls[0].contains(["--surface", "sheet"]))
}

@Test func actMapsDispositionsAndRetriesHeadedOnlyWhenNotDelivered() async {
    let (h, c) = make()
    c.responses["click"] = [errorEnvelope("click", code: "ACTION_NOT_SUPPORTED"),
                            okEnvelope("click", data: #"{"disposition":{"delivery":"delivered_verified","retry":"unsafe"}}"#)]
    #expect(await h.act(.click(ref: "@s1:e1", button: .left, count: 1)) == .delivered(verified: true))
    #expect(c.calls.count == 2 && c.calls[0].first == "click" && c.calls[1].first == "--headed")

    let (h2, c2) = make()
    c2.responses["click"] = [errorEnvelope("click", code: "ACTION_FAILED", delivery: "delivered_unverified")]
    #expect(await h2.act(.click(ref: "@s1:e1", button: .left, count: 1)) == .failed("ACTION_FAILED happened"))
    #expect(c2.calls.count == 1)

    let (h3, c3) = make()
    c3.responses["click"] = [errorEnvelope("click", code: "STALE_REF")]
    #expect(await h3.act(.click(ref: "@s1:e1", button: .left, count: 1)) == .elementChanged)
    #expect(c3.calls.count == 1)

    let (h4, c4) = make(headed: false)
    c4.responses["click"] = [errorEnvelope("click", code: "ACTION_NOT_SUPPORTED")]
    #expect(await h4.act(.click(ref: "@s1:e1", button: .left, count: 1)) == .notDelivered("ACTION_NOT_SUPPORTED happened"))
    #expect(c4.calls.count == 1)

    let (h5, c5) = make()
    c5.responses["click"] = [errorEnvelope("click", code: "POLICY_DENIED"), errorEnvelope("click", code: "ACTION_NOT_SUPPORTED")]
    #expect(await h5.act(.click(ref: "@s1:e1", button: .left, count: 1)) == .notDelivered("ACTION_NOT_SUPPORTED happened"))
    #expect(c5.calls.count == 2)

    let (h6, _) = make()
    #expect(await h6.act(.set(ref: "x")) == .failed("unscripted set-value"))   // unknown delivery (process failure) is final
    let (h7, c7) = make()
    c7.responses["set-value"] = [okEnvelope("set-value", data: #"{"disposition":{"delivery":"delivered_unverified","retry":"unsafe"}}"#)]
    #expect(await h7.act(.set(ref: "x")) == .delivered(verified: false))
}

private extension DesktopCommand {
    static func set(ref: String) -> DesktopCommand { .setValue(ref: ref, text: "v") }
}

@Test func actRecordsSurfacesUntilTaken() async {
    let (h, c) = make()
    c.responses["click"] = [okEnvelope("click", data: #"{"surfaces":[{"type":"sheet"}]}"#)]
    _ = await h.act(.click(ref: "@s1:e1", button: .left, count: 1))
    #expect(h.takeOpenSurfaces() == ["sheet"])
    #expect(h.takeOpenSurfaces() == [])
}

@Test func findTriesExactThenContains() async {
    let (h, c) = make()
    c.responses["find"] = [okEnvelope("find", data: #"{"match":null,"snapshot_id":"s1"}"#),
                           okEnvelope("find", data: #"{"match":{"ref_id":"@s1:e5","role":"menuitem","name":"Save As…","path":["menu","menuitem:File"],"states":[]},"snapshot_id":"s1"}"#)]
    let m = await h.find(app: "TextEdit", surface: .menubar, name: "Save As")
    #expect(m?.ref == "@s1:e5" && m?.disabled == false)
    #expect(c.calls.count == 2 && c.calls[0].contains("--exact") && !c.calls[1].contains("--exact"))
    #expect(c.calls[0].contains(["--surface", "menubar"]) && c.calls[0].contains(["--app", "TextEdit"]))
    let (h2, c2) = make()
    c2.responses["find"] = [errorEnvelope("find", code: "WINDOW_NOT_FOUND")]
    #expect(await h2.find(app: nil, surface: .dock, name: "Safari") == nil)
    #expect(c2.calls.count == 2)   // the exact miss is retried without --exact once
}

@Test func readExtractsText() async {
    let (h, c) = make()
    c.responses["get"] = [okEnvelope("get", data: #"{"value":"cats"}"#)]
    #expect(await h.read(.get(ref: "@s1:e1", property: "value")) == "cats")
    c.responses["get"] = [okEnvelope("get", data: #"{"value":42}"#)]
    #expect(await h.read(.get(ref: "@s1:e1", property: "value")) == "42")
    c.responses["clipboard-get"] = [okEnvelope("clipboard-get", data: #"{"type":"text","text":"hi"}"#)]
    #expect(await h.read(.clipboardGet) == "hi")
    c.responses["clipboard-get"] = [okEnvelope("clipboard-get", data: #"{"type":"text","found":false}"#)]
    #expect(await h.read(.clipboardGet) == "")
    c.responses["list-notifications"] = [okEnvelope("list-notifications", data: #"{"notifications":[{"index":1,"app_name":"Mail","title":"New message","body":"Hi there","actions":[]},{"index":2,"app_name":"Slack","title":"ping","body":""}]}"#)]
    #expect(await h.read(.listNotifications) == "Mail: New message — Hi there\nSlack: ping")
    c.responses["get"] = [errorEnvelope("get", code: "STALE_REF")]
    #expect(await h.read(.get(ref: "@s1:e1", property: "value")) == nil)
}

@Test func listWindowsParsesCandidates() async {
    let (h, c) = make()
    c.responses["list-windows"] = [okEnvelope("list-windows", data: #"[{"id":"w-1","title":"A","is_focused":true,"visible":true},{"id":"w-2","title":"B","is_focused":false,"visible":true}]"#)]
    let w = await h.listWindows(app: "Finder")
    #expect(w.map(\.id) == ["w-1", "w-2"] && w[0].isFocused)
    c.responses["list-windows"] = [okEnvelope("list-windows", data: #"{"windows":[{"id":"w-3","title":"C","is_focused":false,"visible":true}]}"#)]
    #expect(await h.listWindows(app: "Finder").map(\.id) == ["w-3"])
}

@Test func sessionFlagIsPassedToEveryCall() async {
    let (h, c) = make()
    c.responses["session"] = [okEnvelope("session", data: #"{"session_id":"abc","name":"n"}"#), okEnvelope("session")]
    c.responses["click"] = [okEnvelope("click")]
    #expect(await h.startSession(name: "n") == "abc")
    _ = await h.act(.click(ref: "@s1:e1", button: .left, count: 1))
    #expect(c.calls[1].starts(with: ["--session", "abc", "click"]))
    await h.endSession("abc")
    #expect(c.calls[2] == ["session", "end", "abc"] && h.session == nil)
}
