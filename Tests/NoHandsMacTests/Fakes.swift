import Testing
import CoreGraphics
import Foundation
import NoHandsCore
@testable import NoHandsMac

struct Boom: Error {}

final class FakeInput: InputSynthesizing, @unchecked Sendable {
    var calls: [String] = []
    var location: CGPoint? = CGPoint(x: 10, y: 20)
    var throwOnType = false
    func type(_ text: String) throws { if throwOnType { throw Boom() }; calls.append("type:\(text)") }
    func press(_ chord: KeyChord) throws { calls.append("press") }
    func moveMouse(to point: CGPoint) throws { calls.append("move:\(Int(point.x)),\(Int(point.y))") }
    func click(at point: CGPoint, button: MouseButton, count: Int) throws { calls.append("click:\(Int(point.x)),\(Int(point.y))") }
    func mouseDown(_ button: MouseButton, at point: CGPoint) throws { calls.append("down") }
    func mouseUp(_ button: MouseButton, at point: CGPoint) throws { calls.append("up") }
    func scroll(_ direction: Direction, lines: Int) throws { calls.append("scroll") }
    func currentMouseLocation() -> CGPoint? { location }
    func releaseAll() { calls.append("releaseAll") }
}

final class FakeElements: ElementProviding, @unchecked Sendable {
    var elements: [UIElementInfo] = []
    var apps: Set<String> = []
    var front: String? = nil
    var windowTitle: String? = nil
    var url: String? = nil
    /// Set to report that the next walk freshly exposed a Chromium page tree (cleared when read).
    var exposeOnNextWalk = false
    private var justExposed = false
    /// Number of `actionableElements()` walks.
    var walks = 0
    /// Simulated walk time (blocks the calling thread like a real AX walk) and where each walk ran.
    var walkDelay: TimeInterval = 0
    var walkedOnMainThread: [Bool] = []
    func focusedWindowTitle() -> String? { windowTitle }
    func webURL() -> String? { url }
    func frontmostAppName() -> String? { front }
    func actionableElements() -> [UIElementInfo] {
        walks += 1
        walkedOnMainThread.append(Thread.isMainThread)
        if walkDelay > 0 { Thread.sleep(forTimeInterval: walkDelay) }
        if exposeOnNextWalk { exposeOnNextWalk = false; justExposed = true }
        return elements
    }
    func didJustExpose() -> Bool { defer { justExposed = false }; return justExposed }
    func screenRectsCG() -> [CGRect] { [CGRect(x: 0, y: 0, width: 1000, height: 800)] }
    func activate(appNamed: String) -> Bool { apps.contains(appNamed) }
}

@MainActor final class FakeOverlay: OverlayPresenting {
    var state: OverlayState = .none
    var huds: [String] = []
    func showGrid(_ grid: GridModel) { state = .grid(grid) }
    func showLabels(_ labels: [Int: UIElementInfo]) { state = .labels(labels) }
    func hide() { state = .none }
    func showHUD(_ text: String, duration: Duration) { huds.append(text) }
    func screenBoundsCG(containing point: CGPoint) -> CGRect { CGRect(x: 0, y: 0, width: 1000, height: 800) }
}

@MainActor func make() -> (ActionExecutor, FakeInput, FakeElements, FakeOverlay) {
    let i = FakeInput(), e = FakeElements(), o = FakeOverlay()
    return (ActionExecutor(input: i, ax: e, overlay: o, config: AppConfig(), frontTimeout: .milliseconds(150)), i, e, o)
}

