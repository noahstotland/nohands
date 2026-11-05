import Testing
import Foundation
@testable import NoHandsCore

private func tab(_ id: String, _ title: String, active: Bool = false) -> BrowserTab { BrowserTab(id: id, title: title, active: active) }
private func win(_ id: String, _ title: String, front: Bool = false, _ tabs: [BrowserTab] = []) -> BrowserWindow {
    BrowserWindow(id: id, title: title, front: front, tabs: tabs)
}

/// The user's browser at task start: one window, two tabs.
private let mine = [win("w1", "Docs", front: true, [tab("t1", "Inbox"), tab("t2", "Docs", active: true)])]

/// Ids of the tabs and windows flagged `new` / `task` in the listing, as "new:t3 w2 task:t4".
private func flags(_ l: TabListing) -> String {
    let tabs = l.windows.flatMap(\.tabs)
    let new = l.windows.filter(\.new).map(\.id) + tabs.filter(\.new).map(\.id)
    let task = tabs.filter(\.task).map(\.id)
    return "new:" + new.sorted().joined(separator: " ") + " task:" + task.joined(separator: " ")
}

@Test func ledgerFlagsOnlyWhatTheTaskOpenedAsNew() {
    let popTab = tab("t9", "You won!")
    let cases: [(String, [BrowserWindow], String, Bool)] = [
        ("unchanged", mine, "new: task:", false),
        ("pop-under tab", [win("w1", "Docs", front: true, mine[0].tabs + [popTab])], "new:t9 task:", false),
        ("rebuilt ids, same titles", [win("x1", "Docs", front: true, [tab("x2", "Inbox"), tab("x3", "Docs", active: true)])], "new: task:", false),
        ("old tab navigated", [win("w1", "News", front: true, [tab("t1", "Inbox"), tab("t2", "News", active: true)])], "new: task:", false),
        ("pop-up window", mine + [win("w2", "Casino", [tab("t7", "Casino")])], "new:t7 w2 task:", false),
        ("tabless pop-up window", mine + [win("w2", "Casino")], "new:w2 task:", false),
        ("user tab navigated in place, then a pop-up window takes focus: the pop-up is not the task's",
         [win("w1", "News", [tab("t1", "Inbox"), tab("t2", "News", active: true)]), win("w2", "Casino", front: true, [tab("c1", "Casino", active: true)])],
         "new:c1 w2 task:t2", true),
        ("new tab inside the user's window is not a new window", [win("w1", "You won!", front: true, mine[0].tabs + [popTab])], "new:t9 task:", false),
    ]
    for (name, windows, want, marked) in cases {
        var ledger = TabLedger()
        ledger.baseline(app: "Chrome", windows: mine)
        if marked { ledger.markTaskTab(app: "Chrome", windows: windows) }
        #expect(flags(ledger.listing(app: "Chrome", windows: windows)) == want, Comment(rawValue: name))
    }
    // The task's tab is new, flagged task, and a later baseline call changes nothing.
    var ledger = TabLedger()
    ledger.baseline(app: "Chrome", windows: mine)
    let after = [win("w1", "Game", front: true, mine[0].tabs.map { tab($0.id, $0.title) } + [tab("t3", "Game", active: true)])]
    ledger.markTaskTab(app: "Chrome", windows: after)
    let again = ledger.baseline(app: "Chrome", windows: after)
    #expect(!again)
    #expect(flags(ledger.listing(app: "Chrome", windows: after)) == "new:t3 task:t3")
    // A browser first seen mid-task is baselined from two reads taken a moment apart (a cold launch lists its
    // windows one at a time); what appears after that is new.
    let early = after
    let late = after + [win("w5", "Restored", [tab("r1", "Restored")])]
    let recordedLate = ledger.baseline(app: "Safari", windows: late, alsoSeen: early)
    #expect(recordedLate)
    #expect(ledger.hasBaseline(app: "Safari"))
    let popped = late + [win("w6", "Casino", [tab("c1", "Casino")])]
    let recordedAgain = ledger.baseline(app: "Safari", windows: popped)
    #expect(!recordedAgain)
    #expect(flags(ledger.listing(app: "Safari", windows: popped)) == "new:c1 w6 task:")
}

