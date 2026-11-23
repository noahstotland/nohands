import Testing
import CoreGraphics
@testable import NoHandsCore

private func el(_ title: String, _ role: String) -> UIElementInfo {
    UIElementInfo(id: 0, frame: .zero, title: title, role: role)
}

private let screen: [Int: UIElementInfo] = [
    1: el("Page", "AXLink"), 2: el("Edit", "AXButton"), 3: el("Profile", "AXLink"), 4: el("Edit", "AXMenuBarItem"),
    5: el("File", "AXMenuBarItem"), 6: el("Save", "AXMenuItem"),
]
private let bar = ["Edit", "File", "History"]
private func click(_ t: ClickTarget) -> [Action] { [.click(t, button: .left, count: 1)] }

@Test func menuBarClicksAreBlockedUnlessTheGoalAllowsThem() {
    let cases: [(actions: [Action], goal: String, badges: Bool, blocked: Bool)] = [
        (click(.label(4)), "open the latest video", false, true),          // by number
        (click(.element(named: "history")), "open the latest video", false, true),   // by name, even without the item in the list
        (click(.label(1)), "open the latest video", false, false),         // a page link
        (click(.label(6)), "open the latest video", false, false),         // a menu item that is not in the bar
        (click(.label(4)), "open the edit menu", false, false),            // menu word
        (click(.label(4)), "click edit then click copy", false, false),    // the title's own words
        (click(.label(4)), "open the profile", false, true),               // "edit" is not in the goal
        (click(.element(named: "File")), "open the files menubar", false, false),
        (click(.label(4)), "open the latest video", true, false),          // badges showing: the user picked the number
        (click(.label(99)), "open the latest video", false, false),        // unknown number is the executor's problem
        ([.pressMouse(.left), .scroll(.down, amount: 3)], "open the latest video", false, false),
    ]
    for c in cases {
        let message = MenuBarGuard.blocked(c.actions, labels: screen, menuBarTitles: bar, goal: c.goal, badgesShowing: c.badges)
        #expect((message != nil) == c.blocked, "\(c.actions) \(c.goal)")
    }
    #expect(MenuBarGuard.blocked(click(.label(4)), labels: screen, menuBarTitles: bar, goal: "x", badgesShowing: false)
        == "label 4 is the \"Edit\" menu bar item, not a page element")
    #expect(MenuBarGuard.blocked(click(.element(named: "history")), labels: screen, menuBarTitles: bar, goal: "x", badgesShowing: false)
        == "\"History\" is a menu bar item, not a page element")
}

@Test func namedClicksBindToThePageElementTheModelWasShown() {
    func bound(_ actions: [Action], goal: String = "open the latest video") -> [Action] {
        ElementNames.bind(actions, labels: screen, menuBarTitles: bar, goal: goal)
    }
    let named = click(.element(named: "edit"))
    let cases: [(actions: [Action], goal: String, expected: [Action])] = [
        (named, "open the latest video", click(.label(2))),                              // page button beats the menu-bar item
        (click(.element(named: " EDIT ")), "open the latest video", click(.label(2))),   // trimmed, any case
        (click(.element(named: "Pro")), "open the latest video", click(.element(named: "Pro"))),   // exact only
        (click(.element(named: "File")), "open the latest video", click(.element(named: "File"))), // only a menu-bar match
        (named, "click edit, click copy", named),                                         // the goal allows the menu bar item
        ([.scroll(.down, amount: 3)] + named, "open the latest video", [.scroll(.down, amount: 3)] + named),   // not first
        (named + named, "open the latest video", click(.label(2)) + named),               // only the first
        (click(.element(named: "Nothing")), "open the latest video", click(.element(named: "Nothing"))),
        ([.click(.element(named: "edit"), button: .right, count: 2)], "open the latest video",
         [.click(.label(2), button: .right, count: 2)]),
    ]
    for c in cases { #expect(bound(c.actions, goal: c.goal) == c.expected, "\(c.actions) \(c.goal)") }
}

@Test func menuBarClickInIsBlockedForATopLevelMenuTheGoalDoesNotAllow() {
    func run(_ name: String, goal: String, badges: Bool = false) -> Bool {
        MenuBarGuard.blocked([.clickIn(.menubar, name: name)], labels: screen, menuBarTitles: bar, goal: goal, badgesShowing: badges) != nil
    }
    #expect(run("History", goal: "open the latest video"))
    #expect(run("History", goal: "open the latest video", badges: true))
    #expect(!run("History", goal: "open the history menu"))
    #expect(!run("Save", goal: "open the latest video"))   // not a top-level title
}
