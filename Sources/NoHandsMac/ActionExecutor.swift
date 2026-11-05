import Foundation
import CoreGraphics
import NoHandsCore

/// What the executor needs from the accessibility layer (AXQuery conforms).
public protocol ElementProviding: Sendable {
    func actionableElements() -> [UIElementInfo]
    /// The same walk with screen rects read by the caller (on the main actor), for walks run off it.
    func actionableElements(screens: [CGRect]) -> [UIElementInfo]
    func screenRectsCG() -> [CGRect]
    func activate(appNamed: String) -> Bool
    /// Opens `url` in the named app, or in the default handler when nil. Returns the handling app's name
    /// ("" if unknown) so the caller can wait for it; nil when the named app does not exist.
    func open(url: URL, appNamed: String?) -> String?
    func frontmostAppName() -> String?
    /// Whether the frontmost app has a focused window (a cold-launched browser is frontmost before it has one).
    func frontmostHasWindow() -> Bool
    func focusedWindowTitle() -> String?
    func webURL() -> String?
    /// True once right after a walk first exposed the frontmost Chromium app's page tree (which appears a moment
    /// later): the caller should re-observe before trusting the element list. Reading it clears it.
    func didJustExpose() -> Bool
    /// The frontmost app's focused window frame in CG (top-left origin) coordinates; nil when it has none.
    func focusedWindowFrame() -> CGRect?
    /// Moves and resizes the focused window to `frame` (CG coordinates). False when there is no window or the
    /// app refused.
    func setFocusedWindowFrame(_ frame: CGRect) -> Bool
    /// Screen areas a window may occupy (minus menu bar and Dock), CG coordinates, same order as `screenRectsCG()`.
    func visibleScreenRectsCG() -> [CGRect]
    /// The frame (CG coordinates) of the search box in the frontmost window, when it shows one: a page's own
    /// search field first, else the app's. Never a browser's address bar.
    func searchFieldFrame() -> CGRect?
    /// Whether the frontmost app is a web browser (its address bar searches the web).
    func frontmostIsBrowser() -> Bool
}

extension ElementProviding {
    public func searchFieldFrame() -> CGRect? { nil }
    public func frontmostIsBrowser() -> Bool { false }
    public func focusedWindowTitle() -> String? { nil }
    public func webURL() -> String? { nil }
    public func didJustExpose() -> Bool { false }
    public func open(url: URL, appNamed: String?) -> String? { nil }
    public func frontmostHasWindow() -> Bool { true }
    public func actionableElements(screens: [CGRect]) -> [UIElementInfo] { actionableElements() }
    public func focusedWindowFrame() -> CGRect? { nil }
    public func setFocusedWindowFrame(_ frame: CGRect) -> Bool { false }
    public func visibleScreenRectsCG() -> [CGRect] { screenRectsCG() }
}

extension AXQuery: ElementProviding {
    public func screenRectsCG() -> [CGRect] { AXQuery.screenRectsCG() }
    public func visibleScreenRectsCG() -> [CGRect] { AXQuery.visibleScreenRectsCG() }
}

/// What the executor needs from the overlay (OverlayController conforms).
@MainActor public protocol OverlayPresenting: AnyObject {
    var state: OverlayState { get }
    func showGrid(_ grid: GridModel)
    func showLabels(_ labels: [Int: UIElementInfo])
    func hide()
    /// A transient notice that is not about a prompt (loading, listening, an error).
    func showHUD(_ text: String, duration: Duration)
    /// The prompt's row on the board at the top of the screen: its words and how far it has got. Reporting an
    /// unknown id adds the row; reporting a known one updates it.
    func report(_ id: Int, text: String, status: PromptStatus)
    func screenBoundsCG(containing point: CGPoint) -> CGRect
}

extension OverlayPresenting {
    public func showHUD(_ text: String) { showHUD(text, duration: .seconds(1.5)) }
}

extension OverlayController: OverlayPresenting {
    public func screenBoundsCG(containing point: CGPoint) -> CGRect { OverlayController.screenBoundsCG(containing: point) }
}

@MainActor public final class ActionExecutor {
    /// Guards against runaway LLM output being typed into the focused app.
    public static let maxTypedCharacters = 2000
    static let pointerUnknown = "pointer position unknown"
    public static let cancelled = "cancelled"

