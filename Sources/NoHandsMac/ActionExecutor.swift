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
    /// Walks the focused window, offscreen parts included, for an element or text matching `words` (see
    /// `PageFind.Matcher`); the match is remembered for `scrollIntoView`. Honors the calling task's cancellation.
    func findOnPage(words: String) -> UIElementInfo?
    /// The visible text of the focused window's page in reading order (see `AXQuery.pageText`); empty when there is
    /// none. Honors the calling task's cancellation.
    func pageText() -> [String]
    /// Scrolls the element `findOnPage` just returned into view and returns its frame (CG coordinates) once it is on
    /// a screen; nil when it cannot be scrolled or never arrives.
    func scrollIntoView(_ element: UIElementInfo) async -> CGRect?
    /// Whether the frontmost app is a web browser (its address bar searches the web).
    func frontmostIsBrowser() -> Bool
    /// The frontmost browser's name and its windows and tabs, with opaque ids that stay the same for the same window
    /// or tab until `resetBrowserTokens()`; nil when the frontmost app is not a browser. The name is of the app
    /// the windows were read from.
    func browserWindows() -> (app: String, windows: [BrowserWindow])?
    /// Closes the tab or window `id` names with its own close button. `.noControl` when it has none.
    func closeBrowserTab(id: String) -> BrowserActionResult
    func closeBrowserWindow(id: String) -> BrowserActionResult
    /// Makes the tab `id` the selected one.
    func selectBrowserTab(id: String) -> BrowserActionResult
    func browserTabIsSelected(id: String) -> Bool
    /// Whether the tab `id` belongs to the frontmost app and to that app's focused window: the only place a
    /// keyboard shortcut reaches it.
    func browserTabIsInFrontWindow(id: String) -> Bool
    /// Forgets the ids handed out (the end of a task).
    func resetBrowserTokens()
    /// Whether the focused window is in full screen; nil when unknown.
    func focusedWindowIsFullScreen() -> Bool?
    /// Whether the focused element takes typed text.
    func focusedElementIsTextInput() -> Bool
}

/// How a request to act on a browser tab or window went.
public enum BrowserActionResult: Equatable, Sendable {
    case done
    /// The tab or window no longer exists.
    case gone
    /// It has no control for that (a tab with no close button): the caller falls back to a shortcut.
    case noControl
    case failed(String)
}

extension ElementProviding {
    public func searchFieldFrame() -> CGRect? { nil }
    public func findOnPage(words: String) -> UIElementInfo? { nil }
    public func pageText() -> [String] { [] }
    public func scrollIntoView(_ element: UIElementInfo) async -> CGRect? { nil }
    public func frontmostIsBrowser() -> Bool { false }
    public func browserWindows() -> (app: String, windows: [BrowserWindow])? { nil }
    public func closeBrowserTab(id: String) -> BrowserActionResult { .failed("no browser tabs") }
    public func closeBrowserWindow(id: String) -> BrowserActionResult { .failed("no browser windows") }
    public func selectBrowserTab(id: String) -> BrowserActionResult { .failed("no browser tabs") }
    public func browserTabIsSelected(id: String) -> Bool { false }
    public func browserTabIsInFrontWindow(id: String) -> Bool { false }
    public func resetBrowserTokens() {}
    public func focusedWindowIsFullScreen() -> Bool? { nil }
    public func focusedElementIsTextInput() -> Bool { false }
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
    /// A running task's step trail, for the prompt's row. Ignored for an unknown id or a finished row.
    func report(_ id: Int, trail: TaskTrail)
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
    static let noPageText = "no text on this page"

