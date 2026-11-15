import Testing
import CoreGraphics
import Foundation
import NoHandsCore
@testable import NoHandsMac

final class FakeClipboard: ClipboardAccess, @unchecked Sendable {
    var text: String? = "hi"
    var writes: [String] = []
    func readText() -> String? { text }
    func write(_ text: String) { writes.append(text); self.text = text }
}

private let labels: [Int: UIElementInfo] = [
    1: UIElementInfo(id: 1, frame: CGRect(x: 10, y: 10, width: 20, height: 20), title: "Save", role: "button", ref: "@s1:e1"),
    2: UIElementInfo(id: 2, frame: .zero, title: "Name", role: "textfield", ref: "@s1:e2", value: "cats"),
    3: UIElementInfo(id: 3, frame: CGRect(x: 50, y: 50, width: 10, height: 10), title: "Badge", role: "button"),
]

@MainActor private func makeHarnessed(harness: FakeHarness? = FakeHarness()) -> (ActionExecutor, FakeInput, FakeElements, FakeOverlay, FakeHarness?, FakeClipboard) {
    let i = FakeInput(), e = FakeElements(), o = FakeOverlay(), c = FakeClipboard()
    e.front = "Notes"
    let x = ActionExecutor(input: i, ax: e, overlay: o, config: AppConfig(), frontTimeout: .milliseconds(150),
                           windowTimeout: .milliseconds(300), harness: harness, clipboard: c, menus: FakeMenus([]))
    return (x, i, e, o, harness, c)
}

@MainActor @Test func refClickGoesThroughHarnessAndFallsBackToPointOnlyWhenNotDelivered() async {
    let (x, i, _, _, h, _) = makeHarnessed()
    h!.actResults = [.delivered(verified: true)]
    #expect(await x.execute([.click(.label(1), button: .left, count: 1)], labels: labels) == nil)
    #expect(i.calls.isEmpty && h!.calls == ["act:click @s1:e1"])

    h!.actResults = [.notDelivered("x")]
    #expect(await x.execute([.click(.label(1), button: .right, count: 1)], labels: labels) == nil)
    #expect(i.calls == ["click:20,20"] && h!.calls.last == "act:right-click @s1:e1")

    h!.actResults = [.failed("boom")]
    #expect(await x.execute([.click(.label(1), button: .left, count: 1)], labels: labels) == "boom")
    #expect(i.calls == ["click:20,20"])

    h!.actResults = [.elementChanged]
    #expect(await x.execute([.click(.label(1), button: .left, count: 1)], labels: labels) == ActionExecutor.elementChanged)
}

@MainActor @Test func refClickWithoutFrameUsesHarnessOnly() async {
    let (x, i, _, _, h, _) = makeHarnessed()
    h!.actResults = [.notDelivered("x")]
    #expect(await x.execute([.click(.label(2), button: .left, count: 1)], labels: labels) == "x")
    #expect(i.calls.isEmpty)
}

@MainActor @Test func labelWithoutRefUsesCGEvent() async {
    let (x, i, _, _, h, _) = makeHarnessed()
    #expect(await x.execute([.click(.label(3), button: .left, count: 1)], labels: labels) == nil)
    #expect(i.calls == ["click:55,55"] && h!.calls.isEmpty)
}

@MainActor @Test func setValueWithoutRefClicksSelectsAllAndTypes() async {
    let (x, i, _, _, _, _) = makeHarnessed(harness: nil)
    #expect(await x.execute([.setValue(.label(3), "cats")], labels: labels) == nil)
    #expect(i.calls == ["click:55,55", "press", "type:cats"])
    #expect(await x.execute([.clearField(.label(3))], labels: labels) == nil)
    #expect(i.calls.suffix(3) == ["click:55,55", "press", "press"])
    #expect(await x.execute([.typeInto(.label(3), "x")], labels: labels) == nil)
    #expect(i.calls.suffix(2) == ["click:55,55", "type:x"])
    #expect(await x.execute([.selectOption(.label(3), "Blue")], labels: labels) == "needs agent-desktop")
    #expect(await x.execute([.setValue(.label(2), "cats")], labels: labels) == "no label 2 on screen")
    #expect(await x.execute([.setValue(.label(9), "cats")], labels: labels) == "no label 9")
}