    static let needsHarness = "needs agent-desktop"
    public static let elementChanged = "element changed, look again"
    static let readingLimit = 300

    let input: any InputSynthesizing
    let ax: any ElementProviding
    private let overlay: any OverlayPresenting
    private let config: AppConfig
    /// agent-desktop, when installed and chosen; nil runs every action natively.
    let harness: (any DesktopHarness)?
    let clipboard: any ClipboardAccess
    public var onModeChange: ((Mode) -> Void)?
    private let frontTimeout: Duration
    /// How long an app that just came to the front may take to show a window (a cold launch on a loaded Mac).
    private let windowTimeout: Duration
    private var pressed: Set<MouseButton> = []
    /// Label snapshot of the current LLM-derived batch; `.label(n)` resolves only against this.
    var labelSnapshot: [Int: UIElementInfo]?
    /// Text the model asked to read (`read_*` actions) since the last `takeReadings()`.
    public private(set) var readings: [String] = []

    public init(input: any InputSynthesizing, ax: any ElementProviding, overlay: any OverlayPresenting,
                config: AppConfig, frontTimeout: Duration = .seconds(1.5), windowTimeout: Duration = .seconds(6),
                harness: (any DesktopHarness)? = nil, clipboard: any ClipboardAccess = PasteboardClipboard()) {
        self.frontTimeout = frontTimeout
        self.windowTimeout = windowTimeout
        self.input = input
        self.ax = ax
        self.overlay = overlay
        self.config = config
        self.harness = harness
        self.clipboard = clipboard
    }

    /// The readings collected so far; the task loop moves them into the next observation.
    public func takeReadings() -> [String] {
        defer { readings = [] }
        return readings
    }

    func addReading(_ label: String, _ text: String) {
        readings.append(String("\(label): \(text)".prefix(Self.readingLimit)))
    }

    /// Executes in order; stops at the first failure. Returns the failure message if any (the caller shows it on
    /// the prompt's row). Any mouse button pressed by this call is released before a failure is returned.
    /// Returns `cancelled` when the calling task is cancelled before an action.
    @discardableResult
    public func execute(_ actions: [Action], labels: [Int: UIElementInfo]? = nil) async -> String? {
        pressed = []
        labelSnapshot = labels
        defer { labelSnapshot = nil }
        for (i, action) in actions.enumerated() {
            // A cancelled task (stop phrase, pause) must not keep acting, e.g. after an interrupted `wait`.
            if Task.isCancelled {
                if !pressed.isEmpty { input.releaseAll() }
                pressed = []
                return Self.cancelled
            }
            if let message = await run(action, isLast: i == actions.count - 1) {
                if !pressed.isEmpty { input.releaseAll() }
                pressed = []
                return message
            }
        }
        return nil
    }

