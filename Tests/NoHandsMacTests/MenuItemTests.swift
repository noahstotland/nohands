import Testing
import Foundation
import NoHandsCore
@testable import NoHandsMac

@MainActor private func makeMenu() -> (ActionExecutor, FakeMenus) {
    let menus = FakeMenus([
        MenuEntry(title: "Bookmark This Tab…", path: ["Bookmarks"], enabled: true),
        MenuEntry(title: "Close Window", path: ["File"], enabled: false),
        MenuEntry(title: "Empty Trash…", path: ["Finder"], enabled: true),
    ])
    let x = ActionExecutor(input: FakeInput(), ax: FakeElements(), overlay: FakeOverlay(), config: AppConfig(),
                           audio: FakeAudio(), menus: menus)
    return (x, menus)
}

@MainActor @Test func menuItemPressesTheNamedItemAndSaysWhyOtherwise() async {
    let (x, menus) = makeMenu()
    // (spoken, result, indexes pressed so far)
    let cases: [(String, String?, [Int])] = [
        ("bookmark this tab", nil, [0]),                                 // pressed natively, no harness needed
        ("shut down", "no menu item called shut down", [0]),             // no match presses nothing
        ("close window", "menu item Close Window is disabled", [0]),     // disabled presses nothing
    ]
    for (spoken, result, pressed) in cases {
        #expect(await x.execute([.menuItem(spoken)]) == result, Comment(rawValue: spoken))
        #expect(menus.pressed == pressed, Comment(rawValue: spoken))
    }
    // A model step (the task loop passes labels) presses only the exact title: "trash" is not "Empty Trash…".
    #expect(await x.execute([.menuItem("trash")], labels: [:]) == "no menu item called trash")
    #expect(menus.pressed == [0])
    menus.pressWorks = false
    #expect(await x.execute([.menuItem("bookmark this tab")]) == "couldn't press menu item Bookmark This Tab…")
}
