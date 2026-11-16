import Testing
import NoHandsCore
@testable import NoHandsMac

private struct Fake: MenuNode {
    var title: String?
    var enabled = true
    var children: [any MenuNode] = []
    var commandCharacter: String?
    var virtualKey: Int?
    var modifierMask: Int?
}

@Test func menuShortcutReaderReadsTopLevelItemsWithShortcuts() throws {
    let recent = Fake(title: "Open Recent", children: [Fake(children: [Fake(title: "report.txt")])])
    let save = Fake(title: "Save", commandCharacter: "S", virtualKey: 0, modifierMask: 0)
    let close = Fake(title: "Close", enabled: false, virtualKey: 36, modifierMask: 1)
    let file = Fake(title: "File", children: [Fake(children: [save, Fake(title: nil), recent, close])])
    let bar = Fake(title: nil, children: [
        Fake(title: "Apple", children: [Fake(children: [Fake(title: "Shut Down…")])]), file,
    ])
    #expect(try MenuShortcutReader.entries(menuBar: bar) == [
        MenuEntry(title: "Save", path: ["File"], enabled: true, shortcut: KeyChord(.s, [.command])),
        MenuEntry(title: "Open Recent", path: ["File"], enabled: true, hasSubmenu: true),
        MenuEntry(title: "Close", path: ["File"], enabled: false, shortcut: KeyChord(.return, [.command, .shift])),
    ])
    for empty in [Fake(title: nil), Fake(title: nil, children: [Fake(title: "Apple")])] {
        #expect(throws: MenuShortcutReader.ReadError.noMenuBar) { try MenuShortcutReader.entries(menuBar: empty) }
    }
}
