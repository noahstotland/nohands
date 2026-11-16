import XCTest
@testable import NoHandsCore

final class PackDraftTests: XCTestCase {
    private func item(_ title: String, _ menu: String = "File", enabled: Bool = true, sub: Bool = false, key: KeyChord? = nil) -> MenuEntry {
        MenuEntry(title: title, path: [menu], enabled: enabled, hasSubmenu: sub, shortcut: key)
    }

    func testKeptAndLeftOut() throws {
        let cmd: Set<Modifier> = [.command]
        let table: [(entry: MenuEntry, kept: Action?, reason: String?)] = [
            (item("Save As…", key: KeyChord(.s, [.command, .shift])), .pressKey(KeyChord(.s, [.command, .shift])), nil),
            (item("Export as PDF…"), .menuItem("File > Export as PDF…"), nil),
            (item("Zoom Text (+)", "View"), .menuItem("View > Zoom Text (+)"), nil),
            (item("Don’t Save", key: KeyChord(.d, cmd)), .pressKey(KeyChord(.d, cmd)), nil),
            (item("Close Document", key: KeyChord(.w, cmd)), .pressKey(KeyChord(.w, cmd)), nil),
            (item("Print…", enabled: false), nil, "disabled"),
            (item("Open Recent", sub: true), nil, "opens a submenu"),
            (item("  "), nil, "no title"),
            (item("A > B"), nil, "title has >"),
            (item("…"), nil, "no words to say"),
            (item("One two three four five six seven eight nine"), nil, "too long to say"),
            (item("Export as PDF", "Edit"), nil, "same phrase as File > Export as PDF…"),
            (item("Copy", "Edit", key: KeyChord(.c, cmd)), nil, "already a NoHands phrase"),
            (item("New Tab"), nil, "already a NoHands phrase"),
            (item("Delete Note…"), nil, "irreversible"),
            (item("Send", key: KeyChord(.d, [.command, .shift])), nil, "irreversible"),
            (item("Stop"), nil, "rejected: reserved phrase"),
            (item("Show Launcher", key: KeyChord(.space, cmd)), nil, "rejected: blocked chord"),
            (item("Dismiss", key: KeyChord(.w, cmd)), nil, "rejected: "),
        ]
        let result = PackDraft.make(appName: "Notes", bundleID: "com.example.Notes", entries: table.map(\.entry))
        let pack = try XCTUnwrap(result.pack)
        XCTAssertEqual(pack.phrases.count, table.filter { $0.kept != nil }.count)
        XCTAssertEqual(try PackFile.parse(try XCTUnwrap(result.data)), pack)
        let left = Dictionary(uniqueKeysWithValues: result.leftOut.map { ($0.item, $0.reason) })
        XCTAssertEqual(result.leftOut.count, table.filter { $0.reason != nil }.count)
        for row in table {
            let name = (row.entry.path + [row.entry.title.trimmingCharacters(in: .whitespaces)]).joined(separator: " > ")
            if let kept = row.kept {
                XCTAssertEqual(pack.phrases[PackDraft.phrase(row.entry.title)], [kept], name)
            } else {
                XCTAssertTrue(left[name]?.hasPrefix(row.reason ?? "") == true, "\(name): \(left[name] ?? "kept")")
            }
        }
    }

    func testProblemsAndLimit() {
        XCTAssertEqual(PackDraft.make(appName: "X", bundleID: "bad id!", entries: [item("Save")]).problem, .badBundleID)
        XCTAssertEqual(PackDraft.make(appName: "X", bundleID: "com.x.y", entries: [item("Save", enabled: false)]).problem, .nothingToPut)
        let many = (1...205).map { item("Item \($0)") }
        let result = PackDraft.make(appName: "X", bundleID: "com.x.y", entries: many)
        XCTAssertEqual(result.pack?.phrases.count, PackFile.maxCommands)
        XCTAssertEqual(result.leftOut.map(\.reason), Array(repeating: "over the 200 command limit", count: 5))
    }

    func testID() {
        let table: [(bundle: String, id: String)] = [
            ("com.apple.Safari", "com-apple-safari"), ("mail", "mail-custom"), ("a", "app-a"), ("com.example..a--b.", "com-example-a-b"),
            (String(repeating: "a", count: 39) + ".zz", String(repeating: "a", count: 39)),
        ]
        for row in table { XCTAssertEqual(PackDraft.id(for: row.bundle), row.id, row.bundle) }
    }
}