@MainActor @Test func elementActionsViaHarnessUseTheRef() async {
    let (x, i, _, o, h, _) = makeHarnessed()
    o.showLabels([:])
    let actions: [Action] = [
        .setValue(.label(2), "dogs"), .typeInto(.label(2), "x"), .clearField(.label(2)), .selectOption(.label(2), "Blue"),
        .setChecked(.label(1), true), .setChecked(.label(1), false), .setChecked(.label(1), nil),
        .setExpanded(.label(1), true), .setExpanded(.label(1), false), .focusElement(.label(1)), .scrollTo(.label(1)),
        .scrollIn(.label(1), .down, amount: 4)]
    #expect(await x.execute(actions, labels: labels) == nil)
    #expect(h!.calls == ["act:set-value @s1:e2 dogs", "act:type @s1:e2 x", "act:clear @s1:e2", "act:select @s1:e2 Blue",
                         "act:check @s1:e1", "act:uncheck @s1:e1", "act:toggle @s1:e1", "act:expand @s1:e1",
                         "act:collapse @s1:e1", "act:focus @s1:e1", "act:scroll-to @s1:e1",
                         "act:scroll @s1:e1 --direction down --amount 4"])
    #expect(i.calls.isEmpty && o.state == .none)
}

@MainActor @Test func namedTargetsResolveThroughFindThenNative() async {
    let (x, _, e, _, h, _) = makeHarnessed()
    h!.findResult = DesktopFindMatch(ref: "@s1:e7", role: "button", name: "Send", path: [], disabled: false)
    #expect(await x.execute([.setChecked(.named("Send"), true)]) == nil)
    #expect(h!.calls == ["find:window:Notes:Send", "act:check @s1:e7"])
    h!.findResult = nil
    e.elements = [UIElementInfo(id: 1, frame: CGRect(x: 100, y: 100, width: 80, height: 30), title: "Later", role: "AXButton")]
    #expect(await x.execute([.setChecked(.named("Later"), true)]) == nil)   // native element, click fallback
    #expect(await x.execute([.setChecked(.named("Nope"), true)]) == "no element named 'Nope'")
}

@MainActor @Test func menuItemFindsLastSegmentThenClicksAndRefusesDisabled() async {
    let (x, _, _, _, h, _) = makeHarnessed()
    h!.findResult = DesktopFindMatch(ref: "@s1:e5", role: "menuitem", name: "Save As…", path: ["menu", "menuitem:File"], disabled: false)
    #expect(await x.execute([.menuItem("File > Save As…")]) == nil)
    #expect(h!.calls == ["find:menubar:Notes:Save As…", "act:click @s1:e5"])
    h!.findResult = DesktopFindMatch(ref: "@s1:e5", role: "menuitem", name: "Paste", path: [], disabled: true)
    #expect(await x.execute([.menuItem("Paste")]) == "menu item Paste is disabled")
    h!.findResult = nil
    #expect(await x.execute([.menuItem("Nothing")]) == "no menu item called Nothing")
    let (native, _, _, _, _, _) = makeHarnessed(harness: nil)
    #expect(await native.execute([.menuItem("Paste")]) == "no menu item called Paste")
}

@MainActor @Test func clickInDockFindsWithoutApp() async {
    let (x, _, _, _, h, _) = makeHarnessed()
    h!.findResult = DesktopFindMatch(ref: "@s1:e3", role: "button", name: "Safari", path: [], disabled: false)
    #expect(await x.execute([.clickIn(.dock, name: "Safari")]) == nil)
    #expect(h!.calls == ["find:dock:-:Safari", "act:click @s1:e3"])
    #expect(await x.execute([.clickIn(.sheet, name: "Don't Save")]) == nil)
    #expect(h!.calls[2] == "find:sheet:Notes:Don't Save")
}

