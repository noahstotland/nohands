import Testing
import CoreGraphics
import Foundation
import NoHandsCore
@testable import NoHandsMac

private struct Boom: Error {}

private final class FakeInput: InputSynthesizing, @unchecked Sendable {
    var calls: [String] = []
    var location = CGPoint(x: 10, y: 20)
    var throwOnType = false
    func type(_ text: String) throws { if throwOnType { throw Boom() }; calls.append("type:\(text)") }
    func press(_ chord: KeyChord) throws { calls.append("press") }
    func moveMouse(to point: CGPoint) throws { calls.append("move:\(Int(point.x)),\(Int(point.y))") }
    func click(at point: CGPoint, button: MouseButton, count: Int) throws { calls.append("click:\(Int(point.x)),\(Int(point.y))") }
    func mouseDown(_ button: MouseButton, at point: CGPoint) throws { calls.append("down") }
    func mouseUp(_ button: MouseButton, at point: CGPoint) throws { calls.append("up") }
    func scroll(_ direction: Direction, lines: Int) throws { calls.append("scroll") }
    func currentMouseLocation() -> CGPoint { location }
}

private final class FakeElements: ElementProviding, @unchecked Sendable {
    var elements: [UIElementInfo] = []
    var apps: Set<String> = []
    var front: String? = nil
    func frontmostAppName() -> String? { front }
    func actionableElements() -> [UIElementInfo] { elements }
    func screenRectsCG() -> [CGRect] { [CGRect(x: 0, y: 0, width: 1000, height: 800)] }
    func activate(appNamed: String) -> Bool { apps.contains(appNamed) }
}

@MainActor private final class FakeOverlay: OverlayPresenting {
    var state: OverlayState = .none
    var huds: [String] = []
    func showGrid(_ grid: GridModel) { state = .grid(grid) }
    func showLabels(_ labels: [Int: UIElementInfo]) { state = .labels(labels) }
    func hide() { state = .none }
    func showHUD(_ text: String, duration: Duration) { huds.append(text) }
    func screenBoundsCG(containing point: CGPoint) -> CGRect { CGRect(x: 0, y: 0, width: 1000, height: 800) }
}

@MainActor private func make() -> (ActionExecutor, FakeInput, FakeElements, FakeOverlay) {
    let i = FakeInput(), e = FakeElements(), o = FakeOverlay()
    return (ActionExecutor(input: i, ax: e, overlay: o, config: AppConfig(), frontTimeout: .milliseconds(150)), i, e, o)
}

@MainActor @Test func stopsAtFirstFailureAndShowsHUD() async {
    let (x, i, _, o) = make()
    let r = await x.execute([.typeText("a"), .zoomGrid(3), .typeText("b")])
    #expect(r == "no grid shown")
    #expect(i.calls == ["type:a"])
    #expect(o.huds == ["no grid shown"])
}

@MainActor @Test func clickOnNumberedTargetHidesOverlay() async {
    let (x, i, _, o) = make()
    #expect(await x.execute([.showGrid, .click(.numbered(1), button: .left, count: 1)]) == nil)
    #expect(i.calls == ["click:50,50"])
    #expect(o.state == .none)
}

@MainActor @Test func clickOnLabelHidesOverlayAndNonOverlayClickKeepsIt() async {
    let (x, i, e, o) = make()
    e.elements = [UIElementInfo(id: 1, frame: CGRect(x: 100, y: 100, width: 80, height: 30), title: "Save", role: "AXButton")]
    #expect(await x.execute([.showLabels, .click(.cursor, button: .left, count: 1)]) == nil)
    #expect(o.state != .none)
    #expect(await x.execute([.click(.numbered(1), button: .left, count: 2)]) == nil)
    #expect(i.calls == ["click:10,20", "click:140,115"])
    #expect(o.state == .none)
}

@MainActor @Test func elementClickUsesFreshElements() async {
    let (x, i, e, _) = make()
    e.elements = [UIElementInfo(id: 1, frame: CGRect(x: 100, y: 100, width: 80, height: 30), title: "Save", role: "AXButton")]
    #expect(await x.execute([.click(.element(named: "save"), button: .left, count: 1)]) == nil)
    #expect(await x.execute([.click(.element(named: "quit"), button: .left, count: 1)]) == "no element named 'quit'")
    #expect(i.calls == ["click:140,115"])
}