@Test func tabsOfAWindowReadEmptyAtBaselineAreTheUsersAndTheTaskTabSkipsAPopUpWindow() {
    // The baseline read ran out of budget for w1: it shows no tabs. Its tabs, seen later, are the user's.
    var ledger = TabLedger()
    ledger.baseline(app: "Chrome", windows: [win("w1", "Docs", front: true), win("w2", "Mail", [tab("m1", "Mail")])])
    let later = [win("w1", "Docs", front: true, [tab("t1", "Inbox"), tab("t2", "Docs", active: true)]), win("w2", "Mail", [tab("m1", "Mail")])]
    #expect(flags(ledger.listing(app: "Chrome", windows: later)) == "new: task:")
    let recorded = ledger.baseline(app: "Chrome", windows: later)
    #expect(!recorded)
    // Once w1 has been read, a tab that then appears in it is new; so is one in the window that was populated all along.
    let popped = [win("w1", "Docs", front: true, later[0].tabs + [tab("t9", "You won!")]), win("w2", "Mail", [tab("m1", "Mail"), tab("m9", "Ad")])]
    #expect(flags(ledger.listing(app: "Chrome", windows: popped)) == "new:m9 t9 task:")

    // A window whose baseline read was cut short (more tabs than the read listed) never has new tabs.
    var cut = TabLedger()
    cut.baseline(app: "Chrome", windows: [BrowserWindow(id: "w1", title: "Docs", front: true, tabs: [tab("t1", "Inbox"), tab("t2", "Docs", active: true)], complete: false)])
    let more = [BrowserWindow(id: "w1", title: "Docs", front: true, tabs: [tab("t1", "Inbox"), tab("t2", "Docs", active: true), tab("t3", "Far right")], complete: false)]
    #expect(flags(cut.listing(app: "Chrome", windows: more)) == "new: task:")
    cut.baseline(app: "Chrome", windows: more)
    #expect(flags(cut.listing(app: "Chrome", windows: more + [win("w2", "Casino", [tab("c1", "Casino")])])) == "new:c1 w2 task:")

    // A pop-up window that took focus is not the task's tab: the new active tab in the user's window is.
    ledger.markTaskTab(app: "Chrome", windows: [win("w3", "Casino", front: true, [tab("c1", "Casino", active: true)]),
                                                 win("w1", "Game", [tab("t1", "Inbox"), tab("t8", "Game", active: true)]), popped[1]])
    let now = [win("w3", "Casino", front: true, [tab("c1", "Casino", active: true)]), win("w1", "Game", [tab("t1", "Inbox"), tab("t8", "Game", active: true)])]
    #expect(flags(ledger.listing(app: "Chrome", windows: now)) == "new:c1 t8 w3 task:t8")
}

@Test func tabGuardClosesOnlyNewTabsAndWindowsTheTaskDidNotNavigate() {
    var ledger = TabLedger()
    ledger.baseline(app: "Chrome", windows: mine)
    let now = [win("w1", "Game", front: true, [tab("t1", "Inbox"), tab("t2", "Docs"), tab("t3", "Game", active: true), tab("t4", "You won!")]),
               win("w2", "Casino", [tab("t5", "Casino")])]
    ledger.markTaskTab(app: "Chrome", windows: now)
    let l = ledger.listing(app: "Chrome", windows: now)   // tabs 1 Inbox, 2 Docs, 3 Game (task), 4 You won!, 5 Casino
    let cases: [(Action, String, Bool)] = [
        (.closeTab(4), "open the game", false),
        (.closeWindow(2), "open the game", false),
        (.closeTab(1), "open the game", true),
        (.closeTab(3), "open the game", true),
        (.closeWindow(1), "open the game", true),
        (.closeTab(9), "open the game", true),
        (.closeWindow(9), "close everything", true),
        (.closeTab(1), "close the inbox tab", false),
        (.closeTab(3), "close the game tab", false),
        (.selectTab(1), "open the game", false),
        (.selectTab(9), "open the game", true),
    ]
    for (action, goal, blocked) in cases {
        #expect((TabGuard.blocked([action], listing: l, goal: goal) != nil) == blocked, Comment(rawValue: "\(action) / \(goal)"))
    }
    #expect(TabGuard.blocked([.closeTab(1)], listing: nil, goal: "x") == "blocked: no tab 1")
}

