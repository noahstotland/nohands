import Foundation

public enum Modifier: String, Codable, Sendable, CaseIterable { case command, shift, option, control, function }

public enum Key: String, Codable, Sendable, CaseIterable {
    case a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r, s, t, u, v, w, x, y, z
    case zero, one, two, three, four, five, six, seven, eight, nine
    case `return`, tab, space, delete, forwardDelete, escape
    case up, down, left, right, home, end, pageUp, pageDown
    case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12
    case minus, equal, leftBracket, rightBracket, semicolon, quote, comma, period, slash, backslash, grave

    /// Carbon `kVK_*` virtual key codes (ANSI layout), hand-written to avoid importing Carbon.
    public var keyCode: UInt16 {
        switch self {
        case .a: 0
        case .s: 1
        case .d: 2
        case .f: 3
        case .h: 4
        case .g: 5
        case .z: 6
        case .x: 7
        case .c: 8
        case .v: 9
        case .b: 11
        case .q: 12
        case .w: 13
        case .e: 14
        case .r: 15
        case .y: 16
        case .t: 17
        case .one: 18
        case .two: 19
        case .three: 20
        case .four: 21
        case .six: 22
        case .five: 23
        case .equal: 24
        case .nine: 25
        case .seven: 26
        case .minus: 27
        case .eight: 28
        case .zero: 29
        case .rightBracket: 30
        case .o: 31
        case .u: 32
        case .leftBracket: 33
        case .i: 34
        case .p: 35
        case .return: 36
        case .l: 37
        case .j: 38
        case .quote: 39
        case .k: 40
        case .semicolon: 41
        case .backslash: 42
        case .comma: 43
        case .slash: 44
        case .n: 45
        case .m: 46
        case .period: 47
        case .tab: 48
        case .space: 49
        case .grave: 50
        case .delete: 51
        case .escape: 53
        case .f5: 96
        case .f6: 97
        case .f7: 98
        case .f3: 99
        case .f8: 100
        case .f9: 101
        case .f11: 103
        case .f10: 109
        case .f12: 111
        case .home: 115
        case .pageUp: 116
        case .forwardDelete: 117
        case .f4: 118
        case .end: 119
        case .f2: 120
        case .pageDown: 121
        case .f1: 122
        case .left: 123
        case .right: 124
        case .down: 125
        case .up: 126
        }
    }

    private static let aliases: [String: Key] = [
        "enter": .return, "backspace": .delete, "dash": .minus, "esc": .escape,
        "0": .zero, "1": .one, "2": .two, "3": .three, "4": .four,
        "5": .five, "6": .six, "7": .seven, "8": .eight, "9": .nine,
    ]

    public static func named(_ spoken: String) -> Key? {
        let s = spoken.lowercased().trimmingCharacters(in: .whitespaces)
        return Key(rawValue: s) ?? aliases[s]
    }
}

public struct KeyChord: Equatable, Codable, Sendable {
    public var key: Key
    public var modifiers: Set<Modifier>
    public init(_ key: Key, _ modifiers: Set<Modifier> = []) {
        self.key = key
        self.modifiers = modifiers
    }
}