    let input: any InputSynthesizing
    let ax: any ElementProviding
    private let overlay: any OverlayPresenting
    private let config: AppConfig
    /// agent-desktop, when installed and chosen; nil runs every action natively.
    let harness: (any DesktopHarness)?
    /// Where "menu <words>" looks for the item to press, before agent-desktop.
    let menus: any MenuReading
    let clipboard: any ClipboardAccess
    public var onModeChange: ((Mode) -> Void)?
    private let frontTimeout: Duration
    private let audio: any AudioOutputProbing
    private let mediaPoll: Duration
    private let volume: any VolumeControlling
    /// The accessibility layer the media walk uses: one with a larger budget than `ax`, which does not reach a
    /// browser player's buttons. Nil walks with `ax`.
    private let mediaAX: (any ElementProviding)?
    /// How long a freshly exposed Chromium page tree gets to build before the one re-walk.
    private let exposureSettle: Duration
    /// How long an app that just came to the front may take to show a window (a cold launch on a loaded Mac).
    private let windowTimeout: Duration
    private var pressed: Set<MouseButton> = []
    /// Label snapshot of the current LLM-derived batch; `.label(n)` resolves only against this.
    var labelSnapshot: [Int: UIElementInfo]?
    /// The `Tabs:` list the current batch was chosen from; tab and window numbers resolve only against this.
    private var tabSnapshot: TabListing?
    /// Text the model asked to read (`read_*` actions) since the last `takeReadings()`.
    public private(set) var readings: [String] = []
    /// The element the last `findOnPage` scrolled into view, until `takeFound()`.
    public private(set) var found: UIElementInfo?

