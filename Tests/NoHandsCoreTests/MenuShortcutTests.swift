import XCTest
@testable import NoHandsCore

final class MenuShortcutTests: XCTestCase {
    func testChordMapping() {
        let cmd: Set<Modifier> = [.command]
        let table: [(char: String?, vk: Int?, mods: Int?, expected: KeyChord?)] = [
            ("S", 0, 0, KeyChord(.s, cmd)),                                  // upper case is not shift
            ("s", nil, nil, KeyChord(.s, cmd)),
            ("S", 0, 1, KeyChord(.s, [.command, .shift])),
            ("t", 0, 3, KeyChord(.t, [.command, .shift, .option])),
            ("1", 0, 4, KeyChord(.one, [.command, .control])),
            (",", 0, 0, KeyChord(.comma, cmd)),
            ("w", 0, 8, KeyChord(.w)),                                       // no-command bit
            ("", 36, 0, KeyChord(.return, cmd)),                             // no character: the virtual key
            (nil, 117, 1, KeyChord(.forwardDelete, [.command, .shift])),
            (nil, 122, 8, KeyChord(.f1)),
            (nil, 126, 0, KeyChord(.up, cmd)),
            ("", 0, 0, nil),                                                 // virtual key 0 is not a listed key
            ("", 8, 0, nil),
            (nil, nil, 0, nil),
            ("+", 0, 0, nil),                                                // not a key the format has
            ("ab", 0, 0, nil),
            ("é", 0, 0, nil),
            ("\u{F700}", 0, 0, nil),                                         // a glyph-only shortcut
        ]
        for row in table {
            XCTAssertEqual(MenuShortcut.chord(char: row.char, virtualKey: row.vk, modifiers: row.mods), row.expected,
                           "\(row.char ?? "nil") \(row.vk ?? -1) \(row.mods ?? -1)")
        }
    }
}
