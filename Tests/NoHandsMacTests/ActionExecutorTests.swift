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
    return (ActionExecutor(input: i, ax: e, overlay: o, config: AppConfig()), i, e, o)
}

@MainActor @Test func stopsAtFirstFailureAndShowsHUD() {
    let (x, i, _, o) = make()
    let r = x.execute([.typeText("a"), .zoomGrid(3), .typeText("b")])
    #expect(r == "no grid shown")
    #expect(i.calls == ["type:a"])
    #expect(o.huds == ["no grid shown"])
}

@MainActor @Test func clickOnNumberedTargetHidesOverlay() {
    let (x, i, _, o) = make()
    #expect(x.execute([.showGrid, .click(.numbered(1), button: .left, count: 1)]) == nil)
    #expect(i.calls == ["click:50,50"])
    #expect(o.state == .none)
}

@MainActor @Test func clickOnLabelHidesOverlayAndNonOverlayClickKeepsIt() {
    let (x, i, e, o) = make()
    e.elements = [UIElementInfo(id: 1, frame: CGRect(x: 100, y: 100, width: 80, height: 30), title: "Save", role: "AXButton")]
    #expect(x.execute([.showLabels, .click(.cursor, button: .left, count: 1)]) == nil)
    #expect(o.state != .none)
    #expect(x.execute([.click(.numbered(1), button: .left, count: 2)]) == nil)
    #expect(i.calls == ["click:10,20", "click:140,115"])
    #expect(o.state == .none)
}

@MainActor @Test func elementClickUsesFreshElements() {
    let (x, i, e, _) = make()
    e.elements = [UIElementInfo(id: 1, frame: CGRect(x: 100, y: 100, width: 80, height: 30), title: "Save", role: "AXButton")]
    #expect(x.execute([.click(.element(named: "save"), button: .left, count: 1)]) == nil)
    #expect(x.execute([.click(.element(named: "quit"), button: .left, count: 1)]) == "no element named 'quit'")
    #expect(i.calls == ["click:140,115"])
}

@MainActor @Test func zoomGridRules() {
    let (x, _, _, o) = make()
    #expect(x.execute([.zoomGrid(1)]) == "no grid shown")
    #expect(x.execute([.showGrid, .zoomGrid(500)]) == "no cell 500")
    #expect(x.execute([.zoomGrid(1)]) == nil)
    if case .grid(let g) = o.state { #expect(g.bounds.width == 100) } else { Issue.record("expected grid") }
}

@MainActor @Test func openAppFailure() {
    let (x, _, e, _) = make()
    e.apps = ["Safari"]
    #expect(x.execute([.openApp("Safari")]) == nil)
    #expect(x.execute([.openApp("Nope")]) == "no app named Nope")
}

@MainActor @Test func typeTextCap() {
    let (x, i, _, _) = make()
    #expect(x.execute([.typeText(String(repeating: "a", count: 2001))]) == "text too long")
    #expect(i.calls.isEmpty)
    #expect(x.execute([.typeText(String(repeating: "a", count: 2000))]) == nil)
    #expect(i.calls.count == 1)
}

@MainActor @Test func modeChangeCallbackAndIgnore() {
    let (x, i, _, _) = make()
    var modes: [Mode] = []
    x.onModeChange = { modes.append($0) }
    #expect(x.execute([.setMode(.sleep), .ignore]) == nil)
    #expect(modes == [.sleep])
    #expect(i.calls.isEmpty)
}

@MainActor @Test func inputErrorBecomesFailure() {
    let (x, i, _, o) = make()
    i.throwOnType = true
    #expect(x.execute([.typeText("hi"), .scroll(.down, amount: 1)]) != nil)
    #expect(i.calls.isEmpty)
    #expect(o.huds.count == 1)
}

@MainActor @Test func relativeMoveAndMouseButtonsUseCursor() {
    let (x, i, _, _) = make()
    #expect(x.execute([.moveCursor(.relative(dx: 5, dy: -5)), .pressMouse(.left), .releaseMouse(.left), .scroll(.up, amount: 2)]) == nil)
    #expect(i.calls == ["move:15,15", "down", "up", "scroll"])
}
