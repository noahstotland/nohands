import Foundation

/// Finds a step that is about to press an irreversible button (Send, Delete, Place order, ...) the user's goal did
/// not name. The task runner pauses such a step for a spoken yes (`ConfirmAnswer`) instead of running it on a guess.
/// Words are matched whole ("Sender", "Sent" and "Posts" are not buttons to ask about), and each verb is allowed
/// only by its own forms in the goal: "buy a lamp" allows Buy but not Place order.
public enum IrreversibleGuard {
    private struct Verb {
        /// What the user hears in "say yes to ...", and the imperative words the element's name must contain in a row.
        let name: String
        /// Goal words that allow the verb: every set needs one of its words in the goal.
        let allowedBy: [Set<String>]

        init(_ name: String, allowedBy: [Set<String>]) {
            self.name = name
            self.allowedBy = allowedBy
        }
    }

    private static let verbs: [Verb] = [
        Verb("send", allowedBy: [["send", "sends", "sending", "sent"]]),
        Verb("delete", allowedBy: [["delete", "deletes", "deleting", "deleted"]]),
        Verb("remove", allowedBy: [["remove", "removes", "removing", "removed"]]),
        Verb("discard", allowedBy: [["discard", "discards", "discarding", "discarded"]]),
        Verb("pay", allowedBy: [["pay", "pays", "paying", "paid"]]),
        Verb("buy", allowedBy: [["buy", "buys", "buying", "bought"]]),
        Verb("purchase", allowedBy: [["purchase", "purchases", "purchasing", "purchased"]]),
        Verb("checkout", allowedBy: [["checkout"]]),
        Verb("confirm", allowedBy: [["confirm", "confirms", "confirming", "confirmed"]]),
        Verb("submit", allowedBy: [["submit", "submits", "submitting", "submitted"]]),
        Verb("publish", allowedBy: [["publish", "publishes", "publishing", "published"]]),
        Verb("post", allowedBy: [["post", "posts", "posting", "posted"]]),
        Verb("unsubscribe", allowedBy: [["unsubscribe", "unsubscribes", "unsubscribing", "unsubscribed"]]),
        Verb("transfer", allowedBy: [["transfer", "transfers", "transferring", "transferred"]]),
        Verb("place order", allowedBy: [["order", "orders", "ordering", "ordered"]]),
        Verb("empty trash",
             allowedBy: [["empty", "empties", "emptying", "emptied"], ["trash", "bin"]]),
    ]

    /// Whether the words of a spoken phrase name a guarded verb ("send", "sending", "place order") or the word
    /// "trash", as whole words once punctuation splits them ("send-it" is "send it"). Used to force the spoken yes on
    /// a pack phrase.
    static func namesVerb(_ phraseWords: [String]) -> Bool {
        let tokens = words(phraseWords.joined(separator: " "))
        if tokens.contains("trash") { return true }
        return verbs.contains { verb in
            let name = mergeCheckOut(verb.name.split(separator: " ").map(String.init))
            // Past forms ("sent", "deleted") name something already done, and "posts" is a noun: neither is a command.
            return name.count == 1 ? tokens.contains { verb.allowedBy[0].contains($0) && !isPast($0) } : contains(tokens, name)
        }
    }

    /// Forms that are not a command: past ("sent"), and third person or plural ("posts", "purchases" are nouns too).
    private static func isPast(_ word: String) -> Bool { word.hasSuffix("ed") || word.hasSuffix("s") || ["sent", "paid", "bought"].contains(word) }

    /// Letters and digits only, so "Send…" and "File > Send" split into words; "check out" is one word, "checkout".
    private static func words(_ text: String) -> [String] {
        let cleaned = String(text.map { $0.isLetter || $0.isNumber ? $0 : " " })
        return mergeCheckOut(CommandGrammar.normalize(cleaned))
    }

