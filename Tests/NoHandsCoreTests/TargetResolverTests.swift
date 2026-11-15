import Testing
import CoreGraphics
@testable import NoHandsCore

private let grid = GridModel(bounds: CGRect(x: 0, y: 0, width: 1000, height: 800))
private let save = UIElementInfo(id: 1, frame: CGRect(x: 100, y: 100, width: 80, height: 30), title: "Save", role: "AXButton")

@Test func numberedResolvesAgainstVisibleOverlay() {
    #expect(TargetResolver.resolveClick(.numbered(1), overlay: .grid(grid), cursor: .zero, elements: []) == .point(CGPoint(x: 50, y: 50)))
    #expect(TargetResolver.resolveClick(.numbered(1), overlay: .labels([1: save]), cursor: .zero, elements: []) == .point(CGPoint(x: 140, y: 115)))
}

@Test func numberedTargetOutOfRangeIsReported() {
    #expect(TargetResolver.resolveClick(.numbered(150), overlay: .grid(grid), cursor: .zero, elements: []) == .failure("no cell 150"))
    #expect(TargetResolver.resolveClick(.numbered(7), overlay: .none, cursor: .zero, elements: []) == .failure("no grid or labels shown"))
    #expect(TargetResolver.resolveClick(.numbered(2), overlay: .labels([1: save]), cursor: .zero, elements: []) == .failure("no label 2"))
}

@Test func elementAndCursorTargets() {
    #expect(TargetResolver.resolveClick(.element(named: "save"), overlay: .none, cursor: .zero, elements: [save]) == .point(CGPoint(x: 140, y: 115)))
    #expect(TargetResolver.resolveClick(.element(named: "quit"), overlay: .none, cursor: .zero, elements: [save]) == .failure("no element named 'quit'"))
    #expect(TargetResolver.resolveClick(.cursor, overlay: .none, cursor: CGPoint(x: 5, y: 6), elements: []) == .point(CGPoint(x: 5, y: 6)))
    #expect(TargetResolver.resolveMove(.relative(dx: -10, dy: 20), overlay: .none, cursor: CGPoint(x: 100, y: 100), elements: []) == .point(CGPoint(x: 90, y: 120)))
}

@Test func pointAndMoveTargets() {
    let p = CGPoint(x: 7, y: 8)
    #expect(TargetResolver.resolveClick(.point(p), overlay: .none, cursor: .zero, elements: []) == .point(p))
    #expect(TargetResolver.resolveMove(.point(p), overlay: .none, cursor: .zero, elements: []) == .point(p))
    #expect(TargetResolver.resolveMove(.numbered(1), overlay: .grid(grid), cursor: .zero, elements: []) == .point(CGPoint(x: 50, y: 50)))
    #expect(TargetResolver.resolveMove(.element(named: "save"), overlay: .none, cursor: .zero, elements: [save]) == .point(CGPoint(x: 140, y: 115)))
    #expect(TargetResolver.resolveMove(.numbered(3), overlay: .none, cursor: .zero, elements: []) == .failure("no grid or labels shown"))
}

@Test func partlyOffScreenLabelClicksVisiblePart() {
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let edge = UIElementInfo(id: 2, frame: CGRect(x: 950, y: 100, width: 100, height: 40), title: "Edge", role: "AXButton")
    // visible part is x 950...1000 -> center 975
    #expect(TargetResolver.resolveClick(.numbered(1), overlay: .labels([1: edge]), cursor: .zero, elements: [], screens: [screen]) == .point(CGPoint(x: 975, y: 120)))
    #expect(TargetResolver.resolveClick(.element(named: "edge"), overlay: .none, cursor: .zero, elements: [edge], screens: [screen]) == .point(CGPoint(x: 975, y: 120)))
}

@Test func labelResolvesOnlyAgainstExplicitSnapshot() {
    let snap: [Int: UIElementInfo] = [7: save]
    // Even with a grid showing, .label(7) must not become grid cell 7.
    #expect(TargetResolver.resolveClick(.label(7), overlay: .grid(grid), cursor: .zero, elements: [], labels: snap) == .point(CGPoint(x: 140, y: 115)))
    #expect(TargetResolver.resolveClick(.label(7), overlay: .none, cursor: .zero, elements: [], labels: snap) == .point(CGPoint(x: 140, y: 115)))
    #expect(TargetResolver.resolveMove(.label(7), overlay: .none, cursor: .zero, elements: [], labels: snap) == .point(CGPoint(x: 140, y: 115)))
}

