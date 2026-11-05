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
    /// Overlay surfaces agent-desktop can snapshot; while one is open the window behind it is the wrong target.
    static let overlaySurfaces: [String: DesktopSurface] = ["menu": .menu, "sheet": .sheet, "alert": .alert, "popover": .popover]

    public init(ax: any ElementProviding, maxElements: Int, harness: (any DesktopHarness)? = nil, snapshotTimeoutMs: Int = 3000) {
        self.ax = ax
        self.maxElements = maxElements
        self.harness = harness
        self.snapshotTimeoutMs = snapshotTimeoutMs
    }

    /// `labels` holds exactly the elements listed in the observation (titled, first `maxElements` by number).
    /// While number badges are shown (`overlay` is `.labels`), the badges' own elements and numbers are used, so a
    /// number the model picks is the one the user sees. Off the main actor, pass `screens` (from `screenRects()`,
    /// read on the main actor); nil reads them here.
    public func observe(mode: Mode, overlay: OverlayState,
                        screens: [CGRect]? = nil) -> (observation: ScreenObservation, labels: [Int: UIElementInfo]) {
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
        return (observation, snapshot)
    }

    /// The task loop's observation. `harnessKind` is the task's harness (chosen once with `probe()`): with
    /// `.agentDesktop` and no badge overlay, elements come from an agent-desktop snapshot of the frontmost app, or
    /// of the overlay surface (sheet, menu, alert, popover) the last action left open. When agent-desktop cannot
    /// read the window the native walk is used for this observation, but `observation.harness` stays the task's.
    public func observe(mode: Mode, overlay: OverlayState, screens: [CGRect]? = nil, harnessKind: HarnessKind,
                        readings: [String] = []) async -> (observation: ScreenObservation, labels: [Int: UIElementInfo]) {
        var result: (observation: ScreenObservation, labels: [Int: UIElementInfo])
        if harnessKind == .agentDesktop, let harness, overlay.kindName != "labels" {
            let app = ax.frontmostAppName() ?? ""
            let surface = harness.takeOpenSurfaces().lazy.compactMap { Self.overlaySurfaces[$0] }.first
            if let snap = await harness.snapshot(app: app, surface: surface, timeoutMs: snapshotTimeoutMs) {
                result = Self.list(snap, app: app, windowTitle: ax.focusedWindowTitle() ?? snap.windowTitle ?? "",
                                   url: ax.webURL(), mode: mode, overlay: overlay, limit: maxElements)
                result.observation.surface = surface?.rawValue
            } else {
                result = observe(mode: mode, overlay: overlay, screens: screens)
            }
        } else {
            result = observe(mode: mode, overlay: overlay, screens: screens)
        }
        result.observation.harness = harnessKind
        result.observation.readings = readings
        return result
    }

    /// Whether agent-desktop can read the frontmost app right now; decides a task's harness.
    public func probe() async -> Bool {
        guard let harness else { return false }
        return await harness.snapshot(app: ax.frontmostAppName() ?? "", surface: nil, timeoutMs: snapshotTimeoutMs) != nil
    }

    /// Numbers the snapshot's listable elements 1…N in snapshot (depth-first) order, up to `limit`.
    static func list(_ snap: DesktopSnapshot, app: String, windowTitle: String, url: String?, mode: Mode,
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

    /// True once right after an observation first exposed a Chromium page tree: observe again before trusting it.
    public func didJustExpose() -> Bool { ax.didJustExpose() }

    /// Screen rects in CG coordinates. Call on the main actor (reads NSScreen).
    public func screenRects() -> [CGRect] { ax.screenRectsCG() }
}