    public init(input: any InputSynthesizing, ax: any ElementProviding, overlay: any OverlayPresenting,
                config: AppConfig, frontTimeout: Duration = .seconds(1.5), windowTimeout: Duration = .seconds(6),
                harness: (any DesktopHarness)? = nil, clipboard: any ClipboardAccess = PasteboardClipboard(),
                audio: any AudioOutputProbing = AudioOutputProbe(), mediaPoll: Duration = .milliseconds(500),
                mediaAX: (any ElementProviding)? = nil, exposureSettle: Duration = .milliseconds(600),
                menus: any MenuReading = AXMenuReader(), volume: any VolumeControlling = CoreAudioVolume()) {
        self.menus = menus
        self.volume = volume
        self.audio = audio
        self.mediaAX = mediaAX
        self.mediaPoll = mediaPoll
        self.frontTimeout = frontTimeout
        self.exposureSettle = exposureSettle
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

    /// The element a find just scrolled to; the task loop lists it first in the next observation.
    public func takeFound() -> UIElementInfo? {
        defer { found = nil }
        return found
    }

    func addReading(_ label: String, _ text: String) {
        // A label can come from the page (an element's title), so it can never spell the page reading's `page: `
        // prefix: colons go, and a bare "page" is renamed.
        var safe = label.replacingOccurrences(of: ":", with: " ").trimmingCharacters(in: .whitespaces)
        if safe.lowercased() == PageText.readingLabel { safe = "\(safe) value" }
        readings.append(String("\(safe): \(text)".prefix(Self.readingLimit)))
    }

    /// The page reading, the only long one. Only code calls this, so page content can't choose the long limit.
    func addPageReading(_ text: String) {
        readings.append(String("\(PageText.readingLabel): \(text)".prefix(PageText.limit)))
    }

    /// Executes in order; stops at the first failure. Returns the failure message if any (the caller shows it on
    /// the prompt's row). Any mouse button pressed by this call is released before a failure is returned.
    /// Returns `cancelled` when the calling task is cancelled before an action.
    @discardableResult
    public func execute(_ actions: [Action], labels: [Int: UIElementInfo]? = nil, tabs: TabListing? = nil) async -> String? {
        pressed = []
        labelSnapshot = labels
        tabSnapshot = tabs
        defer { labelSnapshot = nil; tabSnapshot = nil }
        for (i, action) in actions.enumerated() {
            // A cancelled task (stop phrase, pause) must not keep acting, e.g. after an interrupted `wait`.
            if Task.isCancelled {
                if !pressed.isEmpty { input.releaseAll() }
                pressed = []
                return Self.cancelled
            }
            // A found element is the next observation's number 1 only when the find was the step's last act: anything
            // after it may have changed the page.
            if case .findOnPage = action {} else { found = nil }
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
                var target = target
                var named: [UIElementInfo]?
                if case .element(let name) = target {
                    named = await freshElements()
                    if Task.isCancelled { return Self.cancelled }
                    // An exact title wins; a position ("first video") that maps to a shown label clicks as that label.
                    if LabelAssigner.find(exactly: name, in: named ?? []) == nil, let shown = labelSnapshot,
                       let n = OrdinalTarget.parse(name)?.label(in: shown) { target = .label(n) }
                }
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
                if named == nil { named = await namedElements(for: target) }
                if Task.isCancelled { return Self.cancelled }   // a spoken stop during the settle wait must not click
                switch resolveClick(target, elements: named) {
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
                let named = await namedElements(for: target)
                if Task.isCancelled { return Self.cancelled }
                switch resolveMove(target, elements: named) {
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
                let fresh = await freshElements()
                if Task.isCancelled { return Self.cancelled }
                overlay.showLabels(LabelAssigner.assign(fresh))
            case .hideOverlay:
                overlay.hide()
            case .setMode(let mode):
                onModeChange?(mode)
            case .openApp(let name):
                guard ax.activate(appNamed: name) else { return "no app named \(name)" }
                hideStaleOverlay()
                if let failure = await waitReady(name, moreActionsFollow: !isLast) { return failure }
            case .openURL(let url, let app):
                if let failure = await openURLAction(url, app: app, isLast: isLast) { return failure }
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
            case .searchSite(let query, let site):
                guard query.count <= Self.maxTypedCharacters else { return "text too long" }
                guard let typed = SiteSearch.typable(query) else { return "can't search for that" }
                if let host = ax.webURL().flatMap({ URL(string: $0)?.host }), SiteSearch.isOn(site: site, host: host) {
                    if let failure = try search(typed, site: site) { return failure }
                    hideStaleOverlay()
                } else {
                    guard let url = SiteSearch.url(host: site, query: typed) else { return "can't search for that" }
                    PipelineLog.info("search: route=openURL site=\(site) (site not in front)")
                    if let failure = await openURLAction(url, app: nil, isLast: isLast) { return failure }
                }
            case .wait(let ms):
                try? await Task.sleep(for: .milliseconds(ms))
            case .checkMedia:
                addReading("Media", await mediaState().rawValue)
            case .findOnPage(let words, let movePointer):
                if let failure = try await findOnPage(words, movePointer: movePointer) { return failure }
                hideStaleOverlay()
            case .ignore, .look:
                break
            case .readPage:
                if let failure = await readPage() { return failure }
            case .closeTab(let n):
                guard let tab = tabSnapshot?.tab(n) else { return "no tab \(n)" }
                if let failure = try await closeTab(id: tab.id) { return failure }
            case .closeWindow(let n):
                guard let window = tabSnapshot?.window(n) else { return "no window \(n)" }
                if let failure = Self.failure(ax.closeBrowserWindow(id: window.id), gone: "window already closed",
                                              noControl: "can't close that window") { return failure }
            case .selectTab(let n):
                guard let tab = tabSnapshot?.tab(n) else { return "no tab \(n)" }
                if let failure = Self.failure(ax.selectBrowserTab(id: tab.id), gone: "tab already closed",
                                              noControl: "can't select that tab") { return failure }
            case .goToTab(let target):
                if let failure = try await goToTab(target) { return failure }
            case .closeOtherTabs:
                if let failure = closeOtherTabs() { return failure }
            case .listTabs:
                if let failure = await listTabs() { return failure }
            case .media(let command):
                if let failure = try await runMedia(command) { return failure }
                hideStaleOverlay()
            case .volume(let change):
                if let failure = changeVolume(change) { return failure }
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

    static let noBrowser = "no browser in front"

    /// The front window of the front browser and its tabs in strip order, read off the main actor (the read can take its
    /// whole budget). nil when the front app is not a browser. Tab titles are page text: callers show them on the
    /// board only, never in a log.
    private func readFrontTabs() async -> (app: String, window: BrowserWindow?)? {
        let ax = self.ax
        guard let read = await Task.detached(operation: { ax.browserWindows() }).value else { return nil }
        return (read.app, read.windows.first(where: \.front) ?? read.windows.first)
    }

    /// "tab 3", "last tab", "switch to the YouTube tab": a number from 1 to 8 and "last" press command-1 to command-9
    /// (no read, works in Firefox); the rest read the strip and press the tab. Only in a browser, so "tab 3" never
    /// presses command-3 in Finder or Xcode.
    private func goToTab(_ target: TabTarget) async throws -> String? {
        guard ax.frontmostIsBrowser() else { return Self.noBrowser }
        if let chord = TabMatch.chord(for: target) {
            try input.press(chord)
            hideStaleOverlay()
            return nil
        }
        guard let (app, window) = await readFrontTabs() else { return Self.noBrowser }
        // A spoken stop during the read must not let the press go out.
        if Task.isCancelled { return Self.cancelled }
        guard let window, !window.tabs.isEmpty else { return "can't read the tabs in \(app)" }
        let tabs = window.tabs
        let index: Int
        switch target {
        case .number(let n):
            guard n <= tabs.count else { return window.complete ? "only \(tabs.count) tab\(tabs.count == 1 ? "" : "s")" : "can't read that far in \(app)" }
            index = n - 1
        case .named(let words):
            guard let match = TabMatch.best(words, in: tabs) else { return "no tab called \(words)" }
            index = match
        case .last:
            index = tabs.count - 1
        }
        if let failure = Self.failure(ax.selectBrowserTab(id: tabs[index].id), gone: "tab already closed",
                                      noControl: "can't select that tab") { return failure }
        hideStaleOverlay()
        return nil
    }

    /// "close the other tabs": the browser's own Close Other Tabs menu item, exact title only. A browser with no such
    /// item (Chrome keeps it in the tab's context menu) fails instead of closing tabs one by one.
    private func closeOtherTabs() -> String? {
        guard ax.frontmostIsBrowser() else { return Self.noBrowser }
        let title = "Close Other Tabs"
        switch pressMenuItem(title, exactOnly: true) {
        case .pressed: hideStaleOverlay(); return nil
        case .disabled: return "menu item \(title) is disabled"
        case .refused: return "couldn't press menu item \(title)"
        case .noMatch: return "no \(title) menu item in \(ax.frontmostAppName() ?? "this browser")"
        }
    }

    /// "list tabs": the front window's tabs as one line on the board.
    private func listTabs() async -> String? {
        guard ax.frontmostIsBrowser() else { return Self.noBrowser }
        guard let (app, window) = await readFrontTabs() else { return Self.noBrowser }
        if Task.isCancelled { return Self.cancelled }
        guard let window, !window.tabs.isEmpty else { return "can't read the tabs in \(app)" }
        overlay.showHUD(TabMatch.listLine(window.tabs), duration: .seconds(6))
        return nil
    }

    private static func failure(_ r: BrowserActionResult, gone: String, noControl: String) -> String? {
        switch r {
        case .done: nil
        case .gone: gone
        case .noControl: noControl
        case .failed(let m): m
        }
    }

    /// Closes a tab with its own close button; without one, selects it, checks it is now the selected tab in the
    /// front browser's focused window, and sends command-W. Naming the tab (not "the current one") and checking
    /// where it lives keeps a focus change between observing and acting from closing the wrong one: command-W
    /// closes whatever tab is selected in the focused window, not necessarily this tab's.
    private func closeTab(id: String) async throws -> String? {
        let gone = "tab already closed"
        switch ax.closeBrowserTab(id: id) {
        case .done: return nil
        case .gone: return gone
        case .failed(let m): return m
        case .noControl:
            guard ax.frontmostIsBrowser() else { return "browser not in front" }
            let cannot = "can't close that tab"
            guard ax.browserTabIsInFrontWindow(id: id) else { return cannot }
            if let failure = Self.failure(ax.selectBrowserTab(id: id), gone: gone, noControl: "can't select that tab") { return failure }
            try? await Task.sleep(for: .milliseconds(100))
            // A spoken stop during the pause must not let command-W go out.
            if Task.isCancelled { return Self.cancelled }
            guard ax.browserTabIsSelected(id: id) else { return "couldn't select that tab" }
            guard ax.browserTabIsInFrontWindow(id: id) else { return cannot }
            try input.press(KeyChord(.w, [.command]))
            return nil
        }
    }

    /// "pause", "next track", "skip ahead", "full screen video", "exit full screen": the route (YouTube's keys in a
    /// browser on YouTube, else a system key or the window chord) after the checks that stop a toggle doing the
    /// opposite. A command whose point is already met ("nothing is playing") shows a notice and presses nothing.
    private func runMedia(_ command: MediaCommand) async throws -> String? {
        switch command {
        case .pause, .play:
            let state = await mediaState()
            if Task.isCancelled { return Self.cancelled }
            if command == .pause, state != .playing { overlay.showHUD("nothing is playing"); return nil }
            if command == .play, state == .playing { overlay.showHUD("already playing"); return nil }
        default: break
        }
        let isBrowser = ax.frontmostIsBrowser()
        let host = isBrowser ? ax.webURL().flatMap { URL(string: $0)?.host } : nil
        switch MediaRoute.step(for: command, isBrowser: isBrowser, host: host) {
        case .siteKeys(let chords):
            if ax.focusedElementIsTextInput() {
                // A letter would be typed into the box: play and pause use the system key, the rest fail.
                switch command {
                case .play, .pause, .playPause: try input.pressMediaKey(.playPause); return nil
                default: return "a text box has focus: click the video first"
                }
            }
            for chord in chords { try input.press(chord) }
        case .systemKey(let key): try input.pressMediaKey(key)
        case .windowFullScreen: try input.press(Self.windowFullScreen)
        case .exitFullScreen(let siteEscape):
            guard ax.focusedWindowIsFullScreen() == true else { overlay.showHUD("not in full screen"); return nil }
            try input.press(siteEscape ? KeyChord(.escape) : Self.windowFullScreen)
        case .unsupported(let message): return message
        }
        return nil
    }

    private static let windowFullScreen = KeyChord(.f, [.command, .control])

    /// "volume 30 percent", "volume up", "mute": CoreAudio on the default output. Any level above 0 also unmutes, as the
    /// volume keys do. The notice shows the new level.
    private func changeVolume(_ change: VolumeChange) -> String? {
        do {
            if case .mute(let on) = change {
                try volume.setMuted(on)
                if on { overlay.showHUD("muted"); return nil }
            } else {
                guard let current = volume.level(), let target = VolumeMath.apply(change, current: current) else {
                    return VolumeError.noControl.description
                }
                try volume.setLevel(target)
                if target > 0 { try? volume.setMuted(false) }
            }
            overlay.showHUD(volume.level().map { "volume \($0)%" } ?? "unmuted")
            return nil
        } catch {
            return "\(error)"
        }
    }

    /// Whether media plays in the front window now, from a native walk of its elements (never agent-desktop).
    /// The walk runs off the main actor (it can take its whole budget); screen rects are read here first.
    func mediaState() async -> MediaState {
        let provider = mediaAX ?? ax
        let audio = self.audio
        let screens = provider.screenRectsCG()
        return await Task.detached {
            MediaSignal.state(elements: provider.actionableElements(screens: screens), audioPlaying: audio.isPlaying)
        }.value
    }

    /// Polls `mediaState()` until it is `playing` (nil) or `timeoutMs` passes ("wait timed out"). Cancellation
    /// ends it at once.
    func waitForMediaPlaying(timeoutMs: Int) async -> String? {
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(timeoutMs))
        while true {
            if Task.isCancelled { return Self.cancelled }
            if await mediaState() == .playing { return nil }
            let left = ContinuousClock.now.duration(to: deadline)
            if left <= .zero { return "wait timed out" }
            try? await Task.sleep(for: min(mediaPoll, left))
        }
    }

    func hideStaleOverlay() { if overlay.state != .none { overlay.hide() } }

    /// Open `url` in the named browser or the default one, then wait for it to come to the front when more
    /// actions follow. Returns the failure, or nil.
    private func openURLAction(_ url: URL, app: String?, isLast: Bool) async -> String? {
        guard let handler = ax.open(url: url, appNamed: app) else {
            return app.map { "no app named \($0)" } ?? "no browser for \(url.host ?? "that address")"
        }
        hideStaleOverlay()
        if !handler.isEmpty, let failure = await waitReady(handler, moreActionsFollow: !isLast) { return failure }
        return nil
    }

    /// "search for <query>": the frontmost window's own search box (a YouTube page's, Finder's) gets the query
    /// and Return; without one, a site with a known results page is navigated to it in the current tab; any
    /// other browser page searches from the address bar. Returns the failure for an app with nothing to search.
    /// `site` (a `SiteSearch.templates` key, from "search for X on <site>") only adds `site=` to the log line.
    private func search(_ query: String, site: String? = nil) throws -> String? {
        // One public log line per search naming the route and why earlier routes were skipped. The query is
        // never in it (transcripts are private); a thrown input error is logged as a warning naming the route.
        var route = "searchField"
        let siteLog = site.map { " site=\($0) (site open)" } ?? ""
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
                PipelineLog.info("search: route=searchField\(siteLog)")
                return nil
            }
            let pageURL = ax.webURL()
            if let host = pageURL.flatMap({ URL(string: $0)?.host }), let results = SiteSearch.url(host: host, query: typed) {
                route = "siteURL"
                try addressBar(results.absoluteString)
                PipelineLog.info("search: route=siteURL\(siteLog.isEmpty ? " (no search field, known site)" : siteLog)")
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

    /// One walk; if it just exposed a Chromium page tree, wait for the tree to build and walk once more.
    /// A flag left by a walk nobody re-walked for (the harness paths) is cleared first, so it costs no wait here.
    /// The caller checks for cancellation after this returns: a cancelled wait returns the thin first walk.
    private func freshElements() async -> [UIElementInfo] {
        _ = ax.didJustExpose()
        let first = ax.actionableElements()
        guard ax.didJustExpose() else { return first }
        try? await Task.sleep(for: exposureSettle)
        return Task.isCancelled ? first : ax.actionableElements()
    }

    /// "find <words>": the focused window is walked, offscreen parts included, for the words; the match is scrolled
    /// into view and kept for `takeFound()`. With `movePointer` (the spoken command) the pointer is left on it, so a
    /// bare "click" follows; the model's find never moves it. Nothing natively and a harness: agent-desktop's find and
    /// scroll-to. A cancel (a spoken stop) is seen after the walk and again before the scroll.
    private func findOnPage(_ words: String, movePointer: Bool) async throws -> String? {
        found = nil
        guard words.count <= PageFind.maxWords else { return "text too long" }
        guard !PageFind.normalize(words).isEmpty else { return "nothing to find" }
        PipelineLog.info("find: walking the page (len=\(words.count))")
        _ = ax.didJustExpose()
        var match = ax.findOnPage(words: words)
        if ax.didJustExpose() {
            try? await Task.sleep(for: exposureSettle)
            if !Task.isCancelled { match = ax.findOnPage(words: words) }
        }
        if Task.isCancelled { return Self.cancelled }
        if let match {
            guard let frame = await ax.scrollIntoView(match) else {
                return Task.isCancelled ? Self.cancelled : "couldn't scroll to \(words)"
            }
            if Task.isCancelled { return Self.cancelled }
            var shown = match
            shown.frame = frame
            found = shown
            if movePointer { try input.moveMouse(to: shown.clickPoint(screens: ax.screenRectsCG())) }
            return nil
        }
        if let harness, let m = await harness.find(app: ax.frontmostAppName(), surface: nil, name: words) {
            if Task.isCancelled { return Self.cancelled }
            switch await harness.act(.scrollTo(ref: m.ref)) {
            case .delivered: break
            case .failed(let message), .notDelivered(let message): return message
            case .elementChanged: return Self.elementChanged
            }
            found = UIElementInfo(id: 0, frame: .zero, title: m.name, role: m.role, ref: m.ref)
            return nil
        }
        return Task.isCancelled ? Self.cancelled : PageFind.failure(words)
    }

    /// "read_page": the focused window's visible text as one `page:` reading for the next step. A cancel (a spoken
    /// stop) is seen after the walk, before anything is kept. Always the native walk: an agent-desktop snapshot holds
    /// no static text.
    private func readPage() async -> String? {
        _ = ax.didJustExpose()
        var runs = ax.pageText()
        if ax.didJustExpose() {
            try? await Task.sleep(for: exposureSettle)
            if !Task.isCancelled { runs = ax.pageText() }
        }
        if Task.isCancelled { return Self.cancelled }
        // Room for the label, so the cut mark is never trimmed off the end.
        let text = PageText.join(runs, limit: PageText.limit - PageText.readingLabel.count - 2)
        guard !text.isEmpty else { return Self.noPageText }
        PipelineLog.info("read_page: \(text.count) characters", detail: text)
        addPageReading(text)
        return nil
    }

    private func namedElements(for target: ClickTarget) async -> [UIElementInfo]? {
        if case .element = target { return await freshElements() }
        return nil
    }

    private func namedElements(for target: MoveTarget) async -> [UIElementInfo]? {
        if case .element = target { return await freshElements() }
        return nil
    }

    private func resolveClick(_ t: ClickTarget, elements: [UIElementInfo]?) -> TargetResolution {
        var needsElements = false, direct = false
        if case .element = t { needsElements = true }
        if case .point = t { direct = true }
        let cursor = input.currentMouseLocation()
        if case .cursor = t, cursor == nil { return .failure(Self.pointerUnknown) }
        return checkOnScreen(TargetResolver.resolveClick(t, overlay: overlay.state, cursor: cursor ?? .zero,
                                           elements: elements ?? (needsElements ? ax.actionableElements() : []),
                                           screens: ax.screenRectsCG(), labels: labelSnapshot), checked: direct)
    }

    func resolveMove(_ t: MoveTarget, elements: [UIElementInfo]? = nil) -> TargetResolution {
        var needsElements = false, direct = false
        if case .element = t { needsElements = true }
        switch t { case .point, .relative: direct = true; default: break }
        let cursor = input.currentMouseLocation()
        if case .relative = t, cursor == nil { return .failure(Self.pointerUnknown) }
        return checkOnScreen(TargetResolver.resolveMove(t, overlay: overlay.state, cursor: cursor ?? .zero,
                                          elements: elements ?? (needsElements ? ax.actionableElements() : []),
                                          screens: ax.screenRectsCG(), labels: labelSnapshot), checked: direct)
    }

    /// Safety net for pause/quit: release any held mouse button and drop any grid/labels overlay.
    public func releaseAll() {
        input.releaseAll()
        pressed = []
        overlay.hide()
    }
}