    private func run(_ action: Action, isLast: Bool) async -> String? {
        do {
            switch action {
            case .typeText(let text):
                guard text.count <= Self.maxTypedCharacters else { return "text too long" }
                try input.type(text)
                hideStaleOverlay()
            case .pressKey(let chord):
                try input.press(chord)
                hideStaleOverlay()
            case .click(let target, let button, let count):
                guard (1...3).contains(count) else { return "bad click count" }
                // A numbered element with a ref is clicked semantically; a point click is the fallback.
                if case .label(let n) = target, let e = labelSnapshot?[n], let ref = e.ref, let harness {
                    switch await harness.act(.click(ref: ref, button: button, count: count)) {
                    case .delivered: hideStaleOverlay(); return nil
                    case .failed(let m): return m
                    case .elementChanged: return Self.elementChanged
                    case .notDelivered(let m):
                        guard e.frame != .zero else { return m }
                    }
                }
                let usedOverlay: Bool
                if case .numbered = target { usedOverlay = overlay.state != .none } else { usedOverlay = false }
                switch resolveClick(target) {
                case .failure(let m): return m
                case .point(let p):
                    try input.click(at: p, button: button, count: count)
                    if usedOverlay { overlay.hide() }
                }
            case .pressMouse(let b):
                guard let at = input.currentMouseLocation() else { return Self.pointerUnknown }
                try input.mouseDown(b, at: at)
                pressed.insert(b)
            case .releaseMouse(let b):
                guard let at = input.currentMouseLocation() else { return Self.pointerUnknown }
                try input.mouseUp(b, at: at)
                pressed.remove(b)
            case .moveCursor(let target):
                switch resolveMove(target) {
                case .failure(let m): return m
                case .point(let p): try input.moveMouse(to: p)
                }
            case .scroll(let direction, let amount):
                guard (1...100).contains(amount) else { return "bad scroll amount" }
                try input.scroll(direction, lines: amount)
                hideStaleOverlay()
            case .showGrid:
                guard let at = input.currentMouseLocation() else { return Self.pointerUnknown }
                let bounds = overlay.screenBoundsCG(containing: at)
                overlay.showGrid(GridModel(bounds: bounds, columns: config.gridColumns, rows: config.gridRows))
            case .zoomGrid(let n):
                guard case .grid(let g) = overlay.state else { return "no grid shown" }
                guard let zoomed = g.zoomed(into: n) else { return "no cell \(n)" }
                overlay.showGrid(zoomed)
            case .showLabels:
                overlay.showLabels(LabelAssigner.assign(ax.actionableElements()))
            case .hideOverlay:
                overlay.hide()
            case .setMode(let mode):
                onModeChange?(mode)
            case .openApp(let name):
                guard ax.activate(appNamed: name) else { return "no app named \(name)" }
                hideStaleOverlay()
                if let failure = await waitReady(name, moreActionsFollow: !isLast) { return failure }
            case .openURL(let url, let app):
                guard let handler = ax.open(url: url, appNamed: app) else {
                    return app.map { "no app named \($0)" } ?? "no browser for \(url.host ?? "that address")"
                }
                hideStaleOverlay()
                if !handler.isEmpty, let failure = await waitReady(handler, moreActionsFollow: !isLast) { return failure }
            case .moveWindow(let placement):
                guard let current = ax.focusedWindowFrame() else { return "no window to move" }
                guard let screen = Self.screen(holding: current, among: ax.visibleScreenRectsCG()) else { return "no screen" }
                let target = placement.frame(in: screen, current: current)
                guard ax.setFocusedWindowFrame(target) else { return "couldn't move window" }
                hideStaleOverlay()
            case .search(let query):
                guard query.count <= Self.maxTypedCharacters else { return "text too long" }
                if let failure = try search(query) { return failure }
                hideStaleOverlay()
            case .wait(let ms):
                try? await Task.sleep(for: .milliseconds(ms))
            case .ignore:
                break
            case .setValue, .typeInto, .clearField, .selectOption, .setChecked, .setExpanded, .focusElement, .scrollTo,
                 .scrollIn, .drag, .clickIn, .menuItem, .closeApp, .windowAction, .clipboardSet, .readClipboard,
                 .readValue, .readNotifications, .dismissNotifications, .waitFor:
                if let failure = try await runHarnessAction(action) { return failure }
                hideStaleOverlay()
            }
            return nil
        } catch let e as Unresolved {
            return e.message
        } catch is HarnessOnly {
            return Self.needsHarness
        } catch {
            return "couldn't post input event"
        }
    }

    func hideStaleOverlay() { if overlay.state != .none { overlay.hide() } }

    /// "search for <query>": the frontmost window's own search box (a YouTube page's, Finder's) gets the query
    /// and Return; without one, a site with a known results page is navigated to it in the current tab; any
    /// other browser page searches from the address bar. Returns the failure for an app with nothing to search.
    private func search(_ query: String) throws -> String? {
        // One public log line per search naming the route and why earlier routes were skipped. The query is
        // never in it (transcripts are private); a thrown input error is logged as a warning naming the route.
        var route = "searchField"
        do {
            guard let typed = SiteSearch.typable(query) else { return "can't search for that" }
            // A field outside the focused window (scrolled out of view, another app's) is not clicked: Cmd-A and the
            // typing after it would land in whatever is there.
            if let box = ax.searchFieldFrame(),
               ax.focusedWindowFrame().map({ $0.contains(CGPoint(x: box.midX, y: box.midY)) }) ?? true {
                try input.click(at: CGPoint(x: box.midX, y: box.midY), button: .left, count: 1)
                try input.press(KeyChord(.a, [.command]))
                try input.type(typed)
                try input.press(KeyChord(.return))
                PipelineLog.info("search: route=searchField")
                return nil
            }
            let pageURL = ax.webURL()
            if let host = pageURL.flatMap({ URL(string: $0)?.host }), let results = SiteSearch.url(host: host, query: typed) {
                route = "siteURL"
                try addressBar(results.absoluteString)
                PipelineLog.info("search: route=siteURL (no search field, known site)")
                return nil
            }
            guard pageURL != nil || ax.frontmostIsBrowser() else {
                PipelineLog.info("search: route=none (not a browser, no search field)")
                return "nothing to search in \(ax.frontmostAppName() ?? "the frontmost app")"
            }
            route = "addressBar"
            try addressBar(typed)
            PipelineLog.info("search: route=addressBar (no search field, no known site)")
            return nil
        } catch {
            PipelineLog.warning("search: route=\(route) failed to post input", detail: "\(error)")
            throw error
        }
    }