    private static func contains(_ words: [String], _ phrase: [String]) -> Bool {
        guard !phrase.isEmpty, words.count >= phrase.count else { return false }
        return (0...(words.count - phrase.count)).contains { Array(words[$0..<($0 + phrase.count)]) == phrase }
    }

    /// Words that open a new instruction after a comma ("don't delete it, just send it").
    private static let newInstruction: Set<String> = ["just", "instead", "rather", "now", "please"]

    /// The goal's words, minus any word after a negation ("don't send it", "I don't want to send it" do not allow
    /// Send). A full stop, "but" or "then" ends the negation. A comma ends it only when the negated part named no
    /// guarded verb ("no, send it") or a new instruction follows ("don't delete it, just send it"); otherwise it
    /// runs on ("don't delete, send or archive anything").
    static func goalVerbs(_ goal: String) -> Set<String> {
        let negations: Set<String> = ["not", "never", "dont", "doesnt", "didnt", "wont", "cant", "shouldnt", "wouldnt",
                                      "isnt", "cannot", "no", "nor", "without"]
        let breaks: Set<String> = ["but", "then"]
        let verbForms = Set(verbs.flatMap { $0.allowedBy.flatMap { $0 } })
        let plain = goal.replacingOccurrences(of: "\u{2019}", with: "").replacingOccurrences(of: "'", with: "")
        var out = Set<String>()
        for clause in plain.split(whereSeparator: { ".;!?".contains($0) }) {
            var negated = false
            var namedVerb = false
            for (i, part) in clause.split(separator: ",", omittingEmptySubsequences: false).enumerated() {
                let tokens = words(String(part))
                if i > 0, negated, !namedVerb || tokens.first.map(newInstruction.contains) == true { negated = false }
                for word in tokens {
                    if breaks.contains(word) { negated = false } else if negations.contains(word) { negated = true; namedVerb = false }
                    else if negated { if verbForms.contains(word) { namedVerb = true } }
                    else { out.insert(word) }
                }
            }
        }
        return out
    }

    /// The verbs to confirm before `actions` run ("send", or "send and delete" when one step holds several), or nil
    /// when the step may run. One yes then covers exactly the verbs it was asked about. A press is checked by every
    /// route that reaches a button, in order: its name, its label, a grid cell or label badge, the cursor (where a
    /// move in this step or `cursor`, the real pointer, left it), a point, a drag's end, and Return or Space on the
    /// focused button.
    public static func held(_ actions: [Action], labels: [Int: UIElementInfo], goal: String,
                            overlay: OverlayState = .none, cursor: CGPoint? = nil) -> String? {
        let goalWords = goalVerbs(goal)
        var asked: [String] = []
        var walk = Walk(labels: labels, overlay: overlay, pointer: cursor)
        for action in actions {
            if case .menuItem(let path, _) = action, MenuMatch.leaf(of: path) == nil {
                if !asked.contains(unnamedMenuItem) { asked.append(unnamedMenuItem) }
                continue
            }
            guard let name = walk.step(action) else { continue }
            // The executor finds a named target by exact title, else a partial match ("order" finds "Place order"), in a
            // live walk that may differ from `labels`, so every label it could pick is checked too.
            var candidates = [words(name)]
            if isNamed(action) {
                candidates += tier(of: name, in: Array(labels.values)).map { words($0.title) }
            }
            for nameWords in candidates {
                for verb in verbs where contains(nameWords, words(verb.name)) && !asked.contains(verb.name) {
                    if !allows(verb, goalWords) { asked.append(verb.name) }
                }
            }
        }
        return asked.isEmpty ? nil : asked.joined(separator: " and ")
    }