@MainActor @Test func zoomGridRules() async {
    let (x, _, _, o) = make()
    #expect(await x.execute([.zoomGrid(1)]) == "no grid shown")
    #expect(await x.execute([.showGrid, .zoomGrid(500)]) == "no cell 500")
    #expect(await x.execute([.zoomGrid(1)]) == nil)
    if case .grid(let g) = o.state { #expect(g.bounds.width == 100) } else { Issue.record("expected grid") }
}

@MainActor @Test func openAppFailure() async {
    let (x, _, e, _) = make()
    e.apps = ["Safari"]
    e.front = "Safari"
    #expect(await x.execute([.openApp("Safari")]) == nil)
    #expect(await x.execute([.openApp("Nope")]) == "no app named Nope")
}

@MainActor @Test func typeTextCap() async {
    let (x, i, _, _) = make()
    #expect(await x.execute([.typeText(String(repeating: "a", count: 2001))]) == "text too long")
    #expect(i.calls.isEmpty)
    #expect(await x.execute([.typeText(String(repeating: "a", count: 2000))]) == nil)
    #expect(i.calls.count == 1)
}

@MainActor @Test func modeChangeCallbackAndIgnore() async {
    let (x, i, _, _) = make()
    var modes: [Mode] = []
    x.onModeChange = { modes.append($0) }
    #expect(await x.execute([.setMode(.sleep), .ignore]) == nil)
    #expect(modes == [.sleep])
    #expect(i.calls.isEmpty)
}

@MainActor @Test func inputErrorBecomesFailure() async {
    let (x, i, _, o) = make()
    i.throwOnType = true
    #expect(await x.execute([.typeText("hi"), .scroll(.down, amount: 1)]) != nil)
    #expect(i.calls.isEmpty)
    #expect(o.huds.count == 1)
}

@MainActor @Test func relativeMoveAndMouseButtonsUseCursor() async {
    let (x, i, _, _) = make()
    #expect(await x.execute([.moveCursor(.relative(dx: 5, dy: -5)), .pressMouse(.left), .releaseMouse(.left), .scroll(.up, amount: 2)]) == nil)
    #expect(i.calls == ["move:15,15", "down", "up", "scroll"])
}

@MainActor @Test func failureReleasesHeldButton() async {
    let (x, i, _, _) = make()
    let r = await x.execute([.pressMouse(.left), .moveCursor(.numbered(1))])
    #expect(r == "no grid or labels shown")
    #expect(i.calls == ["down", "up"])
}

@MainActor @Test func releasedButtonIsNotReleasedAgain() async {
    let (x, i, _, _) = make()
    _ = await x.execute([.pressMouse(.left), .releaseMouse(.left), .zoomGrid(1)])
    #expect(i.calls == ["down", "up"])
}

@MainActor @Test func clickCountAndScrollBounds() async {
    let (x, i, _, _) = make()
    #expect(await x.execute([.click(.cursor, button: .left, count: 0)]) == "bad click count")
    #expect(await x.execute([.click(.cursor, button: .left, count: 4)]) == "bad click count")
    #expect(await x.execute([.click(.cursor, button: .left, count: 3)]) == nil)
    #expect(await x.execute([.scroll(.down, amount: 0)]) == "bad scroll amount")
    #expect(await x.execute([.scroll(.down, amount: 101)]) == "bad scroll amount")
    #expect(await x.execute([.scroll(.down, amount: 100)]) == nil)
    #expect(i.calls == ["click:10,20", "scroll"])
}

@MainActor @Test func offScreenPointsRejected() async {
    let (x, i, e, _) = make()
    #expect(await x.execute([.click(.point(CGPoint(x: 5000, y: 5)), button: .left, count: 1)]) == "point off screen")
    #expect(await x.execute([.moveCursor(.point(CGPoint(x: -1, y: 5)))]) == "point off screen")
    #expect(await x.execute([.moveCursor(.relative(dx: 2000, dy: 0))]) == "point off screen")
    #expect(await x.execute([.moveCursor(.point(CGPoint(x: 999, y: 799)))]) == nil)
    #expect(i.calls == ["move:999,799"])
    _ = e
}

@MainActor @Test func emptyScreenListSkipsBoundsCheck() async {
    let i = FakeInput(), o = FakeOverlay()
    final class NoScreens: ElementProviding, @unchecked Sendable {
        func actionableElements() -> [UIElementInfo] { [] }
        func screenRectsCG() -> [CGRect] { [] }
        func activate(appNamed: String) -> Bool { true }
        func frontmostAppName() -> String? { nil }
    }
    let x = ActionExecutor(input: i, ax: NoScreens(), overlay: o, config: AppConfig())
    #expect(await x.execute([.moveCursor(.point(CGPoint(x: 99999, y: 5)))]) == nil)
}

@MainActor @Test func openAppWaitsForFrontAndFailsIfMoreActions() async {
    let (x, i, e, _) = make()
    e.apps = ["Safari"]
    // never comes to front, more actions follow -> fail, later action not run
    #expect(await x.execute([.openApp("Safari"), .typeText("x")]) == "app did not come to front")
    #expect(i.calls.isEmpty)
    // timeout but last action -> continues
    #expect(await x.execute([.openApp("Safari")]) == nil)
    // in front -> continues with further actions
    e.front = "Safari"
    #expect(await x.execute([.openApp("Safari"), .typeText("x")]) == nil)
    #expect(i.calls == ["type:x"])
}

@MainActor @Test func inputActionsHideStaleOverlay() async {
    for a: Action in [.typeText("a"), .pressKey(KeyChord(.a)), .scroll(.down, amount: 1)] {
        let (x, _, _, o) = make()
        _ = await x.execute([.showGrid])
        #expect(o.state != .none)
        _ = await x.execute([a])
        #expect(o.state == .none)
    }
    let (x, _, e, o) = make()
    e.apps = ["Safari"]; e.front = "Safari"
    _ = await x.execute([.showGrid, .openApp("Safari")])
    #expect(o.state == .none)
}