@MainActor @Test func readsProduceReadingsAndNoInput() async {
    let (x, i, _, _, h, _) = makeHarnessed()
    h!.readResult = "cats"
    #expect(await x.execute([.readValue(.label(2)), .readClipboard], labels: labels) == nil)
    #expect(h!.calls == ["read:get @s1:e2 --property value", "read:clipboard-get"])
    #expect(x.takeReadings() == ["Name: cats", "clipboard: cats"] && x.takeReadings().isEmpty && i.calls.isEmpty)
    h!.readResult = "Mail: hi"
    #expect(await x.execute([.readNotifications]) == nil)
    #expect(x.takeReadings() == ["notifications: Mail: hi"])
    h!.readResult = nil
    #expect(await x.execute([.readValue(.label(2))], labels: labels) == "couldn't read")
    #expect(await x.execute([.readClipboard]) == "couldn't read")
    #expect(x.takeReadings().isEmpty)
}

@MainActor @Test func nativeClipboardAndReadValueFallbacks() async {
    let (x, _, _, _, _, c) = makeHarnessed(harness: nil)
    #expect(await x.execute([.readClipboard, .clipboardSet("new"), .readValue(.label(2))], labels: labels) == nil)
    #expect(c.writes == ["new"] && x.takeReadings() == ["clipboard: hi", "Name: cats"])
    #expect(await x.execute([.readNotifications]) == "needs agent-desktop")
    #expect(await x.execute([.dismissNotifications(app: nil)]) == "needs agent-desktop")
}

@MainActor @Test func waitForTimeoutIsAStepFailure() async {
    let (x, _, _, _, h, _) = makeHarnessed()
    h!.actResults = [.delivered(verified: true)]
    #expect(await x.execute([.waitFor(.text("Done"), timeoutMs: 1000)]) == nil)
    #expect(h!.calls == ["act:wait --text Done --app Notes --timeout 1000"])
    h!.actResults = [.failed("TIMEOUT happened")]
    #expect(await x.execute([.waitFor(.event(.windowOpened), timeoutMs: 1000)]) == "wait timed out")
    #expect(await x.execute([.waitFor(.element(.label(1), predicate: "actionable"), timeoutMs: 1000)], labels: labels) == "wait timed out")
    #expect(h!.calls.last == "act:wait --element @s1:e1 --predicate actionable --timeout 1000")
    let (native, _, _, _, _, _) = makeHarnessed(harness: nil)
    let t = ContinuousClock.now
    #expect(await native.execute([.waitFor(.menu, timeoutMs: 100)]) == nil)
    #expect(t.duration(to: .now) >= .milliseconds(90))
}

@MainActor @Test func closeAppAndWindowOpsViaHarnessAndNative() async {
    let (x, i, e, _, h, _) = makeHarnessed()
    e.apps = ["Safari"]
    #expect(await x.execute([.closeApp("Safari"), .windowAction(.minimize, app: "Safari", title: nil), .windowAction(.focus, app: "Safari", title: "GitHub"),
                             .clipboardSet("x"), .dismissNotifications(app: "Mail")]) == nil)
    #expect(h!.calls == ["act:close-app Safari", "act:minimize --app Safari", "act:focus-window --app Safari --title GitHub",
                         "act:clipboard-set x", "act:--headed dismiss-all-notifications --app Mail"])
    #expect(i.calls.isEmpty)
    let (n, ni, ne, _, _, _) = makeHarnessed(harness: nil)
    ne.apps = ["Safari"]
    #expect(await n.execute([.closeApp("Safari")]) == nil)
    #expect(ni.calls == ["press"])
    #expect(await n.execute([.windowAction(.minimize, app: "Safari", title: nil)]) == nil && ni.calls == ["press", "press"])
    #expect(await n.execute([.windowAction(.focus, app: "Safari", title: nil)]) == nil && ni.calls.count == 2)
    #expect(await n.execute([.windowAction(.maximize, app: nil, title: nil)]) == "needs agent-desktop")
    #expect(await n.execute([.closeApp("Nope")]) == "no app named Nope")
}

