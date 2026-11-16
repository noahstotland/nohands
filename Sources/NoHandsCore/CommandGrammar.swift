import Foundation

public struct GrammarConfig: Sendable {
    public var moveStepPx: Int = 50
    public var scrollStepLines: Int = 5
    public var maxScroll: Int = 50
    public init() {}
}

public struct CommandGrammar: Sendable {
    private let config: GrammarConfig
    private let packs: PackSet

    public init(config: GrammarConfig = GrammarConfig(), packs: PackSet = .builtIns) {
        self.config = config
        self.packs = packs
    }

    /// The same grammar looking pack phrases up in `packs`.
    public func with(packs: PackSet) -> CommandGrammar { CommandGrammar(config: config, packs: packs) }

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

            "top of page": chord(.up, [.command]), "top of the page": chord(.up, [.command]),
            "bottom of page": chord(.down, [.command]), "bottom of the page": chord(.down, [.command]),
            "zoom in": chord(.equal, [.command]), "zoom out": chord(.minus, [.command]),
            "actual size": chord(.zero, [.command]), "reset zoom": chord(.zero, [.command]),

            "play": [.media(.play)], "resume": [.media(.play)],
            "play the music": [.media(.play)],
            "pause": [.media(.pause)], "pause the video": [.media(.pause)], "pause the music": [.media(.pause)],
            "play pause": [.media(.playPause)], "toggle play": [.media(.playPause)],
            "next track": [.media(.next)], "next song": [.media(.next)], "next video": [.media(.next)],
            "previous track": [.media(.previous)], "previous song": [.media(.previous)],
            "previous video": [.media(.previous)],
            "full screen video": [.media(.fullScreen)], "video full screen": [.media(.fullScreen)],
            "make the video full screen": [.media(.fullScreen)],
            "exit full screen": [.media(.exitFullScreen)], "leave full screen": [.media(.exitFullScreen)],
            "mute": [.volume(.mute(true))], "mute sound": [.volume(.mute(true))],
            "unmute": [.volume(.mute(false))], "unmute sound": [.volume(.mute(false))],

