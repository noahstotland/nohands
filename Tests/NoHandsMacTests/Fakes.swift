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
    /// Called on every walk (e.g. to advance a fake clock), and where each walk ran.
    var onWalk: (@Sendable () -> Void)?
    var walkedOnMainThread: [Bool] = []
    /// Screen rects passed in by the caller of `actionableElements(screens:)` (nil entry: read here).
    var walkScreens: [[CGRect]?] = []
    func focusedWindowTitle() -> String? { windowTitle }
    func webURL() -> String? { url }
    func frontmostAppName() -> String? { front }
    func actionableElements() -> [UIElementInfo] { walk(screens: nil) }
    func actionableElements(screens: [CGRect]) -> [UIElementInfo] { walk(screens: screens) }
    private func walk(screens: [CGRect]?) -> [UIElementInfo] {
        walks += 1
        walkedOnMainThread.append(Thread.isMainThread)
        walkScreens.append(screens)
        onWalk?()
        if exposeOnNextWalk { exposeOnNextWalk = false; justExposed = true }
        return elements
    }
    func didJustExpose() -> Bool { defer { justExposed = false }; return justExposed }
    func screenRectsCG() -> [CGRect] { [CGRect(x: 0, y: 0, width: 1000, height: 800)] }
    func activate(appNamed: String) -> Bool { apps.contains(appNamed) }

    /// URL opens: the default browser's name, URLs opened, and whether the frontmost app has a window.
    var defaultBrowser: String? = "Safari"
    var opened: [(url: URL, app: String?)] = []
    var hasWindow = true
    /// When > 0, `frontmostHasWindow()` reports false that many times, then true.
    var windowAppearsAfterChecks = 0
    func open(url: URL, appNamed: String?) -> String? {
        if let appNamed, !apps.contains(appNamed) { return nil }
        opened.append((url, appNamed))
        return appNamed ?? defaultBrowser
    }
    func frontmostHasWindow() -> Bool {
        if windowAppearsAfterChecks > 0 { windowAppearsAfterChecks -= 1; return false }
        return hasWindow
    }

    /// Window geometry: the focused window's frame (nil = no window), frames set, visible screen areas, and
    /// whether the app accepts the move.
    var windowFrame: CGRect? = CGRect(x: 100, y: 100, width: 400, height: 300)
    var placed: [CGRect] = []
    var visibleScreens: [CGRect] = [CGRect(x: 0, y: 25, width: 1000, height: 775)]
    var acceptsMove = true
    func focusedWindowFrame() -> CGRect? { windowFrame }
    func setFocusedWindowFrame(_ frame: CGRect) -> Bool {
        guard windowFrame != nil, acceptsMove else { return false }
        placed.append(frame)
        windowFrame = frame
        return true
    }
    func visibleScreenRectsCG() -> [CGRect] { visibleScreens }
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
    return (ActionExecutor(input: i, ax: e, overlay: o, config: AppConfig(), frontTimeout: .milliseconds(150),
                           windowTimeout: .milliseconds(300)), i, e, o)
}


/// A manually advanced clock for `TaskRunner(now:)`.
final class FakeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = ContinuousClock.now
    func now() -> ContinuousClock.Instant { lock.withLock { current } }
    func advance(_ d: Duration) { lock.withLock { current = current.advanced(by: d) } }
}