@Test func tabsBlockShowsFlagsCapsAndCleansTitles() {
    var ledger = TabLedger()
    let many = (1...25).map { tab("o\($0)", "Old \($0)") }
    ledger.baseline(app: "Chrome", windows: [win("w1", "Old 1", front: true, many), win("w9", "Other", [tab("z1", "Other"), tab("z2", "Other 2")])])
    let long = String(repeating: "x", count: 100)
    let now = [win("w1", "Game", front: true, many + [tab("n1", "Game", active: true), tab("n2", "Bad\n\"title\" \(long)")]),
               win("w9", "Other", [tab("z1", "Other"), tab("z2", "Other 2")]),
               win("w2", "Casino", [tab("n3", "Casino")])]
    ledger.markTaskTab(app: "Chrome", windows: now)
    let l = ledger.listing(app: "Chrome", windows: now)
    var o = ScreenObservation(app: "Chrome", mode: .command)
    o.tabs = l
    let s = ClaudeRequestBuilder.userMessage(request: StepRequest(goal: "g", step: 1, maxSteps: 3, history: [], observation: o))
    #expect(s.contains("Tab rules") && s.range(of: "Tab rules")!.lowerBound < s.range(of: "Tabs (Chrome):")!.lowerBound)
    let lines = s.components(separatedBy: "\n")
    let at = lines.firstIndex(of: "Tabs (Chrome):")!
    #expect(lines[at + 1] == "  window 1 (front) \"Game\"")
    #expect(lines[at + 2] == "    tab 1 \"Old 1\"" && lines[at + 21] == "    tab 20 \"Old 20\"")
    #expect(lines[at + 22] == "    tab 21 \"Game\" (active, task, new)")
    #expect(lines[at + 23] == "    tab 22 \"Bad 'title' " + String(repeating: "x", count: 60 - "Bad 'title' ".count) + "\" (new)")
    #expect(lines[at + 24] == "    +5 other tabs")
    #expect(lines[at + 25] == "  window 2 (new) \"Casino\"" && lines[at + 26] == "    tab 23 \"Casino\" (new)")
    #expect(lines[at + 27] == "  +1 other windows")
    #expect(l.tab(21)?.id == "n1" && l.window(2)?.id == "w2" && l.tab(99) == nil)
    // Past ten new tabs and windows beyond the front window's, the rest are only counted.
    var capped = TabLedger()
    capped.baseline(app: "Chrome", windows: mine)
    let flood = (1...12).map { win("p\($0)", "Ad \($0)", [tab("a\($0)", "Ad \($0)")]) }
    let floodList = capped.listing(app: "Chrome", windows: mine + flood)
    #expect(floodList.windows.count == 11 && floodList.hiddenNew == 2)
    #expect(floodList.rendered.hasSuffix("\n  +2 more new"))
    let plain = ScreenObservation(app: "Finder", mode: .command)
    #expect(!ClaudeRequestBuilder.userMessage(request: StepRequest(goal: "g", step: 1, maxSteps: 3, history: [], observation: plain)).contains("Tab"))
}

@Test func tabActionsDecodeAndRejectABadNumber() throws {
    let ok = #"{"actions":[{"kind":"close_tab","target_number":3},{"kind":"close_window","target_number":2},{"kind":"select_tab","target_number":1}]}"#
    #expect(try IntentDecoder.actions(fromPayloadText: ok) == [.closeTab(3), .closeWindow(2), .selectTab(1)])
    let bad = #"{"actions":[{"kind":"close_tab"},{"kind":"close_window","target_number":0},{"kind":"select_tab","target_number":-1}]}"#
    #expect(try IntentDecoder.actions(fromPayloadText: bad) == [])
}

@Test func mediaGoalsGetTheLongerStepCap() throws {
    for goal in ["Open the Raptors game on streamsite", "watch the latest veritasium video", "play some jazz", "put on the match"] {
        #expect(MediaGoal.matches(goal), Comment(rawValue: goal))
    }
    for goal in ["open gmail", "scroll down", "close the tab"] { #expect(!MediaGoal.matches(goal), Comment(rawValue: goal)) }
    #expect(try AppConfig.load(from: nil, environment: [:]).maxMediaTaskSteps == 24)
    #expect(try AppConfig.load(from: Data(#"{"maxMediaTaskSteps":0}"#.utf8), environment: [:]).maxMediaTaskSteps == 1)
    #expect(try AppConfig.load(from: Data(#"{"maxMediaTaskSteps":99}"#.utf8), environment: [:]).maxMediaTaskSteps == 30)
    #expect(try AppConfig.load(from: Data(#"{"maxMediaTaskSteps":18}"#.utf8), environment: [:]).maxMediaTaskSteps == 18)
}