            "lock screen": [.system(.lockScreen)], "lock computer": [.system(.lockScreen)], "lock mac": [.system(.lockScreen)],
            "screenshot": [.system(.screenshot(.screen))], "take screenshot": [.system(.screenshot(.screen))],
            "screenshot screen": [.system(.screenshot(.screen))],
            "screenshot selection": [.system(.screenshot(.selection))], "screenshot area": [.system(.screenshot(.selection))],
            "screenshot window": [.system(.screenshot(.window))],
            "mission control": [.system(.missionControl)], "show desktop": [.system(.showDesktop)],
            "next space": [.system(.space(.right))], "previous space": [.system(.space(.left))],
            "notification center": [.system(.notificationCenter)], "notification centre": [.system(.notificationCenter)],
            "show notifications": [.system(.notificationCenter)],
            "empty trash": [.system(.emptyTrash)],

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
    static let compoundMarkers: Set<String> = [
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

    /// nil when no rule matches (caller falls back to the LLM). `bundleID` is the frontmost app: its pack, if any,
    /// is checked before the global table. In order: a pack phrase that is also a global phrase, the global table on
    /// the whole phrase, the pack on the phrase without its lead ("open", "go to", an article), "menu <words>", the
    /// global table after an "open" lead, the text edits, the patterns, the filler-stripped table. A stop phrase never
    /// reaches a pack. `textFocused` is whether the front app has a text field focused: only then do edits that name
    /// words in the field ("delete the old files") belong to the grammar; without it they go to the model as before.
    public func parse(_ transcript: String, frontmost bundleID: String? = nil, textFocused: Bool = false) -> [Action]? {
        let tokens = Self.normalize(transcript)
        guard !tokens.isEmpty else { return nil }
        let whole = tokens.joined(separator: " ")
        let pack = StopWords.isStop(transcript) ? nil : bundleID.flatMap(packs.phrases(for:))
        if let hit = pack?[whole] ?? Self.exact[whole] { return hit }
        let (stripped, dropped) = PhraseLead.strip(tokens)
        if !stripped.isEmpty {
            let phrase = stripped.joined(separator: " ")
            if let hit = pack?[phrase] { return hit }
            // Multi-word only: "open home" stays the Home app, not the Home key.
            if dropped == .open, stripped.count > 1, let hit = Self.exact[phrase] { return hit }
        }
        if tokens.count > 1, tokens[0] == "menu" {
            let words = Self.rawWords(transcript, matching: tokens) ?? tokens
            return [.menuItem(words.dropFirst().joined(separator: " "))]
        }
        if let hit = Self.parseTab(tokens, transcript: transcript) { return hit }
        if let edit = Self.parseEdit(transcript, textFocused: textFocused) { return [.editText(edit, otherwise: nil)] }
        if let how = Self.parseRewrite(transcript, textFocused: textFocused) { return [.rewriteText(how)] }
        if let hit = Self.parseMedia(tokens) { return hit }
        if let request = Self.parseSettings(tokens) {
            // An unknown pane after "open settings for" is the grammar's own phrase: `rejection` says so; the model never guesses.
            guard case .pane(let pane) = request else { return nil }
            return [.system(.openSettings(pane))]
        }
        if let hit = parsePattern(tokens, transcript: transcript) { return hit }
        return Self.strippedExactMatch(tokens)
    }

    private static let closeOtherTabsPhrases: Set<String> = ["close the other tabs", "close other tabs", "close all other tabs"]
    private static let listTabsPhrases: Set<String> = ["list tabs", "list the tabs", "list my tabs"]
    /// Tab names that are other tab phrases: "go to the next tab" and "open the new tab" are not tabs called that.
    private static let reservedTabWords: Set<String> = ["new", "next", "previous", "first", "last", "other"]
    /// Words that, inside a name, mean the speaker chained another command ("open chrome and go to the youtube tab").
    private static let chainedTabWords: Set<String> = ["then", "open", "go", "switch", "search", "click", "type", "press"]

    /// Tab commands: "tab 3", "last tab", "switch to the youtube tab", "close the other tabs", "list tabs". A lead
    /// ("switch to", "go to", "open") and an article are optional except that a name needs a lead. nil for anything
    /// else, so every other phrase keeps its rule ("open the new tab", "go to the next tab", "tab 0").
    private static func parseTab(_ tokens: [String], transcript: String) -> [Action]? {
        let phrase = tokens.joined(separator: " ")
        if closeOtherTabsPhrases.contains(phrase) { return [.closeOtherTabs] }
        if listTabsPhrases.contains(phrase) { return [.listTabs] }
        var rest = tokens[...]
        let hasLead: Bool
        if rest.starts(with: ["switch", "to"]) || rest.starts(with: ["go", "to"]) { rest = rest.dropFirst(2); hasLead = true }
        else if rest.first == "open" { rest = rest.dropFirst(); hasLead = true }
        else { hasLead = false }
        var article = false
        if let a = rest.first, ["the", "a", "an"].contains(a) { rest = rest.dropFirst(); article = true }
        guard rest.count >= 2 else { return nil }
        if rest.first == "tab", !article {
            var number = Array(rest.dropFirst())
            if number.first == "number" { number.removeFirst() }
            guard let n = NumberWords.parse(number), (1...99).contains(n) else { return nil }
            return [.goToTab(.number(n))]
        }
        guard rest.last == "tab" else { return nil }
        let name = Array(rest.dropLast())
        if name == ["first"] { return [.goToTab(.number(1))] }
        if name == ["last"] { return [.goToTab(.last)] }
        guard hasLead, name.count <= 8, !reservedTabWords.contains(name[0]),
              chainedTabWords.isDisjoint(with: name.dropFirst()),
              let raw = rawWords(transcript, matching: tokens) else { return nil }
        // `rest` is a suffix of `tokens`; the raw words line up with it.
        let words = raw[(tokens.count - rest.count)...].dropLast().joined(separator: " ")
        return [.goToTab(.named(words))]
    }

    private static let editUnits: [String: TextUnit] = ["word": .word, "line": .line, "sentence": .sentence, "paragraph": .paragraph]
    /// Words that alone are not something to look up in the field ("select all", "delete that").
    private static let notAPhrase: Set<String> = ["all", "that", "this", "it"]
    private static let maxPhraseWords = 12
    private static let caseWords: [String: CaseChange] = ["capitalize": .capitalize, "uppercase": .upper, "lowercase": .lower]

    /// Text editing in the focused field: "select the last sentence", "delete line", "replace meeting with call",
    /// "go before the budget", "go to the end of the line", "capitalize that". "the" is optional wherever it can appear.
    /// Phrases (`<phrase>`, `<a>`, `<b>`) keep the speaker's raw words and need `textFocused`; the unit, caret and case
    /// commands parse regardless and fail at run time with "no text field". nil for anything else, so "select all",
    /// "delete that", "go to the end" and "replace x" keep their rules. Public so dictation mode can ask too.
    public static func parseEdit(_ transcript: String, textFocused: Bool) -> TextEdit? {
        let tokens = normalize(transcript)
        guard tokens.count >= 2 else { return nil }
        func the(_ words: ArraySlice<String>) -> ArraySlice<String> { words.first == "the" ? words.dropFirst() : words }
        /// Before a unit word, "this", "that" and "current" stand for "the" ("delete this line", "select the current word").
        func unitBody(_ words: ArraySlice<String>) -> [String] {
            var body = Array(the(words))
            if body.count == 2, ["this", "that", "current"].contains(body[0]), editUnits[body[1]] != nil { body.removeFirst() }
            return body
        }
        /// The speaker's own words from `from` up to `to`, or nil when they are not a phrase to look up.
        func phrase(_ from: Int, _ to: Int) -> String? {
            let spoken = the(tokens[from..<to])
            guard !spoken.isEmpty, spoken.count <= maxPhraseWords, textFocused,
                  spoken.count > 1 || !(notAPhrase.contains(spoken[spoken.startIndex]) || editUnits[spoken[spoken.startIndex]] != nil),
                  let raw = rawWords(transcript, matching: tokens) else { return nil }
            var words = Array(raw[from..<to])
            while let last = words.last?.last, ".,!?".contains(last) { words[words.count - 1].removeLast() }
            return words.joined(separator: " ")
        }
        switch tokens[0] {
        case "select", "delete":
            let remove = tokens[0] == "delete"
            let body = unitBody(tokens.dropFirst())
            if body.count == 1, let unit = editUnits[body[0]] { return remove ? .delete(unit, last: false) : .select(unit, last: false) }
            if body.count == 2, body[0] == "last", let unit = editUnits[body[1]], unit == .word || unit == .sentence {
                return remove ? .delete(unit, last: true) : .select(unit, last: true)
            }
            guard let words = phrase(1, tokens.count) else { return nil }
            return remove ? .deletePhrase(words) : .selectPhrase(words)
        case "replace":
            // The first "with" splits the two: "replace coffee with tea with milk" types "tea with milk".
            guard let at = tokens.firstIndex(of: "with"), at > 1, at < tokens.count - 1,
                  let old = phrase(1, at), let raw = rawWords(transcript, matching: tokens) else { return nil }
            return .replace(old, with: raw[(at + 1)...].joined(separator: " "))
        case "go":
            if tokens[1] == "before" || tokens[1] == "after" {
                guard let words = phrase(2, tokens.count) else { return nil }
                return tokens[1] == "before" ? .caretBefore(words) : .caretAfter(words)
            }
            guard tokens[1] == "to" else { return nil }
            let place = Array(the(tokens.dropFirst(2)))
            guard place.count >= 3, place[1] == "of" else { return nil }
            let target = Array(the(place.dropFirst(2)))
            guard target.count == 1 else { return nil }
            switch (target[0], place[0]) {
            case ("line", "start"), ("line", "beginning"): return .caret(.lineStart)
            case ("line", "end"): return .caret(.lineEnd)
            case ("document", "start"), ("document", "beginning"), ("document", "top"): return .caret(.documentStart)
            case ("document", "end"), ("document", "bottom"): return .caret(.documentEnd)
            default: return nil
            }
        default:
            guard tokens.count == 2, tokens[1] == "that", let change = caseWords[tokens[0]] else { return nil }
            return .changeCase(change)
        }
    }

    private static let rewriteSubjects: Set<String> = ["that", "this", "it"]
    private static let makeStyles: [String: RewriteStyle] = [
        "shorter": .shorter, "longer": .longer, "clearer": .clearer, "simpler": .simpler, "friendlier": .friendly,
        "more concise": .concise, "more formal": .formal, "more casual": .casual, "more polite": .polite,
        "more professional": .professional,
    ]
    private static let sayStyles: [String: RewriteStyle] = [
        "politely": .polite, "formally": .formal, "casually": .casual, "clearly": .clearer, "simply": .simpler,
        "concisely": .concise, "professionally": .professional,
    ]
    private static let maxRewriteWords = 20

    /// Rewrites of the selected text, only when a text field is focused (else nil, so the words go to the model as
    /// before): "make that shorter", "say it more politely", "fix the grammar", "proofread that", "translate that to
    /// French", "rewrite that" and "rewrite that as a list". The subject is always that, this or it. nil for anything
    /// else ("make it bigger", "make the window wider"). Command mode only: dictation types these words.
    public static func parseRewrite(_ transcript: String, textFocused: Bool) -> RewriteInstruction? {
        guard textFocused else { return nil }
        let tokens = normalize(transcript)
        guard tokens.count >= 2 else { return nil }
        let subjectAt = { (i: Int) in i < tokens.count && rewriteSubjects.contains(tokens[i]) }
        let tail = { (from: Int) in tokens.dropFirst(from).joined(separator: " ") }
        switch tokens[0] {
        case "make":
            guard subjectAt(1), let style = makeStyles[tail(2)] else { return nil }
            return .style(style)
        case "say":
            guard subjectAt(1), tokens.count == 4, tokens[2] == "more", let style = sayStyles[tokens[3]] else { return nil }
            return .style(style)
        case "fix":
            guard tokens[1] == "the", tokens.count >= 3, tokens[2] == "grammar" || tokens[2] == "spelling",
                  tokens.count == 3 || (tokens.count == 5 && tokens[3] == "in" && subjectAt(4)) else { return nil }
            return .style(.grammar)
        case "proofread":
            return tokens.count == 2 && subjectAt(1) ? .style(.grammar) : nil
        case "translate":
            guard subjectAt(1), tokens.count >= 4, tokens[2] == "to" || tokens[2] == "into", tokens.count - 3 <= 3,
                  tokens.dropFirst(3).allSatisfy({ $0.allSatisfy(\.isLetter) }) else { return nil }
            let words = rawWords(transcript, matching: tokens) ?? tokens
            return .translate(language: words.dropFirst(3).joined(separator: " "))
        case "rewrite":
            guard subjectAt(1) else { return nil }
            if tokens.count == 2 { return .style(.clearer) }
            guard tokens.count - 2 <= maxRewriteWords, let words = rawWords(transcript, matching: tokens) else { return nil }
            return .custom(words.dropFirst(2).joined(separator: " "))
        default:
            return nil
        }
    }

    /// Numbered media phrases: "volume up [n] [percent]", "volume <n> [percent]", "set (the) volume to <n> [percent]",
    /// "turn it up/down [n]" and "skip ahead/forward/back/backward [n [seconds]]". Out-of-range counts are nil (the
    /// model gets them); a set level clamps. A volume step is 10 points.
    private static func parseMedia(_ tokens: [String]) -> [Action]? {
        var rest = tokens[...]
        switch rest.first {
        case "set":
            rest = rest.dropFirst()
            if rest.first == "the" { rest = rest.dropFirst() }
            guard rest.first == "volume", rest.dropFirst().first == "to" else { return nil }
            return volumeLevel(Array(rest.dropFirst(2)))
        case "volume":
            rest = rest.dropFirst()
            if let sign = rest.first.flatMap({ volumeSigns[$0] }) { return volumeStep(Array(rest.dropFirst()), sign: sign) }
            return volumeLevel(Array(rest))
        case "turn":
            guard rest.dropFirst().first == "it", let sign = rest.dropFirst(2).first.flatMap({ volumeSigns[$0] }) else { return nil }
            return volumeStep(Array(rest.dropFirst(3)), sign: sign)
        case "skip":
            guard let sign = rest.dropFirst().first.flatMap({ skipSigns[$0] }) else { return nil }
            var count = Array(rest.dropFirst(2))
            let hasUnit = count.last == "seconds" || count.last == "second"
            if hasUnit { count.removeLast() }
            if count.isEmpty { return hasUnit ? nil : [.media(.skip(seconds: sign * 10))] }
            guard let n = NumberWords.parse(count), (1...600).contains(n) else { return nil }
            return [.media(.skip(seconds: sign * n))]
        default: return nil
        }
    }

    private static let volumeSigns = ["up": 1, "down": -1]
    private static let skipSigns = ["ahead": 1, "forward": 1, "back": -1, "backward": -1]

    /// "[n] [percent]" after "volume up/down": n steps of 10 points (1 to 10), or n points with "percent" (1 to 100).
    private static func volumeStep(_ words: [String], sign: Int) -> [Action]? {
        let (count, percent) = splitPercent(words)
        if count.isEmpty { return percent ? nil : [.volume(.by(sign * 10))] }
        guard let n = NumberWords.parse(count), (1...(percent ? 100 : 10)).contains(n) else { return nil }
        return [.volume(.by(sign * (percent ? n : n * 10)))]
    }

    private enum SettingsRequest { case pane(SettingsPane), unknown(String) }

    /// "open settings for <pane>", "open <pane> settings", "<pane> settings" (an article after the lead is optional). After
    /// "open settings for", filler words ("the", "please") are dropped and `&` reads as "and"; a name that is no pane is
    /// `.unknown` when it is a short plain name, and nil (the model's) when it holds a compound word ("bluetooth and turn it
    /// off") or runs past four words. "open <x> settings" with an unknown `<x>` is nil, so it stays an app named that
    /// ("open system settings").
    private static func parseSettings(_ tokens: [String]) -> SettingsRequest? {
        var rest = tokens.map { $0 == "&" ? "and" : $0 }[...]
        let opened = rest.first == "open"
        if opened { rest = rest.dropFirst() }
        func the(_ words: ArraySlice<String>) -> [String] { Array(words.first == "the" ? words.dropFirst() : words) }
        if opened, the(rest).starts(with: ["settings", "for"]) {
            let spoken = the(rest).dropFirst(2)
            let name = Array(spoken.filter { !fillers.contains($0) })
            if let pane = SettingsPane.parse(name) { return .pane(pane) }
            // The marker check sees the name before fillers go, or "bluetooth to connect airpods" would lose its "to".
            guard name.count <= 4, spoken.allSatisfy({ !compoundMarkers.contains($0) }) else { return nil }
            return .unknown(name.joined(separator: " "))
        }
        guard rest.count >= 2, rest.last == "settings" else { return nil }
        return SettingsPane.parse(the(rest.dropLast())).map(SettingsRequest.pane)
    }

    /// "<n> [percent]": an absolute level, clamped to 0 to 100.
    private static func volumeLevel(_ words: [String]) -> [Action]? {
        guard let n = NumberWords.parse(splitPercent(words).count) else { return nil }
        return [.volume(.set(min(n, 100)))]
    }

    /// The words without a closing "percent", "%" or "30%" sign, and whether there was one.
    private static func splitPercent(_ words: [String]) -> (count: [String], percent: Bool) {
        var count = words
        guard let last = count.last else { return (count, false) }
        if last == "percent" || last == "%" { count.removeLast(); return (count, true) }
        if last.hasSuffix("%") { count[count.count - 1] = String(last.dropLast()); return (count, true) }
        return (count, false)
    }

    /// What the global table does with a phrase: an exact entry, or the entry left once filler words are dropped
    /// ("release the click", "please dictation mode").
    private static func globalActions(_ phrase: String) -> [Action]? {
        exact[phrase] ?? strippedExactMatch(phrase.split(separator: " ").map(String.init))
    }

    /// Whether the global table binds this phrase to a mode change, a mouse release or hiding the overlay: a pack
    /// may never claim it.
    static func isReservedGlobal(_ phrase: String) -> Bool {
        (globalActions(phrase) ?? []).contains { action in
            switch action {
            case .setMode, .releaseMouse, .hideOverlay: return true
            default: return false
            }
        }
    }

    /// Whether `transcript` is a route-forgetting phrase (NH-46): false for "forget that route", true for "forget all
    /// routes", nil for anything else. The whole phrase only. The pipeline, not the executor, acts on it, so it is not in
    /// `parse`; `ModeMachine` asks first and a macro cannot take either name.
    public static func forgetsRoutes(_ transcript: String) -> Bool? {
        switch normalize(transcript).joined(separator: " ") {
        case "forget that route": false
        case "forget all routes": true
        default: nil
        }
    }

    /// The HUD line for a `spell` phrase that can't be typed or an "open settings for" an unknown pane; nil for anything
    /// else. Such a phrase is the grammar's own, so it must never fall through to the model, which could guess at what
    /// to type or which pane to open.
    public func rejection(_ transcript: String) -> String? {
        let tokens = Self.normalize(transcript)
        if case .unknown(let name)? = Self.parseSettings(tokens) {
            return name.isEmpty ? "say open settings for and a pane, like bluetooth" : "no settings pane called \(name): say open system settings"
        }
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
        case "scroll":
            if tokens.count > 1, tokens[1] == "to" { return parseFind(tokens, transcript: transcript, skipping: 2, edgesAreWords: false) }
            return parseScroll(Array(tokens.dropFirst()))
        case "find": return parseFind(tokens, transcript: transcript, skipping: 1, edgesAreWords: true)
        case "drag": return Self.parseDrag(Array(tokens.dropFirst()))
        case "zoom":
            let rest = Array(tokens.dropFirst())
            guard let n = NumberWords.parse(rest) else { return nil }
            return [.zoomGrid(n)]
        case "open":
            let rest = tokens.dropFirst()
            guard !rest.isEmpty else { return nil }
            if let file = Self.parseOpenFile(Array(rest)) { return file }
            if let site = Self.parseOpenSite(transcript) { return site }
            // "open chrome and go to youtube" is a multi-step request, not an app name: leave it to the LLM.
            guard rest.allSatisfy({ !Self.compoundMarkers.contains($0) }) else { return nil }
            return [.openApp(rest.joined(separator: " "))]
        case "go", "search":
            let prefix = first == "go" ? ["go", "to"] : ["search", "for"]
            guard let rawWords = Self.rawWords(transcript, matching: tokens) else { return nil }
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

    /// The transcript's words with the speaker's casing and no DictationFormatter, trailing ASR punctuation trimmed.
    /// Nil when that leaves a different count from `tokens` (punctuation-only words: leave it to the model).
    private static func rawWords(_ transcript: String, matching tokens: [String]) -> [String]? {
        var words = transcript.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        while let last = words.last?.last, ".,!?".contains(last) {
            words[words.count - 1].removeLast()
            if words[words.count - 1].isEmpty { words.removeLast() }
        }
        return words.count == tokens.count ? words : nil
    }

    private static let topEdges: Set<String> = ["top", "top of page", "top of the page"]
    private static let bottomEdges: Set<String> = ["bottom", "bottom of page", "bottom of the page"]
    /// The directions "scroll to ..." can say that are not words on a page ("scroll to the down"); they go to the model.
    private static let scrollDirections: Set<String> = ["up", "down", "left", "right"]

    /// "drag <n> to <m>" and "drag from <n> to <m>": two numbers, split at the first "to". nil for anything else
    /// ("drag the file to the trash", "drag to 12"), which goes to the model.
    private static func parseDrag(_ words: [String]) -> [Action]? {
        let rest = words.first == "from" ? Array(words.dropFirst()) : words
        guard let at = rest.firstIndex(of: "to"),
              let from = NumberWords.parse(Array(rest[..<at])),
              let to = NumberWords.parse(Array(rest[(at + 1)...])) else { return nil }
        return [.drag(from: .numbered(from), to: .numbered(to))]
    }

    /// "find <words>" and "scroll to <words>" (`skipping` is the words of the command itself): scroll the page to them
    /// and leave the pointer there. Bare "find" and "find the" stay command-F (nil here, then the exact table).
    /// `scroll to` the top or bottom of the page presses command-up or command-down; a direction stays with the model.
    private func parseFind(_ tokens: [String], transcript: String, skipping: Int, edgesAreWords: Bool) -> [Action]? {
        guard let raw = Self.rawWords(transcript, matching: tokens) else { return nil }
        let spoken = raw.dropFirst(skipping).joined(separator: " ")
        let normalized = PageFind.normalize(spoken)
        guard !normalized.isEmpty else { return nil }
        if !edgesAreWords {
            if Self.topEdges.contains(normalized) { return [.pressKey(KeyChord(.up, [.command]))] }
            if Self.bottomEdges.contains(normalized) { return [.pressKey(KeyChord(.down, [.command]))] }
            if Self.scrollDirections.contains(normalized) { return nil }
        }
        return [.findOnPage(spoken, movePointer: true)]
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
        // "click 12 and hold": the pointer to 12, then the left button down. A name keeps its meaning (the element).
        if button == .left, count == 1, rest.count > 2, rest.suffix(2) == ["and", "hold"],
           let n = NumberWords.parse(Array(rest.dropLast(2))) {
            return [.moveCursor(.numbered(n)), .pressMouse(.left)]
        }
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
            var place = tokens.dropFirst()
            if place.first == "the" { place = place.dropFirst() }
            if place.first == "center" || place.first == "centre",
               place.dropFirst().isEmpty || Array(place.dropFirst()) == ["of", "the", "screen"] {
                return [.moveCursor(.screenCenter)]
            }
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