    /// The smallest observed element whose frame holds `point`; nil when none does.
    public static func elementUnder(_ point: CGPoint, in elements: [UIElementInfo]) -> UIElementInfo? {
        elements.filter { $0.frame.contains(point) }.min { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
    }

    /// What a step has done to the pointer and focus so far, to find the element each press lands on.
    private struct Walk {
        let labels: [Int: UIElementInfo]
        let overlay: OverlayState
        var pointer: CGPoint?
        var focusedByStep = false
        var focus: UIElementInfo?

        func under(_ p: CGPoint?) -> UIElementInfo? { p.flatMap { elementUnder($0, in: Array(labels.values)) } }

        /// The element a grid cell or label badge number points at; the request's own label when nothing is shown.
        func numbered(_ n: Int) -> UIElementInfo? {
            switch overlay {
            case .none: return labels[n]
            case .labels(let shown): return shown[n]
            case .grid(let g): return under(g.center(of: n))
            }
        }

        func element(_ t: MoveTarget) -> UIElementInfo? {
            switch t {
            case .label(let n): return labels[n]
            case .numbered(let n): return numbered(n)
            case .point(let p): return under(p)
            case .relative(let dx, let dy): return under(pointer.map { CGPoint(x: $0.x + CGFloat(dx), y: $0.y + CGFloat(dy)) })
            case .element, .screenCenter: return nil
            }
        }

        func point(_ t: MoveTarget) -> CGPoint? {
            switch t {
            case .point(let p): return p
            case .relative(let dx, let dy): return pointer.map { CGPoint(x: $0.x + CGFloat(dx), y: $0.y + CGFloat(dy)) }
            case .numbered(let n):
                if case .grid(let g) = overlay { return g.center(of: n) }
                return centre(numbered(n))
            case .label(let n): return centre(labels[n])
            case .element(let name): return centre(tier(of: name, in: Array(labels.values)).first)
            case .screenCenter: return nil
            }
        }

        private func centre(_ e: UIElementInfo?) -> CGPoint? {
            guard let f = e?.frame, f != .zero else { return nil }
            return CGPoint(x: f.midX, y: f.midY)
        }

        /// What the user would call the thing the action presses (nil: it presses nothing named); moves the simulated
        /// pointer and focus as the action would.
        mutating func step(_ action: Action) -> String? {
            switch action {
            case .click(.label(let n), _, _): pointer = centre(labels[n]) ?? pointer; return labels[n]?.title
            case .click(.numbered(let n), _, _):
                let e = numbered(n)
                pointer = point(.numbered(n)) ?? pointer
                return e?.title
            case .click(.element(let name), _, _), .clickIn(_, let name): return name
            case .click(.cursor, _, _), .releaseMouse: return under(pointer)?.title
            case .click(.point(let p), _, _): pointer = p; return under(p)?.title
            case .menuItem(let path, _): return MenuMatch.leaf(of: path)
            case .setValue(.label(let n), _): return labels[n]?.title
            case .setValue(.named(let name), _), .selectOption(.named(let name), _), .typeInto(.named(let name), _),
                 .setChecked(.named(let name), _): return name
            // Moving the cursor or focus onto the button is the first half of pressing it (click at the cursor, Return, Space).
            case .moveCursor(let target):
                let name: String?
                switch target {
                case .label(let n): name = labels[n]?.title
                case .element(let name2): name = name2
                default: name = nil
                }
                pointer = point(target)
                return name
            case .focusElement(let target):
                focusedByStep = true
                switch target {
                case .label(let n): focus = labels[n]; return labels[n]?.title
                case .named(let name): focus = tier(of: name, in: Array(labels.values)).first; return name
                }
            // A drag released on a button presses it.
            case .drag(_, let to):
                let name: String?
                if case .element(let named) = to { name = named } else { name = element(to)?.title }
                pointer = point(to)
                return name
            case .pressKey(let chord) where chord.key == .return || (chord.key == .space && chord.modifiers.isEmpty):
                if focusedByStep { return focus?.title }
                return labels.keys.sorted().compactMap { labels[$0] }
                    .first { $0.states.contains("focused") && $0.role.lowercased().contains("button") }?.title
            default: return nil
            }
        }
    }

    private static func allows(_ verb: Verb, _ goalWords: Set<String>) -> Bool {
        verb.allowedBy.allSatisfy { !$0.isDisjoint(with: goalWords) }
    }

    /// What a menu title with no name in it ("", ">", " > ") is called when it is held: the executor has nothing to
    /// match, so a pack or model step may not carry one.
    private static let unnamedMenuItem = "unnamed menu item"

    /// The verb a short menu title could press at run time, nil when none. Only the last non-empty part of the path
    /// counts (`MenuMatch.leaf`), since that is what the executor matches. Menu items are found by words (a prefix of the title's words, then any
    /// title holding every spoken word), so "Empty" can press "Empty Trash…". A title is held when its plain form is
    /// part of a guarded verb's name ("Emp", "rash"), or each of its words, as `MenuMatch.fold` splits them ("check
    /// out" is one word, "checkout"), starts a word of the name ("Empty", "Plac", "Check"), and the goal does not
    /// allow that verb.
    public static func namesLoosely(title: String, goal: String) -> String? {
        guard let leaf = MenuMatch.leaf(of: title) else { return unnamedMenuItem }
        let plain = MenuMatch.plain(leaf)
        let titleWords = mergeCheckOut(MenuMatch.fold(leaf))
        guard !titleWords.isEmpty else { return nil }
        let goalWords = goalVerbs(goal)
        return verbs.first { verb in
            let nameWords = mergeCheckOut(MenuMatch.fold(verb.name))
            let loose = verb.name.contains(plain) || titleWords.allSatisfy { w in nameWords.contains { $0.hasPrefix(w) } }
            return loose && !allows(verb, goalWords)
        }?.name
    }

    private static func mergeCheckOut(_ words: [String]) -> [String] {
        var out: [String] = []
        for word in words {
            if word == "out", out.last == "check" { out[out.count - 1] = "checkout" } else { out.append(word) }
        }
        return out
    }

    /// The elements a name may press: those with exactly that title, else every one whose title contains it. Both
    /// the native lookup (exact, prefix, contains) and agent-desktop's (exact, contains) land inside this set.
    private static func tier(of name: String, in elements: [UIElementInfo]) -> [UIElementInfo] {
        let q = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        let titled = elements.map { ($0, $0.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) }
        let exact = titled.filter { $0.1 == q }
        return (exact.isEmpty ? titled.filter { $0.1.contains(q) } : exact).map(\.0)
    }

    private static func isNamed(_ action: Action) -> Bool {
        switch action {
        case .click(.element, _, _), .clickIn, .moveCursor(.element), .drag(_, .element), .focusElement(.named), .setValue(.named, _), .selectOption(.named, _),
             .typeInto(.named, _), .setChecked(.named, _): return true
        default: return false
        }
    }
}

/// Whether a spoken reply to "say yes to <verb>" is a yes. Only "yes", "confirm" and "do it" count, with "please"
/// before or after; "yeah", "sure" or a yes with more words after it do not, so a stray word cannot confirm a payment.
public enum ConfirmAnswer {
    /// How long a step held for a spoken yes waits for the answer.
    public static let timeout: Duration = .seconds(30)

    /// `attention` is the configured attention word: when one is set, the reply must start with it.
    public static func isYes(_ transcript: String, attention: AttentionGate = .off) -> Bool {
        var text = transcript
        // With an attention word set, a yes needs it: a "yes" from a TV or another room must not press Send.
        switch attention.check(transcript) {
        case .addressed(let rest): text = rest
        case .off: break
        case .wordOnly, .notAddressed: return false
        }
        var words = CommandGrammar.normalize(text)
        if words.first == "please" { words.removeFirst() }
        if words.last == "please" { words.removeLast() }
        return ["yes", "confirm", "do it"].contains(words.joined(separator: " "))
    }
}
