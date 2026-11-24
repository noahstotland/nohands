import Testing
import CoreGraphics
import Foundation
import NoHandsCore
@testable import NoHandsMac

/// An element far below the screen, as the page walk reports it before the scroll.
private let offscreen = UIElementInfo(id: 1_000_001, frame: CGRect(x: 100, y: 5000, width: 200, height: 20),
                                      title: "Raptors vs Celtics", role: "AXLink")

@MainActor @Test func findScrollsToTheMatchAndOnlyTheSpokenFindMovesThePointer() async {
    // (words, movePointer, expected pointer calls)
    let table: [(String, Bool, [String])] = [
        ("the Raptors game", true, ["move:200,310"]),   // the frame after the scroll, not the one the walk saw
        ("the Raptors game", false, []),
    ]
    for (words, move, calls) in table {
        let (x, i, e, _) = make()
        e.pageMatch = offscreen
        #expect(await x.execute([.findOnPage(words, movePointer: move)]) == nil)
        #expect(e.findWords == [words] && e.scrolled == [offscreen] && i.calls == calls, "move \(move)")
        let found = x.takeFound()
        #expect(found?.title == "Raptors vs Celtics" && found?.frame == e.scrollLandsAt && x.takeFound() == nil)
    }
}

@MainActor @Test func aFoundElementIsKeptOnlyWhenTheFindIsTheStepsLastAction() async {
    let table: [([Action], Bool)] = [
        ([.findOnPage("Raptors", movePointer: false)], true),
        ([.findOnPage("Raptors", movePointer: false), .pressKey(KeyChord(.return))], false),
        ([.pressKey(KeyChord(.return)), .findOnPage("Raptors", movePointer: false)], true),
    ]
    for (actions, kept) in table {
        let (x, _, e, _) = make()
        e.pageMatch = offscreen
        #expect(await x.execute(actions) == nil)
        #expect((x.takeFound() != nil) == kept, "\(actions)")
    }
}

@MainActor @Test func findFailuresNameWhatHappened() async {
    let (x, i, e, _) = make()
    // Nothing on the page, and no harness: the message the vision trigger ignores.
    #expect(await x.execute([.findOnPage("Raptors", movePointer: true)]) == "no match for Raptors on this page")
    #expect(e.scrolled.isEmpty && i.calls.isEmpty && x.takeFound() == nil)
    // A match whose scroll never lands.
    e.pageMatch = offscreen
    e.scrollLandsAt = nil
    #expect(await x.execute([.findOnPage("Raptors", movePointer: true)]) == "couldn't scroll to Raptors")
    #expect(i.calls.isEmpty && x.takeFound() == nil)
    // Over the cap, or no words at all: the walk never runs.
    e.findWords = []
    #expect(await x.execute([.findOnPage(String(repeating: "a", count: 121), movePointer: true)]) == "text too long")
    #expect(await x.execute([.findOnPage(" the ", movePointer: true)]) == "nothing to find")
    #expect(e.findWords.isEmpty)
}

@MainActor @Test func aStopDuringTheWalkScrollsNothing() async {
    let (x, i, e, _) = make()
    e.pageMatch = offscreen
    e.onFind = { withUnsafeCurrentTask { $0?.cancel() } }
    let result = await Task { @MainActor in await x.execute([.findOnPage("Raptors", movePointer: true)]) }.value
    #expect(result == ActionExecutor.cancelled)
    #expect(e.scrolled.isEmpty && i.calls.isEmpty && x.takeFound() == nil)
}

@MainActor @Test func withNothingNativeTheHarnessFindsAndScrolls() async {
    let i = FakeInput(), e = FakeElements(), o = FakeOverlay(), h = FakeHarness()
    e.front = "Safari"
    h.findResult = DesktopFindMatch(ref: "@s1:e7", role: "link", name: "Raptors vs Celtics", path: [], disabled: false)
    let x = ActionExecutor(input: i, ax: e, overlay: o, config: AppConfig(), harness: h)
    #expect(await x.execute([.findOnPage("Raptors", movePointer: true)]) == nil)
    #expect(h.calls == ["find:window:Safari:Raptors", "act:scroll-to @s1:e7"] && i.calls.isEmpty)
    let found = x.takeFound()
    #expect(found?.title == "Raptors vs Celtics" && found?.ref == "@s1:e7" && found?.frame == .zero)
}

@Test func theNextObservationListsTheFoundElementFirst() async {
    let f = FakeElements(); f.front = "Safari"
    func button(_ id: Int, _ title: String) -> UIElementInfo {
        UIElementInfo(id: id, frame: CGRect(x: 0, y: id * 40, width: 80, height: 30), title: title, role: "AXButton")
    }
    f.elements = [button(1, "Home"), button(2, "Videos"), button(3, "Raptors vs Celtics")]
    let o = ScreenObserver(ax: f, maxElements: 3)
    func titles(_ found: UIElementInfo?, overlay: OverlayState = .none) async -> ([String], [String]) {
        let r = await o.observe(mode: .command, overlay: overlay, harnessKind: .native, found: found)
        return (r.observation.elements.map(\.title), r.labels.keys.sorted().map { r.labels[$0]!.title })
    }
    var onScreen = offscreen
    onScreen.frame = CGRect(x: 0, y: 120, width: 80, height: 30)
    let listed = (["Raptors vs Celtics", "Home", "Videos"], ["Raptors vs Celtics", "Home", "Videos"])
    let before = (["Home", "Videos", "Raptors vs Celtics"], ["Home", "Videos", "Raptors vs Celtics"])
    #expect(await titles(nil) == before)
    #expect(await titles(onScreen) == listed)                    // already listed: moved up
    var text = offscreen
    text.title = "Scoreboard"
    #expect(await titles(text) == (["Scoreboard", "Home", "Videos"], ["Scoreboard", "Home", "Videos"]))   // not listed: inserted, cap holds
    let badges = [4: button(4, "Save")]
    #expect(await titles(onScreen, overlay: .labels(badges)) == (["Save"], ["Save"]))   // badges keep the numbers the user sees
}
