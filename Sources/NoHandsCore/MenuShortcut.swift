import Foundation

/// A menu item's keyboard shortcut as Accessibility reports it, turned into a key chord the pack format can hold.
public enum MenuShortcut {
    private static let characters: [Character: Key] = {
        var table: [Character: Key] = ["-": .minus, "=": .equal, "[": .leftBracket, "]": .rightBracket, ";": .semicolon,
                                       "'": .quote, ",": .comma, ".": .period, "/": .slash, "\\": .backslash, "`": .grave]
        for key in Key.allCases where key.rawValue.count == 1 { table[Character(key.rawValue)] = key }
        for (digit, key) in zip("0123456789", [Key.zero, .one, .two, .three, .four, .five, .six, .seven, .eight, .nine]) {
            table[digit] = key
        }
        return table
    }()

    /// The keys a menu can show without a character: the reverse of `Key.keyCode`.
    private static let virtualKeys: [Int: Key] = {
        let named: Set<Key> = [.return, .tab, .space, .delete, .forwardDelete, .escape, .up, .down, .left, .right, .home, .end,
                               .pageUp, .pageDown, .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10, .f11, .f12]
        return Dictionary(uniqueKeysWithValues: named.map { (Int($0.keyCode), $0) })
    }()

    /// The chord for `kAXMenuItemCmdChar`, `kAXMenuItemCmdVirtualKey` and `kAXMenuItemCmdModifiers`, or nil when there
    /// is none or it is not one the format can say. A character wins over the virtual key (which is 0 beside a
    /// character); an upper-case character does not imply shift. Modifier bits: 1 shift, 2 option, 4 control, 8 no command.
    public static func chord(char: String?, virtualKey: Int?, modifiers: Int?) -> KeyChord? {
        let key: Key
        if let char, !char.isEmpty {
            let lower = char.lowercased()
            guard lower.count == 1, let found = characters[lower.first!] else { return nil }
            key = found
        } else if let virtualKey, let found = virtualKeys[virtualKey] {
            key = found
        } else {
            return nil
        }
        let mask = modifiers ?? 0
        var set = Set<Modifier>()
        if mask & 8 == 0 { set.insert(.command) }
        if mask & 1 != 0 { set.insert(.shift) }
        if mask & 2 != 0 { set.insert(.option) }
        if mask & 4 != 0 { set.insert(.control) }
        return KeyChord(key, set)
    }
}