@MainActor @Test func dragUsesHarnessWithRefsAndPointsOrNativeMouse() async {
    let (x, i, _, _, h, _) = makeHarnessed()
    #expect(await x.execute([.drag(from: .label(1), to: .point(CGPoint(x: 300, y: 400)))], labels: labels) == nil)
    #expect(h!.calls == ["act:--headed drag --from @s1:e1 --to-xy 300,400"] && i.calls.isEmpty)
    #expect(await x.execute([.drag(from: .point(CGPoint(x: 1, y: 2)), to: .label(3))], labels: labels) == nil)
    #expect(h!.calls.last == "act:--headed drag --from-xy 1,2 --to-xy 55,55")
    let (n, ni, _, _, _, _) = makeHarnessed(harness: nil)
    #expect(await n.execute([.drag(from: .point(CGPoint(x: 1, y: 2)), to: .label(3))], labels: labels) == nil)
    #expect(ni.calls == ["move:1,2", "down", "move:55,55", "up"])
}

@MainActor @Test func mediaPlayingWaitIsPolledByNoHandsNotTheHarness() async {
    func executor(_ e: FakeElements, _ h: FakeHarness, _ o: FakeOverlay) -> ActionExecutor {
        ActionExecutor(input: FakeInput(), ax: e, overlay: o, config: AppConfig(), harness: h, audio: FakeAudio(),
                       mediaPoll: .milliseconds(5))
    }
    let e = FakeElements(), h = FakeHarness(), o = FakeOverlay()
    e.front = "Safari"
    e.elements = [UIElementInfo(id: 1, frame: .zero, title: "Play", role: "AXButton")]
    e.onWalk = { [unowned e] in
        if e.walks == 3 { e.elements = [UIElementInfo(id: 1, frame: .zero, title: "Pause (k)", role: "AXButton")] }
    }
    let x = executor(e, h, o)
    #expect(await x.execute([.waitFor(.mediaPlaying, timeoutMs: 2000)]) == nil)
    #expect(e.walks == 3)

    e.elements = [UIElementInfo(id: 1, frame: .zero, title: "Play", role: "AXButton")]
    e.onWalk = nil
    #expect(await x.execute([.waitFor(.mediaPlaying, timeoutMs: 40)]) == "wait timed out")
    #expect(await x.execute([.checkMedia]) == nil)
    #expect(x.takeReadings() == ["Media: paused"])
    #expect(h.calls.isEmpty)

    // Cancelling a long wait ends it at once with `cancelled`, not after its timeout.
    let waiting = Task { await x.execute([.waitFor(.mediaPlaying, timeoutMs: 30000)]) }
    try? await Task.sleep(for: .milliseconds(30))
    waiting.cancel()
    #expect(await waiting.value == ActionExecutor.cancelled)
}

@MainActor @Test func ordinalNameClicksTheShownResultThroughTheHarness() async {
    let (x, i, _, _, h, _) = makeHarnessed()
    h!.actResults = [.delivered(verified: true)]
    let shown: [Int: UIElementInfo] = [
        1: UIElementInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 50, height: 20), title: "Home", role: "link", ref: "@s1:e9"),
        2: UIElementInfo(id: 2, frame: CGRect(x: 0, y: 50, width: 50, height: 20), title: "Raptors vs Celtics Full Game", role: "link", ref: "@s1:e7"),
    ]
    #expect(await x.execute([.click(.element(named: "first video"), button: .left, count: 1)], labels: shown) == nil)
    #expect(i.calls.isEmpty && h!.calls == ["act:click @s1:e7"])
    #expect(await x.execute([.click(.element(named: "tenth video"), button: .left, count: 1)], labels: shown)
        == "no element named 'tenth video'; say its label number from the list")
}
