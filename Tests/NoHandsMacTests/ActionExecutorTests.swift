import Testing
import CoreGraphics
import Foundation
import NoHandsCore
@testable import NoHandsMac

@MainActor @Test func stopsAtFirstFailure() async {
    let (x, i, _, o) = make()
    let r = await x.execute([.typeText("a"), .zoomGrid(3), .typeText("b")])
    #expect(r == "no grid shown")
    #expect(i.calls == ["type:a"])
    #expect(o.huds.isEmpty)   // failures go on the prompt's row, not a notice
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
    #expect(i.calls == ["down", "releaseAll"])
}

@MainActor @Test func spokenStopDoesNotReleaseMidDrag() async {
    let (x, i, _, _) = make()
    x.dragInFlight = true
    x.releaseHeldButton()
    #expect(i.calls.isEmpty)   // the drag's own mouse-up or catch releases
    x.dragInFlight = false
    x.releaseHeldButton()
    #expect(i.calls == ["releaseAll"])
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

private let reload = UIElementInfo(id: 1, frame: CGRect(x: 100, y: 100, width: 80, height: 30), title: "Reload", role: "AXButton")

@MainActor @Test func llmLabelClickHitsElementCentreWithNoOverlay() async {
    let (x, i, _, _) = make()
    #expect(await x.execute([.click(.label(7), button: .left, count: 1)], labels: [7: reload]) == nil)
    #expect(i.calls == ["click:140,115"])
}

@MainActor @Test func llmLabelClickIgnoresGridCellOfSameNumber() async {
    let (x, i, _, o) = make()
    _ = await x.execute([.showGrid])
    #expect(await x.execute([.click(.label(7), button: .left, count: 1)], labels: [7: reload]) == nil)
    #expect(i.calls == ["click:140,115"])                  // not grid cell 7
    if case .grid = o.state {} else { Issue.record("grid should still be showing") }
    #expect(await x.execute([.click(.label(7), button: .left, count: 1)]) == "no label 7")   // no snapshot -> fails
}

@MainActor @Test func pointerUnknownFailsCursorDependentActions() async {
    let (x, i, _, _) = make()
    i.location = nil
    #expect(await x.execute([.click(.cursor, button: .left, count: 1)]) == "pointer position unknown")
    #expect(await x.execute([.moveCursor(.relative(dx: 1, dy: 1))]) == "pointer position unknown")
    #expect(await x.execute([.pressMouse(.left)]) == "pointer position unknown")
    #expect(await x.execute([.showGrid]) == "pointer position unknown")
    #expect(await x.execute([.click(.point(CGPoint(x: 5, y: 5)), button: .left, count: 1)]) == nil)
}

@MainActor @Test func releaseAllReleasesInputAndHidesOverlay() async {
    let (x, i, _, o) = make()
    _ = await x.execute([.showGrid])
    x.releaseAll()
    #expect(i.calls == ["releaseAll"])
    #expect(o.state == .none)
}

@MainActor @Test func cancelledExecutionStopsBetweenActions() async {
    let (ex, input, _, _) = make()
    let task = Task { await ex.execute([.wait(ms: 5000), .typeText("late")]) }
    try? await Task.sleep(for: .milliseconds(50))
    task.cancel()
    #expect(await task.value == "cancelled")
    #expect(input.calls.isEmpty)
}

@MainActor @Test func openURLUsesDefaultBrowserOrNamedApp() async {
    let (x, i, e, _) = make()
    let yt = URL(string: "https://www.youtube.com")!
    e.defaultBrowser = "Safari"; e.front = "Safari"
    #expect(await x.execute([.openURL(yt, app: nil)]) == nil)
    #expect(e.opened.map(\.app) == [nil])
    #expect(e.opened.first?.url == yt)
    // Named browser that exists: opened there, then further actions wait for it to be frontmost.
    e.apps = ["Google Chrome"]; e.front = "Google Chrome"
    #expect(await x.execute([.openURL(yt, app: "Google Chrome"), .typeText("x")]) == nil)
    #expect(i.calls == ["type:x"])
    // Named browser that does not exist.
    #expect(await x.execute([.openURL(yt, app: "Nope")]) == "no app named Nope")
    // Not in front in time and more actions follow: fail before typing anywhere.
    e.front = "Finder"
    #expect(await x.execute([.openURL(yt, app: "Google Chrome"), .typeText("y")]) == "app did not come to front")
    #expect(i.calls == ["type:x"])
}

@MainActor @Test func openAppWaitsForAWindowBeforeTyping() async {
    let (x, i, e, _) = make()
    e.apps = ["Google Chrome"]; e.front = "Google Chrome"
    // Chrome launched cold: frontmost but no window yet. Keystrokes would go nowhere, so fail instead.
    e.hasWindow = false
    #expect(await x.execute([.openApp("Google Chrome"), .pressKey(KeyChord(.l, [.command]))]) == "no window in Google Chrome")
    #expect(i.calls.isEmpty)
    // Last action: no window needed.
    #expect(await x.execute([.openApp("Google Chrome")]) == nil)
    // Window appears while waiting.
    e.hasWindow = true
    e.windowAppearsAfterChecks = 2
    #expect(await x.execute([.openApp("Google Chrome"), .pressKey(KeyChord(.l, [.command]))]) == nil)
    #expect(i.calls.count == 1)
}

@MainActor @Test func moveWindowUsesTheScreenHoldingTheWindow() async {
    let (x, _, e, o) = make()
    e.visibleScreens = [CGRect(x: 0, y: 25, width: 1000, height: 775), CGRect(x: 1000, y: 0, width: 2000, height: 1000)]
    e.windowFrame = CGRect(x: 1200, y: 100, width: 400, height: 300)   // on the second screen
    #expect(await x.execute([.moveWindow(.leftHalf)]) == nil)
    #expect(e.placed == [CGRect(x: 1000, y: 0, width: 1000, height: 1000)])
    // Centre keeps the size; a window on the first screen uses that screen.
    e.windowFrame = CGRect(x: 100, y: 100, width: 400, height: 300)
    #expect(await x.execute([.moveWindow(.center)]) == nil)
    #expect(e.placed.last == CGRect(x: 300, y: 263, width: 400, height: 300))
    // A stale overlay is dropped once the window moved.
    o.state = .labels([:])
    #expect(await x.execute([.moveWindow(.maximize)]) == nil)
    #expect(o.state == .none)
    #expect(e.placed.last == CGRect(x: 0, y: 25, width: 1000, height: 775))
}

@MainActor @Test func moveWindowFailures() async {
    let (x, _, e, o) = make()
    e.windowFrame = nil
    #expect(await x.execute([.moveWindow(.leftHalf)]) == "no window to move")
    e.windowFrame = CGRect(x: 100, y: 100, width: 400, height: 300)
    e.acceptsMove = false
    #expect(await x.execute([.moveWindow(.leftHalf)]) == "couldn't move window")
    e.acceptsMove = true
    e.visibleScreens = []
    #expect(await x.execute([.moveWindow(.leftHalf)]) == "no screen")
    #expect(e.placed.isEmpty)
}

@Test func screenHoldingWindowPrefersCentreThenOverlap() {
    let a = CGRect(x: 0, y: 0, width: 1000, height: 800), b = CGRect(x: 1000, y: 0, width: 1000, height: 800)
    #expect(ActionExecutor.screen(holding: CGRect(x: 900, y: 0, width: 400, height: 100), among: [a, b]) == b)
    #expect(ActionExecutor.screen(holding: CGRect(x: 700, y: 0, width: 400, height: 100), among: [a, b]) == a)
    // Centre off every screen (window dragged above the top edge): the biggest overlap wins.
    #expect(ActionExecutor.screen(holding: CGRect(x: 1500, y: -500, width: 400, height: 600), among: [a, b]) == b)
    #expect(ActionExecutor.screen(holding: CGRect(x: 5000, y: 5000, width: 10, height: 10), among: [a, b]) == a)
    #expect(ActionExecutor.screen(holding: a, among: []) == nil)
}

@MainActor @Test func searchPrefersTheSearchBoxThenTheResultsPageThenTheAddressBar() async {
    // The page's (or app's) own search box: click it, replace its text, Return.
    let (x, i, e, _) = make()
    e.front = "Google Chrome"
    e.url = "https://www.youtube.com/"
    e.searchBox = CGRect(x: 200, y: 120, width: 200, height: 30)
    #expect(await x.execute([.search("outdoor boys")]) == nil)
    #expect(i.calls == ["click:300,135", "press", "type:outdoor boys", "press"])

    // A box outside the focused window is never clicked (Cmd-A and typing would land elsewhere): next route.
    i.calls = []
    e.searchBox = CGRect(x: 700, y: 10, width: 200, height: 30)
    #expect(await x.execute([.search("outdoor boys")]) == nil)
    #expect(i.calls == ["press", "type:https://www.youtube.com/results?search_query=outdoor%20boys", "press"])

    // No box reachable but a site with a known results page: navigate the current tab to it.
    i.calls = []
    e.searchBox = nil
    #expect(await x.execute([.search("outdoor boys")]) == nil)
    #expect(i.calls == ["press", "type:https://www.youtube.com/results?search_query=outdoor%20boys", "press"])

    // Any other page in a browser: the address bar searches the web.
    i.calls = []
    e.url = "https://example.org/"
    #expect(await x.execute([.search("outdoor boys")]) == nil)
    #expect(i.calls == ["press", "type:outdoor boys", "press"])
    i.calls = []
    e.url = nil
    e.isBrowser = true   // a new-tab page with no web area yet
    #expect(await x.execute([.search("cats")]) == nil)
    #expect(i.calls == ["press", "type:cats", "press"])

    // Text a browser would run or open instead of search for is refused on every search route.
    i.calls = []
    #expect(await x.execute([.search("javascript:alert(1)")]) == "can't search for that")
    #expect(i.calls.isEmpty)

    // An app with nothing to search: a failure, and no keystrokes into whatever is focused.
    i.calls = []
    e.isBrowser = false
    e.front = "Calculator"
    #expect(await x.execute([.search("cats")]) == "nothing to search in Calculator")
    #expect(i.calls.isEmpty)
}

@MainActor @Test func searchSiteSearchesTheOpenSiteElseOpensItsResultsPage() async {
    let (x, i, e, _) = make()
    let action = Action.searchSite("outdoor boys", site: "youtube.com")
    let results = URL(string: "https://www.youtube.com/results?search_query=outdoor%20boys")!
    e.front = "Google Chrome"; e.isBrowser = true; e.defaultBrowser = "Safari"

    // The site is in front with a search box: click it and type there; nothing is opened.
    e.url = "https://www.youtube.com/watch?v=1"
    e.searchBox = CGRect(x: 200, y: 120, width: 200, height: 30)
    #expect(await x.execute([action]) == nil)
    #expect(i.calls == ["click:300,135", "press", "type:outdoor boys", "press"])
    #expect(e.opened.isEmpty)

    // In front with no box reachable: the results URL goes into the current tab's address bar.
    i.calls = []
    e.searchBox = nil
    #expect(await x.execute([action]) == nil)
    #expect(i.calls == ["press", "type:\(results.absoluteString)", "press"])
    #expect(e.opened.isEmpty)

    // Another site, or a page-less app, in front: the results page opens in the default browser, no keystrokes.
    for (front, url) in [("Google Chrome", "https://example.org/"), ("Finder", nil)] as [(String, String?)] {
        i.calls = []; e.opened = []
        e.front = front; e.url = url; e.searchBox = CGRect(x: 200, y: 120, width: 200, height: 30)
        #expect(await x.execute([action]) == nil, "\(front)")
        #expect(e.opened.map(\.url) == [results] && e.opened.map(\.app) == [nil], "\(front)")
        #expect(i.calls.isEmpty, "\(front)")
    }

    // Text a browser would run or open is refused on both paths: nothing typed or opened.
    i.calls = []; e.opened = []
    for url in ["https://www.youtube.com/", "https://example.org/"] {
        e.url = url
        #expect(await x.execute([.searchSite("javascript:alert(1)", site: "youtube.com")]) == "can't search for that")
    }
    #expect(i.calls.isEmpty && e.opened.isEmpty)
}

@MainActor @Test func tabWithoutACloseButtonIsClosedByShortcutOnlyOnceItIsSelected() async {
    var ledger = TabLedger()
    let old = BrowserTab(id: "t0", title: "Inbox", active: true)
    ledger.baseline(app: "Chrome", windows: [BrowserWindow(id: "w1", title: "Inbox", front: true, tabs: [old])])
    let listing = ledger.listing(app: "Chrome", windows: [BrowserWindow(id: "w1", title: "Inbox", front: true,
                                                                         tabs: [old, BrowserTab(id: "t1", title: "Ad")])])
    // (selecting works, tab is in the front app's focused window, result, tabs selected)
    let table: [(Bool, Bool, String?, [String])] = [
        (true, true, nil, ["t1"]),
        (false, true, "couldn't select that tab", ["t1"]),
        (true, false, "can't close that tab", []),   // a tab in another window: command-W would close that window's tab
    ]
    for (selects, inFront, want, selected) in table {
        let (ex, input, ax, _) = make()
        ax.isBrowser = true; ax.tabHasNoCloseButton = true; ax.selectingWorks = selects; ax.tabInFrontWindow = inFront
        #expect(await ex.execute([.closeTab(2)], tabs: listing) == want)
        #expect(ax.selectedTabs == selected)
        #expect(input.calls == (want == nil ? ["press"] : []))   // command-W goes out only for the tab that is selected in the front window
    }
    let (ex, _, ax, _) = make()
    #expect(await ex.execute([.closeTab(5)], tabs: listing) == "no tab 5" && ax.closedTabs.isEmpty)
}

@MainActor @Test func namedClickRewalksAfterExposure() async {
    let subscribe = UIElementInfo(id: 1, frame: CGRect(x: 100, y: 200, width: 80, height: 30), title: "Subscribe", role: "AXButton")
    let click = [Action.click(.element(named: "subscribe"), button: .left, count: 1)]
    for exposed in [true, false] {
        let i = FakeInput(), e = FakeElements(), o = FakeOverlay()
        e.walkLists = [[], [subscribe]]
        e.exposeOnNextWalk = exposed
        let x = ActionExecutor(input: i, ax: e, overlay: o, config: AppConfig(), exposureSettle: .zero)
        let result = await x.execute(click)
        if exposed {
            #expect(result == nil && i.calls == ["click:140,215"] && e.walks == 2)
        } else {
            #expect(result == "no element named 'subscribe'" && i.calls.isEmpty && e.walks == 1)
        }
    }
}

@MainActor @Test func stopDuringTheExposureWaitStopsTheClick() async {
    let subscribe = UIElementInfo(id: 1, frame: CGRect(x: 100, y: 200, width: 80, height: 30), title: "Subscribe", role: "AXButton")
    let i = FakeInput(), e = FakeElements(), o = FakeOverlay()
    e.walkLists = [[subscribe]]   // the thin first walk already holds a match
    e.exposeOnNextWalk = true
    let x = ActionExecutor(input: i, ax: e, overlay: o, config: AppConfig(), exposureSettle: .seconds(5))
    let task = Task { @MainActor in await x.execute([.click(.element(named: "subscribe"), button: .left, count: 1)]) }
    try? await Task.sleep(for: .milliseconds(50))
    task.cancel()
    #expect(await task.value == ActionExecutor.cancelled)
    #expect(i.calls.isEmpty)
}

@MainActor @Test func tabCommandsActOnlyInABrowserAndReadTheStripOnlyWhenTheyMust() async {
    let strip = [BrowserTab(id: "t1", title: "Inbox"), BrowserTab(id: "t2", title: "YouTube", active: true), BrowserTab(id: "t3", title: "GitHub")]
    // (action, in a browser, tabs, failure, tab ids pressed, keys pressed)
    let table: [(Action, Bool, [BrowserTab], String?, [String], [String])] = [
        (.goToTab(.named("github")), true, strip, nil, ["t3"], []),
        (.goToTab(.named("gmail")), true, strip, "no tab called gmail", [], []),
        (.goToTab(.number(3)), true, strip, nil, [], ["press"]),          // command-3: no tab read
        (.goToTab(.last), true, [], nil, [], ["press"]),                  // command-9 works where the strip is hidden
        (.goToTab(.number(12)), true, strip, "only 3 tabs", [], []),
        (.goToTab(.number(12)), true, [], "can't read the tabs in Chrome", [], []),
        (.goToTab(.number(3)), false, strip, "no browser in front", [], []),   // Finder's command-3 stays unpressed
        (.goToTab(.named("github")), false, strip, "no browser in front", [], []),
        (.closeOtherTabs, false, strip, "no browser in front", [], []),
        (.listTabs, false, strip, "no browser in front", [], []),
    ]
    for (action, inBrowser, tabs, want, selected, keys) in table {
        let (ex, input, ax, _) = make()
        ax.isBrowser = inBrowser; ax.front = "Chrome"
        ax.browser = [BrowserWindow(id: "w1", title: "YouTube", front: true, tabs: tabs)]
        #expect(await ex.execute([action]) == want, "\(action)")
        #expect(ax.selectedTabs == selected && input.calls == keys, "\(action)")
    }
    let (ex, _, ax, overlay) = make()
    ax.isBrowser = true; ax.front = "Chrome"; ax.browser = [BrowserWindow(id: "w1", title: "", front: true, tabs: strip)]
    #expect(await ex.execute([.listTabs]) == nil && overlay.huds == ["1 Inbox \u{00B7} 2* YouTube \u{00B7} 3 GitHub"])
}

@MainActor @Test func aSpokenStopDuringTheTabReadKeepsTheTabUnpressed() async {
    let (ex, _, ax, _) = make()
    ax.isBrowser = true; ax.front = "Chrome"
    ax.browser = [BrowserWindow(id: "w1", title: "", front: true, tabs: [BrowserTab(id: "t1", title: "YouTube")])]
    ax.onBrowserRead = { Thread.sleep(forTimeInterval: 0.2) }
    let task = Task { @MainActor in await ex.execute([.goToTab(.named("youtube"))]) }
    try? await Task.sleep(for: .milliseconds(50))
    task.cancel()
    #expect(await task.value == ActionExecutor.cancelled && ax.selectedTabs.isEmpty)
}
