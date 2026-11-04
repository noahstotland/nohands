import Foundation

public struct GrammarConfig: Sendable {
    public var moveStepPx: Int = 50
    public var scrollStepLines: Int = 5
    public var maxScroll: Int = 50
    public init() {}
}

public struct CommandGrammar: Sendable {
    private let config: GrammarConfig

    public init(config: GrammarConfig = GrammarConfig()) {
        self.config = config
    }

    /// Lowercases, strips ASR punctuation (.,!?), collapses whitespace, splits on spaces.
    public static func normalize(_ transcript: String) -> [String] {
        let stripped = transcript.lowercased().filter { !".,!?".contains($0) }
        return stripped.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    private static let exact: [String: [Action]] = {
        func chord(_ k: Key, _ m: Set<Modifier> = []) -> [Action] { [.pressKey(KeyChord(k, m))] }
        return [
            "start dictating": [.setMode(.dictation)],
            "dictation mode": [.setMode(.dictation)],
            "stop dictating": [.setMode(.command)],
            "command mode": [.setMode(.command)],
            "go to sleep": [.setMode(.sleep)],
            "wake up": [.setMode(.command)],

            "enter": chord(.return), "return": chord(.return),
            "backspace": chord(.delete), "escape": chord(.escape),
            "tab": chord(.tab), "space": chord(.space),
            "left": chord(.left), "right": chord(.right), "up": chord(.up), "down": chord(.down),
            "home": chord(.home), "end": chord(.end),
            "page up": chord(.pageUp), "page down": chord(.pageDown),
            "delete": chord(.delete), "forward delete": chord(.forwardDelete),
            "copy": chord(.c, [.command]), "paste": chord(.v, [.command]),
            "cut": chord(.x, [.command]), "save": chord(.s, [.command]),
            "find": chord(.f, [.command]), "new tab": chord(.t, [.command]),
            "close tab": chord(.w, [.command]),
            "close window": chord(.w, [.command, .shift]),
            "quit app": chord(.q, [.command]),
            "undo": chord(.z, [.command]),
            "redo": chord(.z, [.command, .shift]),
            "select all": chord(.a, [.command]),
            "switch app": chord(.tab, [.command]),
            "spotlight": chord(.space, [.command]),
            "delete word": chord(.delete, [.option]),
            "delete line": chord(.delete, [.command]),

            "grid": [.showGrid], "show grid": [.showGrid],
            "show numbers": [.showLabels], "show labels": [.showLabels],
            "hide grid": [.hideOverlay], "hide numbers": [.hideOverlay], "numbers": [.showLabels],
            "hide": [.hideOverlay], "cancel": [.hideOverlay],

            "click": [.click(.cursor, button: .left, count: 1)],
            "double click": [.click(.cursor, button: .left, count: 2)],
            "triple click": [.click(.cursor, button: .left, count: 3)],
            "right click": [.click(.cursor, button: .right, count: 1)],
            "middle click": [.click(.cursor, button: .middle, count: 1)],
            "hold click": [.pressMouse(.left)],
            "release click": [.releaseMouse(.left)],
        ]
    }()

    private static let modifierAliases: [String: Modifier] = [
        "cmd": .command, "alt": .option, "ctrl": .control,
    ]

    private static let clickPrefixes: [String: (MouseButton, Int)] = [
        "click": (.left, 1),
        "double click": (.left, 2),
        "triple click": (.left, 3),
        "right click": (.right, 1),
        "middle click": (.middle, 1),
    ]

    /// nil when no rule matches (caller falls back to the LLM).
    public func parse(_ transcript: String) -> [Action]? {
        let tokens = Self.normalize(transcript)
        guard let first = tokens.first else { return nil }
        if let hit = Self.exact[tokens.joined(separator: " ")] { return hit }

        switch first {
        case "press": return parsePress(Array(tokens.dropFirst()))
        case "move": return parseMove(Array(tokens.dropFirst()))
        case "scroll": return parseScroll(Array(tokens.dropFirst()))
        case "zoom":
            let rest = Array(tokens.dropFirst())
            guard let n = NumberWords.parse(rest) else { return nil }
            return [.zoomGrid(n)]
        case "open":
            let rest = tokens.dropFirst()
            return rest.isEmpty ? nil : [.openApp(rest.joined(separator: " "))]
        case "type":
            let rest = tokens.dropFirst()
            return rest.isEmpty ? nil : [.typeText(rest.joined(separator: " "))]
        default: break
        }

        for n in [2, 1] where tokens.count > n {
            if let (button, count) = Self.clickPrefixes[tokens[0..<n].joined(separator: " ")] {
                return parseClick(Array(tokens[n...]), button: button, count: count)
            }
        }
        return nil
    }

    private func parsePress(_ tokens: [String]) -> [Action]? {
        guard let last = tokens.last, let key = Key.named(last) else { return nil }
        var mods = Set<Modifier>()
        for t in tokens.dropLast() {
            guard let m = Modifier(rawValue: t) ?? Self.modifierAliases[t] else { return nil }
            mods.insert(m)
        }
        return [.pressKey(KeyChord(key, mods))]
    }

    private func parseClick(_ rest: [String], button: MouseButton, count: Int) -> [Action]? {
        if let n = NumberWords.parse(rest) {
            return [.click(.numbered(n), button: button, count: count)]
        }
        var name = rest
        if name.first == "the" { name.removeFirst() }
        guard !name.isEmpty else { return nil }
        return [.click(.element(named: name.joined(separator: " ")), button: button, count: count)]
    }

    private func direction(_ s: String) -> Direction? { Direction(rawValue: s) }

    /// Optional trailing amount: nil result = malformed; `.some(nil)` = absent.
    private func trailingAmount(_ tokens: ArraySlice<String>) -> Int?? {
        if tokens.isEmpty { return .some(nil) }
        guard let (value, rest) = NumberWords.leadingNumber(in: Array(tokens)), rest.isEmpty else { return nil }
        return .some(value)
    }

    private func parseMove(_ tokens: [String]) -> [Action]? {
        if tokens.first == "to" {
            guard let n = NumberWords.parse(Array(tokens.dropFirst())) else { return nil }
            return [.moveCursor(.numbered(n))]
        }
        guard let d = tokens.first.flatMap(direction), let amt = trailingAmount(tokens.dropFirst()) else { return nil }
        let px = amt ?? config.moveStepPx
        switch d {
        case .up: return [.moveCursor(.relative(dx: 0, dy: -px))]
        case .down: return [.moveCursor(.relative(dx: 0, dy: px))]
        case .left: return [.moveCursor(.relative(dx: -px, dy: 0))]
        case .right: return [.moveCursor(.relative(dx: px, dy: 0))]
        }
    }

    private func parseScroll(_ tokens: [String]) -> [Action]? {
        guard let d = tokens.first.flatMap(direction), let amt = trailingAmount(tokens.dropFirst()) else { return nil }
        let n = min(amt ?? config.scrollStepLines, config.maxScroll)
        return [.scroll(d, amount: n)]
    }
}