    private func addressBar(_ text: String) throws {
        try input.press(KeyChord(.l, [.command]))
        try input.type(text)
        try input.press(KeyChord(.return))
    }

    /// The screen a window belongs to: the one holding its centre, else the one it overlaps most, else the first.
    nonisolated static func screen(holding window: CGRect, among screens: [CGRect]) -> CGRect? {
        let centre = CGPoint(x: window.midX, y: window.midY)
        if let s = screens.first(where: { $0.contains(centre) }) { return s }
        let overlapping = screens.filter { $0.intersects(window) }
        func area(_ r: CGRect) -> CGFloat { let i = r.intersection(window); return i.width * i.height }
        if let s = overlapping.max(by: { area($0) < area($1) }) { return s }
        return screens.first
    }

    /// Waits for `name` to come to the front and, when more actions follow (keystrokes that need a window), for
    /// it to have a focused window. Returns the failure message; nil when ready or when nothing follows.
    private func waitReady(_ name: String, moreActionsFollow: Bool) async -> String? {
        let arrived = await waitForFront(name)
        guard moreActionsFollow else { return nil }
        guard arrived else { return "app did not come to front" }
        let deadline = ContinuousClock.now.advanced(by: windowTimeout)
        while !ax.frontmostHasWindow() {
            if ContinuousClock.now >= deadline { return "no window in \(name)" }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return nil
    }

    func waitForFront(_ name: String) async -> Bool {
        let want = name.lowercased()
        func isFront() -> Bool {
            guard let f = ax.frontmostAppName()?.lowercased(), !f.isEmpty else { return false }
            return f == want || f.contains(want) || want.contains(f)
        }
        let deadline = ContinuousClock.now.advanced(by: frontTimeout)
        while !isFront() {
            if ContinuousClock.now >= deadline { return false }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return true
    }

    /// Rejects points outside every screen (skipped when no screens are known).
    private func checkOnScreen(_ r: TargetResolution, checked: Bool) -> TargetResolution {
        guard checked, case .point(let p) = r else { return r }
        let screens = ax.screenRectsCG()
        if screens.isEmpty || screens.contains(where: { $0.contains(p) }) { return r }
        return .failure("point off screen")
    }

    private func elementsIfNeeded(named: Bool) -> [UIElementInfo] { named ? ax.actionableElements() : [] }

    private func resolveClick(_ t: ClickTarget) -> TargetResolution {
        var needsElements = false, direct = false
        if case .element = t { needsElements = true }
        if case .point = t { direct = true }
        let cursor = input.currentMouseLocation()
        if case .cursor = t, cursor == nil { return .failure(Self.pointerUnknown) }
        return checkOnScreen(TargetResolver.resolveClick(t, overlay: overlay.state, cursor: cursor ?? .zero,
                                           elements: elementsIfNeeded(named: needsElements),
                                           screens: ax.screenRectsCG(), labels: labelSnapshot), checked: direct)
    }

    func resolveMove(_ t: MoveTarget) -> TargetResolution {
        var needsElements = false, direct = false
        if case .element = t { needsElements = true }
        switch t { case .point, .relative: direct = true; default: break }
        let cursor = input.currentMouseLocation()
        if case .relative = t, cursor == nil { return .failure(Self.pointerUnknown) }
        return checkOnScreen(TargetResolver.resolveMove(t, overlay: overlay.state, cursor: cursor ?? .zero,
                                          elements: elementsIfNeeded(named: needsElements),
                                          screens: ax.screenRectsCG(), labels: labelSnapshot), checked: direct)
    }

    /// Safety net for pause/quit: release any held mouse button and drop any grid/labels overlay.
    public func releaseAll() {
        input.releaseAll()
        pressed = []
        overlay.hide()
    }
}
