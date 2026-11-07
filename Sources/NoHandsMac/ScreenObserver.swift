import Foundation
import CoreGraphics
import NoHandsCore

/// Builds a `ScreenObservation` of the frontmost app. Only collects; titles/URLs are untrusted and
/// are sanitized by the request builder.
public struct ScreenObserver: Sendable {
    private let ax: any ElementProviding
    private let maxElements: Int
    private let harness: (any DesktopHarness)?
    private let snapshotTimeoutMs: Int
    private let audio: any AudioOutputProbing
    /// Overlay surfaces agent-desktop can snapshot; while one is open the window behind it is the wrong target.
    static let overlaySurfaces: [String: DesktopSurface] = ["menu": .menu, "sheet": .sheet, "alert": .alert, "popover": .popover]

    public init(ax: any ElementProviding, maxElements: Int, harness: (any DesktopHarness)? = nil, snapshotTimeoutMs: Int = 3000,
                audio: any AudioOutputProbing = AudioOutputProbe()) {
        self.ax = ax
        self.maxElements = maxElements
        self.harness = harness
        self.snapshotTimeoutMs = snapshotTimeoutMs
        self.audio = audio
    }

    /// `labels` holds exactly the elements listed in the observation (titled, first `maxElements` by number).
    /// While number badges are shown (`overlay` is `.labels`), the badges' own elements and numbers are used, so a
    /// number the model picks is the one the user sees. Off the main actor, pass `screens` (from `screenRects()`,
    /// read on the main actor); nil reads them here.
    public func observe(mode: Mode, overlay: OverlayState,
                        screens: [CGRect]? = nil) -> (observation: ScreenObservation, labels: [Int: UIElementInfo]) {
        let r = observeNative(mode: mode, overlay: overlay, screens: screens)
        return (r.observation, r.labels)
    }

    /// The native walk; `all` is every element it found, before the untitled filter and the cap.
    private func observeNative(mode: Mode, overlay: OverlayState, screens: [CGRect]?)
        -> (observation: ScreenObservation, labels: [Int: UIElementInfo], all: [UIElementInfo]) {
        let all: [Int: UIElementInfo]
        if case .labels(let badges) = overlay { all = badges }
        else { all = LabelAssigner.assign(screens.map { ax.actionableElements(screens: $0) } ?? ax.actionableElements()) }
        var listed: [ObservedElement] = []
        var snapshot: [Int: UIElementInfo] = [:]
        for n in all.keys.sorted() {
            guard let e = all[n], !e.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            if listed.count >= maxElements { break }
            var role = e.role
            if role.hasPrefix("AX") { role.removeFirst(2) }
            listed.append(ObservedElement(number: n, role: role.lowercased(), title: e.title))
            snapshot[n] = e
        }
        let observation = ScreenObservation(
            app: ax.frontmostAppName() ?? "", windowTitle: ax.focusedWindowTitle() ?? "",
            url: ax.webURL(), mode: mode, overlay: overlay.kindName, elements: listed)
        return (observation, snapshot, all.keys.sorted().compactMap { all[$0] })
    }

    /// The task loop's observation. `harnessKind` is the task's harness (chosen once with `probe()`): with
    /// `.agentDesktop` and no badge overlay, elements come from an agent-desktop snapshot of the frontmost app, or
    /// of the overlay surface (sheet, menu, alert, popover) the last action left open. When agent-desktop cannot
    /// read the window the native walk is used for this observation, but `observation.harness` stays the task's.
    /// `fromHarness` says whether agent-desktop supplied the elements (the task loop's first observation uses it to
    /// decide the task's harness).
    /// `surfaces` are the overlays the last action left open (`DesktopHarness.takeOpenSurfaces()`, read once per
    /// settle by the caller so every poll of that settle targets the same surface); nil reads them here.
    public func observe(mode: Mode, overlay: OverlayState, screens: [CGRect]? = nil, harnessKind: HarnessKind,
                        readings: [String] = [], surfaces: [String]? = nil) async -> (observation: ScreenObservation, labels: [Int: UIElementInfo], fromHarness: Bool) {
        var result: (observation: ScreenObservation, labels: [Int: UIElementInfo])
        var every: [UIElementInfo]
        var fromHarness = false
        if harnessKind == .agentDesktop, let harness, overlay.kindName != "labels" {
            let app = ax.frontmostAppName() ?? ""
            let surface = (surfaces ?? harness.takeOpenSurfaces()).lazy.compactMap { Self.overlaySurfaces[$0] }.first
            if let snap = await harness.snapshot(app: app, surface: surface, timeoutMs: snapshotTimeoutMs) {
                result = Self.list(snap, app: app, windowTitle: ax.focusedWindowTitle() ?? snap.windowTitle ?? "",
                                   url: ax.webURL(), mode: mode, overlay: overlay, limit: maxElements)
                result.observation.surface = surface?.rawValue
                every = snap.elements
                fromHarness = true
            } else {
                let native = observeNative(mode: mode, overlay: overlay, screens: screens)
                (result, every) = ((native.observation, native.labels), native.all)
            }
        } else {
            let native = observeNative(mode: mode, overlay: overlay, screens: screens)
            (result, every) = ((native.observation, native.labels), native.all)
        }
        // Player controls are looked for among every element found; the audio hint only when there is none.
        result.observation.media = MediaSignal.state(elements: every, audioPlaying: audio.isPlaying)
        result.observation.harness = harnessKind
        let browser = ax.browserWindows()
        result.observation.browserWindows = browser?.windows
        result.observation.browserApp = browser?.app
        result.observation.readings = readings
        return (result.observation, result.labels, fromHarness)
    }

    /// The frontmost browser's windows and tabs, read again on their own (the task runner's second look at a
    /// browser it first saw late).
    public func browserWindows() -> (app: String, windows: [BrowserWindow])? { ax.browserWindows() }

    /// Whether agent-desktop can read the frontmost app right now; decides a task's harness.
    public func probe() async -> Bool {
        guard let harness else { return false }
        return await harness.snapshot(app: ax.frontmostAppName() ?? "", surface: nil, timeoutMs: snapshotTimeoutMs) != nil
    }

    /// Numbers the snapshot's listable elements 1…N in snapshot (depth-first) order, up to `limit`.
    public static func list(_ snap: DesktopSnapshot, app: String, windowTitle: String, url: String?, mode: Mode,
                     overlay: OverlayState, limit: Int) -> (observation: ScreenObservation, labels: [Int: UIElementInfo]) {
        var listed: [ObservedElement] = []
        var labels: [Int: UIElementInfo] = [:]
        for e in snap.elements where DesktopSnapshot.listable(e) {
            if listed.count >= limit { break }
            let n = listed.count + 1
            listed.append(ObservedElement(number: n, role: e.role.lowercased(), title: e.title, value: e.value, states: e.states))
            var kept = e
            kept.id = n
            labels[n] = kept
        }
        let observation = ScreenObservation(app: app, windowTitle: windowTitle, url: url, mode: mode,
                                            overlay: overlay.kindName, elements: listed)
        return (observation, labels)
    }

    /// Forgets the browser window and tab ids handed out during a task.
    public func resetBrowserTokens() { ax.resetBrowserTokens() }

    /// True once right after an observation first exposed a Chromium page tree: observe again before trusting it.
    public func didJustExpose() -> Bool { ax.didJustExpose() }

    /// Screen rects in CG coordinates. Call on the main actor (reads NSScreen).
    public func screenRects() -> [CGRect] { ax.screenRectsCG() }
}
