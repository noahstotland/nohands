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

final class FakeAudio: AudioOutputProbing, @unchecked Sendable {
    var playing = false
    var asked = 0
    func isPlaying() -> Bool { asked += 1; return playing }
}

final class FakeElements: ElementProviding, @unchecked Sendable {
    var elements: [UIElementInfo] = []
    var apps: Set<String> = []
    var front: String? = nil
    var windowTitle: String? = nil
    var url: String? = nil
    /// The frontmost window's search box, when it has one.
    var searchBox: CGRect? = nil
    var isBrowser = false
    /// Set to report that the next walk freshly exposed a Chromium page tree (cleared when read).
    var exposeOnNextWalk = false
    func searchFieldFrame() -> CGRect? { searchBox }
    /// The browser's windows and tabs (nil: the front app is not a browser) and the tab and window ids closed or selected.
    var browser: [BrowserWindow]?
    var closedTabs: [String] = []
    var closedWindows: [String] = []
    var selectedTabs: [String] = []
    /// The app the windows were read from (nil: the front app's name).
    var browserApp: String?
    func browserWindows() -> (app: String, windows: [BrowserWindow])? { browser.map { (browserApp ?? front ?? "Browser", $0) } }
    /// Whether a tab is in the front app's focused window.
    var tabInFrontWindow = true
    func browserTabIsInFrontWindow(id: String) -> Bool { tabInFrontWindow }
    /// A tab with no close button of its own, and whether selecting a tab really makes it the selected one.
    var tabHasNoCloseButton = false
    var selectingWorks = true
    func closeBrowserTab(id: String) -> BrowserActionResult {
        if tabHasNoCloseButton { return .noControl }
        closedTabs.append(id); return .done
    }
    func browserTabIsSelected(id: String) -> Bool { selectingWorks && selectedTabs.last == id }
    func closeBrowserWindow(id: String) -> BrowserActionResult { closedWindows.append(id); return .done }
    func selectBrowserTab(id: String) -> BrowserActionResult { selectedTabs.append(id); return .done }
    func frontmostIsBrowser() -> Bool { isBrowser }
    private var justExposed = false
    /// Number of `actionableElements()` walks.
    var walks = 0
    /// When non-empty, each walk returns the next list (the last repeats) instead of `elements`.
    var walkLists: [[UIElementInfo]] = []
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
        return walkLists.isEmpty ? elements : walkLists[min(walks - 1, walkLists.count - 1)]
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
    /// Notices (`showHUD`), in order.
    var huds: [String] = []
    /// Every prompt report, in order.
    var reports: [(id: Int, text: String, status: PromptStatus)] = []
    /// The status cell of every report, in order (what the user reads).
    var statuses: [String] { reports.map { $0.status.text } }
    func showGrid(_ grid: GridModel) { state = .grid(grid) }
    func showLabels(_ labels: [Int: UIElementInfo]) { state = .labels(labels) }
    func hide() { state = .none }
    func showHUD(_ text: String, duration: Duration) { huds.append(text) }
    func report(_ id: Int, text: String, status: PromptStatus) { reports.append((id, text, status)) }
    /// Every trail report, in order.
    var trails: [(id: Int, trail: TaskTrail)] = []
    func report(_ id: Int, trail: TaskTrail) { trails.append((id, trail)) }
    func screenBoundsCG(containing point: CGPoint) -> CGRect { CGRect(x: 0, y: 0, width: 1000, height: 800) }
}

@MainActor func make() -> (ActionExecutor, FakeInput, FakeElements, FakeOverlay) {
    let i = FakeInput(), e = FakeElements(), o = FakeOverlay()
    return (ActionExecutor(input: i, ax: e, overlay: o, config: AppConfig(), frontTimeout: .milliseconds(150),
                           windowTimeout: .milliseconds(300), audio: FakeAudio()), i, e, o)
}


/// A `DesktopCommandRunning` that answers from scripted envelopes keyed by subcommand name (consumed in order; the
/// last one repeats) and records every argv.
final class ScriptedClient: DesktopCommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    var responses: [String: [DesktopEnvelope]] = [:]
    var calls: [[String]] = []
    var environments: [[String: String]] = []

    func run(_ argv: [String], deadline: Duration?, isObservation: Bool, environment: [String: String]) async -> DesktopEnvelope {
        lock.withLock {
            calls.append(argv)
            environments.append(environment)
            let name = argv.first { !$0.hasPrefix("-") } ?? ""
            guard var list = responses[name], !list.isEmpty else {
                return .processFailure(command: name, message: "unscripted \(name)", observation: isObservation)
            }
            let e = list.removeFirst()
            if !list.isEmpty { responses[name] = list }
            return e
        }
    }
}