@Test func labelNeverFallsBackToGridOrOverlay() {
    #expect(TargetResolver.resolveClick(.label(1), overlay: .grid(grid), cursor: .zero, elements: []) == .failure("no label 1"))
    #expect(TargetResolver.resolveClick(.label(1), overlay: .labels([1: save]), cursor: .zero, elements: []) == .failure("no label 1"))
    #expect(TargetResolver.resolveClick(.label(2), overlay: .none, cursor: .zero, elements: [], labels: [7: save]) == .failure("no label 2"))
    #expect(TargetResolver.resolveMove(.label(1), overlay: .grid(grid), cursor: .zero, elements: []) == .failure("no label 1"))
}

private func el(_ id: Int, _ x: CGFloat, _ y: CGFloat, _ title: String, _ role: String) -> UIElementInfo {
    UIElementInfo(id: id, frame: CGRect(x: x, y: y, width: 100, height: 30), title: title, role: role)
}

/// A browser: menu bar, toolbar, address field, tabs, short nav links, a filter chip, then three results that are
/// each a thumbnail link and a title link with the same name.
private let browser: [UIElementInfo] = [
    el(1, 0, 0, "File", "AXMenuBarItem"), el(2, 120, 0, "Edit", "AXMenuBarItem"),
    el(3, 0, 40, "Back", "AXButton"), el(4, 120, 40, "Reload", "AXButton"), el(5, 240, 40, "Address and search bar", "AXTextField"),
    el(6, 0, 80, "Inbox", "AXTab"), el(7, 120, 80, "Results", "AXTab"),
    el(8, 0, 120, "Home", "AXLink"), el(9, 120, 120, "Shorts", "AXLink"), el(10, 240, 120, "YouTube Home", "AXLink"),
    el(11, 0, 160, "Videos", "AXButton"),
    el(12, 0, 200, "Raptors vs Celtics Full Game", "AXLink"), el(13, 300, 200, "Raptors vs Celtics Full Game", "AXLink"),
    el(14, 0, 300, "Cooking Pasta From Scratch", "AXLink"), el(15, 300, 300, "Cooking Pasta From Scratch", "AXLink"),
    el(16, 0, 400, "Learning Swift In Ten Days", "AXLink"), el(17, 300, 400, "Learning Swift In Ten Days", "AXLink"),
]

@Test func ordinalNameResolvesOverTheShownList() {
    func click(_ name: String, _ elements: [UIElementInfo]) -> TargetResolution {
        let shown = LabelAssigner.assign(elements)
        return TargetResolver.resolveClick(.element(named: name), overlay: .none, cursor: .zero, elements: elements, labels: shown)
    }
    func at(_ id: Int, in elements: [UIElementInfo] = browser) -> TargetResolution {
        .point(elements.first { $0.id == id }!.clickPoint(screens: []))
    }
    let hint = "; say its label number from the list"
    let realTitle = browser + [el(18, 0, 500, "First video", "AXLink")]
    let cases: [(String, [UIElementInfo], TargetResolution)] = [
        ("first video", browser, at(12)),           // not the menu bar, toolbar, tabs, nav links or the "Videos" chip
        ("the second result", browser, at(14)),     // the title link repeating the thumbnail's name is not a result
        ("3rd link", browser, at(10)),
        ("last video", browser, at(16)),
        ("the first one", browser, at(12)),
        ("second button", browser, at(4)),
        ("first tab", browser, at(6)),
        ("first text field", browser, at(5)),
        ("first video", realTitle, at(18, in: realTitle)),   // a real title beats the ordinal reading
        ("tenth video", browser, .failure("no element named 'tenth video'" + hint)),
        ("first video", browser.filter { $0.role != "AXLink" }, .failure("no element named 'first video'" + hint)),
        ("third result", browser.filter { $0.id < 16 }, .failure("no element named 'third result'" + hint)),
        ("quit", browser, .failure("no element named 'quit'")),
        ("first big red video player", browser, .failure("no element named 'first big red video player'")),
    ]
    for (name, elements, want) in cases { #expect(click(name, elements) == want, "\(name)") }
    // Without a snapshot the count runs over the fresh elements; a move takes the same path.
    #expect(TargetResolver.resolveClick(.element(named: "last video"), overlay: .none, cursor: .zero, elements: browser) == at(16))
    #expect(TargetResolver.resolveMove(.element(named: "second video"), overlay: .none, cursor: .zero, elements: browser,
                                       labels: LabelAssigner.assign(browser)) == at(14))
}
