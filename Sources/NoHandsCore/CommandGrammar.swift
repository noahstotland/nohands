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
            "minimize": chord(.m, [.command]), "minimize window": chord(.m, [.command]),
            "full screen": chord(.f, [.command, .control]),
            "hide app": chord(.h, [.command]),
            "reload": chord(.r, [.command]), "refresh": chord(.r, [.command]),
            "go back": chord(.leftBracket, [.command]),
            "go forward": chord(.rightBracket, [.command]),
            "next tab": chord(.tab, [.control]),
            "previous tab": chord(.tab, [.control, .shift]),
            "quit app": chord(.q, [.command]),
            "undo": chord(.z, [.command]),
            "redo": chord(.z, [.command, .shift]),
            "select all": chord(.a, [.command]),
            "switch app": chord(.tab, [.command]),
            "spotlight": chord(.space, [.command]),
            "delete word": chord(.delete, [.option]),
            "delete line": chord(.delete, [.command]),

            "is it playing": [.checkMedia], "is the video playing": [.checkMedia],
            "is anything playing": [.checkMedia],

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

            "left half": [.moveWindow(.leftHalf)], "right half": [.moveWindow(.rightHalf)],
            "top half": [.moveWindow(.topHalf)], "bottom half": [.moveWindow(.bottomHalf)],
            "snap left": [.moveWindow(.leftHalf)], "snap right": [.moveWindow(.rightHalf)],
            "snap up": [.moveWindow(.topHalf)], "snap down": [.moveWindow(.bottomHalf)],
            "window left": [.moveWindow(.leftHalf)], "window right": [.moveWindow(.rightHalf)],
            "top left": [.moveWindow(.topLeft)], "top right": [.moveWindow(.topRight)],
            "bottom left": [.moveWindow(.bottomLeft)], "bottom right": [.moveWindow(.bottomRight)],
            "left third": [.moveWindow(.leftThird)], "middle third": [.moveWindow(.middleThird)],
            "right third": [.moveWindow(.rightThird)],
            "maximize": [.moveWindow(.maximize)], "maximize window": [.moveWindow(.maximize)],
            "fill screen": [.moveWindow(.maximize)], "fill the screen": [.moveWindow(.maximize)],
            "center window": [.moveWindow(.center)], "centre window": [.moveWindow(.center)],
        ]
    }()

    /// Words dropped for a last-resort exact-table lookup, so "close the current tab", "snap to the left side"
    /// and "hide the grid" match their terse entries. Tried only after every pattern rule declined, so
    /// "click the save", "type the word" and "click to" (two) keep their original tokens.
    private static let fillers: Set<String> = [
        "the", "this", "that", "current", "a", "an", "my", "to", "please", "side", "of",
    ]

    static func strippedExactMatch(_ tokens: [String]) -> [Action]? {
        let stripped = tokens.filter { !fillers.contains($0) }
        guard stripped.count < tokens.count, !stripped.isEmpty else { return nil }
        return exact[stripped.joined(separator: " ")]
    }

    /// Words that never appear in a bare "open <app>" request and signal a compound command.
    private static let compoundMarkers: Set<String> = [
        "and", "then", "on", "in", "to", "go", "search", "for", "with", "at", "type", "click", "press",
    ]

    /// "open youtube", "open youtube.com", "open youtube on chrome", "open reddit in safari": a known site or a
    /// domain opens in the default browser (or the named one). Raw words keep dots the normalizer strips.
    private static func parseOpenSite(_ transcript: String) -> [Action]? {
        let words = transcript.split(whereSeparator: { $0.isWhitespace }).dropFirst().map { $0.lowercased() }
        let split = words.firstIndex { $0 == "on" || $0 == "in" }
        let siteWords = split.map { Array(words[..<$0]) } ?? Array(words)
        let appWords = split.map { Array(words[($0 + 1)...]) } ?? []
        guard !siteWords.isEmpty, split == nil || !appWords.isEmpty,
              siteWords.allSatisfy({ !compoundMarkers.contains($0) }),
              let url = WebAddress.url(for: siteWords.joined(separator: " ")) else { return nil }
        return [.openURL(url, app: appWords.isEmpty ? nil : appWords.joined(separator: " "))]
    }

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
        if let hit = parsePattern(tokens, transcript: transcript) { return hit }
        return Self.strippedExactMatch(tokens)
    }

    /// The HUD line for a `spell` phrase that can't be typed; nil for anything else. Such a phrase is
    /// the grammar's own, so it must never fall through to the model, which could guess at what to type.
    public func rejection(_ transcript: String) -> String? {
        let tokens = Self.normalize(transcript)
        guard tokens.first == "spell", case .failure(let error) = Speller.spell(Array(tokens.dropFirst())) else { return nil }
        switch error {
        case .empty: return "say spell and then the letters"
        case .unknown(let t): return "can't spell \"\(t)\": say spell again"
        case .capitalWithoutLetter: return "capital needs a letter: say spell again"
        }
    }

    /// The rules keyed on the first word(s): press, move, scroll, zoom, open, go to, search for, type, click.
    private func parsePattern(_ tokens: [String], transcript: String) -> [Action]? {
        let first = tokens[0]
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
            guard !rest.isEmpty else { return nil }
            if let site = Self.parseOpenSite(transcript) { return site }
            // "open chrome and go to youtube" is a multi-step request, not an app name: leave it to the LLM.
            guard rest.allSatisfy({ !Self.compoundMarkers.contains($0) }) else { return nil }
            return [.openApp(rest.joined(separator: " "))]
        case "go", "search":
            let prefix = first == "go" ? ["go", "to"] : ["search", "for"]
            // Raw words (speaker's casing, no DictationFormatter), trailing ASR punctuation trimmed.
            var rawWords = transcript.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            while let last = rawWords.last?.last, ".,!?".contains(last) {
                rawWords[rawWords.count - 1].removeLast()
                if rawWords[rawWords.count - 1].isEmpty { rawWords.removeLast() }
            }
            guard rawWords.count == tokens.count else { return nil }   // punctuation-only words: leave it to the model
            // "search youtube for cats": that site (the executor searches it in place when it is open).
            if first == "search", tokens.count > 1, tokens[1] != "for" {
                guard let at = tokens.firstIndex(of: "for"), at > 1, at < tokens.count - 1,
                      let site = SiteSearch.site(spoken: tokens[1..<at].joined(separator: " ")) else { return nil }
                return [.searchSite(rawWords[(at + 1)...].joined(separator: " "), site: site)]
            }
            guard Array(tokens.prefix(2)) == prefix, tokens.count > 2 else { return nil }
            let payload = rawWords[2...].joined(separator: " ")
            // "go to youtube" / "go to example.org": open the site in the default browser instead of typing into
            // whatever app is frontmost. Other payloads still go through the address bar.
            if first == "go" {
                if let url = WebAddress.url(for: payload) { return [.openURL(url, app: nil)] }
                return [.pressKey(KeyChord(.l, [.command])), .typeText(payload), .pressKey(KeyChord(.return))]
            }
            // "search for cats on youtube": that site, wherever you are.
            if let on = tokens[2...].lastIndex(where: { $0 == "on" || $0 == "in" }), on > 2, on < tokens.count - 1,
               let site = SiteSearch.site(spoken: tokens[(on + 1)...].joined(separator: " ")) {
                return [.searchSite(rawWords[2..<on].joined(separator: " "), site: site)]
            }
            // "search for cats": the frontmost app's or page's own search box.
            return [.search(payload)]
        case "spell":
            guard case .success(let text) = Speller.spell(Array(tokens.dropFirst())) else { return nil }
            return [.typeText(text)]
        case "type":
            guard tokens.count > 1 else { return nil }
            // Payload comes from the raw transcript so ASR casing/punctuation survives.
            let raw = transcript.split(whereSeparator: { $0.isWhitespace }).dropFirst().joined(separator: " ")
            return [.typeText(DictationFormatter.format(raw))]
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