func envelope(_ json: String) -> DesktopEnvelope { DesktopEnvelope.decode(Data(json.utf8))! }
func okEnvelope(_ command: String, data: String = "{}") -> DesktopEnvelope {
    envelope(#"{"version":"2.6","ok":true,"command":"\#(command)","data":\#(data)}"#)
}
func errorEnvelope(_ command: String, code: String, delivery: String = "not_delivered", details: String = "{}") -> DesktopEnvelope {
    envelope(#"{"version":"2.6","ok":false,"command":"\#(command)","error":{"code":"\#(code)","message":"\#(code) happened","details":\#(details),"disposition":{"delivery":"\#(delivery)","retry":"\#(delivery == "not_delivered" ? "safe" : "unsafe")"}}}"#)
}

/// A scripted `DesktopHarness`: records calls as strings and answers from preset results.
final class FakeHarness: DesktopHarness, @unchecked Sendable {
    private let lock = NSLock()
    let kind: HarnessKind = .agentDesktop
    var calls: [String] = []
    /// Snapshot results consumed in order (the last one repeats); nil means "no snapshot" (native fallback).
    var snapshotResults: [DesktopSnapshot?] = [nil]
    var findResult: DesktopFindMatch?
    /// Act results consumed in order; the last one repeats.
    var actResults: [HarnessActionResult] = [.delivered(verified: true)]
    var readResult: String?
    var windows: [DesktopWindowCandidate] = []
    var surfacesToReport: [String] = []
    /// Surfaces every `act` leaves open (as agent-desktop reports in `data.surfaces`).
    var surfacesAfterAct: [String] = []
    var sessionID: String? = "sess-1"
    /// When set, a `wait` returns this instead of the act results, after running `onWait` and sleeping `waitDelay`
    /// (a cancel cuts the sleep short).
    var waitResult: HarnessActionResult?
    var waitDelay: Duration = .zero
    var onWait: (@Sendable () -> Void)?

    func snapshot(app: String, surface: DesktopSurface?, timeoutMs: Int) async -> DesktopSnapshot? {
        lock.withLock {
            calls.append("snapshot:" + (surface?.rawValue ?? app))
            let r = snapshotResults.first
            if snapshotResults.count > 1 { snapshotResults.removeFirst() }
            return r ?? nil
        }
    }
    func find(app: String?, surface: DesktopSurface?, name: String) async -> DesktopFindMatch? {
        lock.withLock { calls.append("find:\(surface?.rawValue ?? "window"):\(app ?? "-"):\(name)"); return findResult }
    }
    func act(_ command: DesktopCommand) async -> HarnessActionResult {
        if case .wait = command, let waited = lock.withLock({ () -> HarnessActionResult? in
            if waitResult != nil { calls.append("act:" + command.argv(headed: false, session: nil).joined(separator: " ")) }
            return waitResult
        }) {
            onWait?()
            if waitDelay > .zero { try? await Task.sleep(for: waitDelay) }
            return waited
        }
        return lock.withLock {
            calls.append("act:" + command.argv(headed: false, session: nil).joined(separator: " "))
            let r = actResults.first ?? .delivered(verified: true)
            if actResults.count > 1 { actResults.removeFirst() }
            surfacesToReport = surfacesAfterAct
            return r
        }
    }
    func read(_ command: DesktopCommand) async -> String? {
        lock.withLock { calls.append("read:" + command.argv(headed: false, session: nil).joined(separator: " ")); return readResult }
    }
    func listWindows(app: String) async -> [DesktopWindowCandidate] {
        lock.withLock { calls.append("windows:\(app)"); return windows }
    }
    func takeOpenSurfaces() -> [String] {
        lock.withLock { defer { surfacesToReport = [] }; return surfacesToReport }
    }
    func startSession(name: String) async -> String? {
        lock.withLock { calls.append("session:start"); return sessionID }
    }
    func endSession(_ id: String) async {
        lock.withLock { calls.append("session:end:\(id)") }
    }
}

/// A manually advanced clock for `TaskRunner(now:)`.
final class FakeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = ContinuousClock.now
    func now() -> ContinuousClock.Instant { lock.withLock { current } }
    func advance(_ d: Duration) { lock.withLock { current = current.advanced(by: d) } }
}

/// A scripted `ScreenshotProviding`: records each capture's badges, answers from preset results (the last repeats),
/// and can be told to hang.
final class FakeScreenshots: ScreenshotProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var results: [ScreenshotResult]
    private var badgeCalls: [[Int: UIElementInfo]] = []
    var hangs = false
    var calls: Int { lock.withLock { badgeCalls.count } }
    var badges: [[Int: UIElementInfo]] { lock.withLock { badgeCalls } }

    /// A 200x150 picture of the 400x300 window at (100, 100): scale 2, so a picture point (x, y) is screen (100 + 2x, 100 + 2y).
    static let shot = StepScreenshot(jpeg: Data([1, 2, 3]), imageSize: CGSize(width: 200, height: 150),
                                     windowFrame: CGRect(x: 100, y: 100, width: 400, height: 300), app: "Safari")

    init(_ results: [ScreenshotResult] = [.image(FakeScreenshots.shot)]) { self.results = results }

    func capture(badges: [Int: UIElementInfo]) async -> ScreenshotResult {
        let (hang, result): (Bool, ScreenshotResult) = lock.withLock {
            badgeCalls.append(badges)
            let r = results.first ?? .failed
            if results.count > 1 { results.removeFirst() }
            return (hangs, r)
        }
        if hang { try? await Task.sleep(for: .seconds(30)) }   // a capture that never comes back in time
        return result
    }
}
