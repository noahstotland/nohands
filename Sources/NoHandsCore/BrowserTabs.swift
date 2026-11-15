import Foundation

/// One browser tab as the Mac layer read it. `id` is an opaque token: Core never looks inside it.
public struct BrowserTab: Equatable, Sendable {
    public var id: String
    public var title: String
    public var active: Bool
    public init(id: String, title: String, active: Bool = false) { self.id = id; self.title = title; self.active = active }
}

/// One browser window. `tabs` is empty when the browser does not expose its tab strip; the window then stands for itself.
public struct BrowserWindow: Equatable, Sendable {
    public var id: String
    public var title: String
    public var front: Bool
    public var tabs: [BrowserTab]
    /// False when the read stopped before the end of the tab strip (the per-group cap or the read deadline): more
    /// tabs may exist than `tabs` lists.
    public var complete: Bool
    public init(id: String, title: String, front: Bool = false, tabs: [BrowserTab] = [], complete: Bool = true) {
        self.id = id; self.title = title; self.front = front; self.tabs = tabs; self.complete = complete
    }
}

/// Tells the user's tabs and windows from the ones a task opened (pop-unders, pop-ups, new windows), one ledger
/// per task. Each browser app gets a baseline the first time the task sees it in front: everything in it is the
/// user's. A tab or window is `new` when neither its id nor its title was in the baseline; the title check keeps
/// the user's tabs safe if the browser ever rebuilds its accessibility elements and every id changes. A window the
/// baseline saw without a tab list, or with a cut-short one (the read ran out of budget, or the browser hides
/// its strip) cannot tell new tabs from the user's: the tabs it shows later join the baseline as the user's, and a
/// tab is only ever new in a window whose baseline read was complete. A browser that was not in front when the
/// task started (a cold launch or session restore lists its windows and tabs one at a time) is baselined from two
/// reads taken a moment apart, with no step in between (`baseline(alsoSeen:)`).
public struct TabLedger: Sendable {
    private struct Baseline: Sendable {
        var windowIDs: Set<String> = [], tabIDs: Set<String> = []
        var titles: Set<String> = []
        /// Baseline windows that had a complete tab list when they were recorded.
        var populatedWindowIDs: Set<String> = []
        /// Baseline windows any read of which was cut short.
        var partialWindowIDs: Set<String> = []

        mutating func record(_ w: BrowserWindow) {
            windowIDs.insert(w.id)
            titles.insert(w.title)
            for t in w.tabs { tabIDs.insert(t.id); titles.insert(t.title) }
            // A window counts as fully read only if every read of it was complete.
            if !w.complete { partialWindowIDs.insert(w.id); populatedWindowIDs.remove(w.id) }
            else if !w.tabs.isEmpty, !partialWindowIDs.contains(w.id) { populatedWindowIDs.insert(w.id) }
        }

        func isNew(_ t: BrowserTab, in w: BrowserWindow) -> Bool {
            if tabIDs.contains(t.id) || titles.contains(t.title) { return false }
            return !(windowIDs.contains(w.id) && !populatedWindowIDs.contains(w.id))
        }

        func isNew(_ w: BrowserWindow) -> Bool {
            if windowIDs.contains(w.id) || titles.contains(w.title) { return false }
            return w.tabs.isEmpty || w.tabs.allSatisfy { isNew($0, in: w) }
        }
    }
    private var baselines: [String: Baseline] = [:]
    /// Per app: ids of tabs the task navigated (or of tabless windows).
    private var taskIDs: [String: Set<String>] = [:]

    public init() {}

    /// Whether `app` already has a baseline.
    public func hasBaseline(app: String) -> Bool { baselines[app] != nil }

    /// Records `windows` (and `alsoSeen`, the earlier of two reads taken 300 ms apart) as the user's the first time `app` is
    /// seen and returns true. Later calls change nothing (false), except that tabs first shown by a baseline window
    /// that had no complete tab list are taken as the user's too.
    @discardableResult
    public mutating func baseline(app: String, windows: [BrowserWindow], alsoSeen: [BrowserWindow] = []) -> Bool {
        guard var b = baselines[app] else {
            var b = Baseline()
            for w in windows + alsoSeen { b.record(w) }
            baselines[app] = b
            return true
        }
        for w in windows where !w.tabs.isEmpty && b.windowIDs.contains(w.id) && !b.populatedWindowIDs.contains(w.id) {
            b.record(w)
        }
        baselines[app] = b
        return false
    }

    /// The active tab of the front window (the window itself when it has no tabs) is the task's: it is never
    /// closable without a close word, even though it is new. A front window that is itself new (a pop-up that took
    /// focus) is not the task's: the active tab of the first window that is not new stands instead, new or not
    /// (marking a user tab changes nothing, user tabs are never closable). The front window is kept only when every
    /// window is new. Call it at the first settled observation after a step that navigated.
    public mutating func markTaskTab(app: String, windows: [BrowserWindow]) {
        guard let front = windows.first(where: \.front) ?? windows.first else { return }
        var pick = front
        if let base = baselines[app], base.isNew(front), let other = windows.first(where: { !base.isNew($0) }) {
            pick = other
        }
        let id = pick.tabs.isEmpty ? pick.id : (pick.tabs.first(where: \.active) ?? pick.tabs[0]).id
        taskIDs[app, default: []].insert(id)
    }

    /// Numbers the windows and tabs for one observation, with their `new` and `task` flags.
    public func listing(app: String, windows: [BrowserWindow]) -> TabListing {
        let base = baselines[app]
        let tasks = taskIDs[app] ?? []
        let frontIndex = windows.firstIndex(where: \.front) ?? 0
        func tabNew(_ t: BrowserTab, in w: BrowserWindow) -> Bool { base?.isNew(t, in: w) ?? false }
        func windowNew(_ w: BrowserWindow) -> Bool { base?.isNew(w) ?? false }
        var out: [TabListing.Window] = []
        var hiddenWindows = 0
        var newShown = 0, hiddenNew = 0
        var tabNumber = 0
        for (wi, w) in windows.enumerated() {
            let isNew = windowNew(w)
            let isTask = tasks.contains(w.id) || w.tabs.contains { tasks.contains($0.id) }
            var shown: [TabListing.Tab] = []
            var windowHidden = 0
            for (ti, t) in w.tabs.enumerated() {
                let new = tabNew(t, in: w), task = tasks.contains(t.id)
                let always = (wi == frontIndex && (ti < TabListing.frontTabCap || t.active)) || task
                guard always || new else { continue }
                // Past the cap, new tabs outside the front window's own listing are only counted.
                if new, !always {
                    if newShown < TabListing.newCap { newShown += 1 } else { hiddenNew += 1; windowHidden += 1; continue }
                }
                tabNumber += 1
                shown.append(.init(number: tabNumber, id: t.id, title: TabListing.clean(t.title),
                                   active: t.active, new: new, task: task))
            }
            if wi != frontIndex, shown.isEmpty {
                guard isNew else { hiddenWindows += 1; continue }
                if newShown >= TabListing.newCap { if windowHidden == 0 { hiddenNew += 1 }; continue }
                newShown += 1
            }
            out.append(.init(number: out.count + 1, id: w.id, title: TabListing.clean(w.title), front: wi == frontIndex,
                             new: isNew, task: isTask, tabs: shown, hiddenTabs: w.tabs.count - shown.count))
        }
        return TabListing(app: app, windows: out, hiddenWindows: hiddenWindows, hiddenNew: hiddenNew)
    }
}

/// What the model sees of a browser: numbered windows and tabs, capped. Numbers map back to the ids the Mac layer
/// handed out.
public struct TabListing: Equatable, Sendable {
    public struct Tab: Equatable, Sendable {
        public var number: Int
        public var id: String
        public var title: String
        public var active: Bool
        public var new: Bool
        public var task: Bool
    }
    public struct Window: Equatable, Sendable {
        public var number: Int
        public var id: String
        public var title: String
        public var front: Bool
        public var new: Bool
        public var task: Bool
        /// The tabs shown (with numbers); the rest are only counted in `hiddenTabs`.
        public var tabs: [Tab]
        public var hiddenTabs: Int
    }

    /// Every tab of the front window up to this many; every new or task tab anywhere.
    static let frontTabCap = 20
    /// New tabs and windows listed beyond the front window's own; the rest are only counted.
    static let newCap = 10
    static let titleLimit = 60

    public var app: String
    public var windows: [Window]
    /// Old windows that are not listed.
    public var hiddenWindows: Int
    /// New tabs and windows past `newCap`, not listed.
    public var hiddenNew = 0

    public func tab(_ number: Int) -> Tab? { windows.lazy.flatMap(\.tabs).first { $0.number == number } }
    public func window(_ number: Int) -> Window? { windows.first { $0.number == number } }

    /// Titles are untrusted: one line, cut short, and no double quotes to fake the list's own structure.
    static func clean(_ title: String) -> String {
        ClaudeRequestBuilder.sanitize(title, limit: titleLimit).replacingOccurrences(of: "\"", with: "'")
    }

    /// The `Tabs:` block of the request, without a trailing newline.
    var rendered: String {
        func flags(_ f: [(Bool, String)]) -> String {
            let on = f.filter(\.0).map(\.1)
            return on.isEmpty ? "" : " (" + on.joined(separator: ", ") + ")"
        }
        var s = "Tabs (\(ClaudeRequestBuilder.sanitize(app))):"
        for w in windows {
            s += "\n  window \(w.number)" + flags([(w.front, "front"), (w.new, "new"), (w.new && w.task, "task")])
                + " \"\(w.title)\""
            for t in w.tabs {
                s += "\n    tab \(t.number) \"\(t.title)\"" + flags([(t.active, "active"), (t.task, "task"), (t.new, "new")])
            }
            if w.hiddenTabs > 0 { s += "\n    +\(w.hiddenTabs) other tabs" }
        }
        if hiddenWindows > 0 { s += "\n  +\(hiddenWindows) other windows" }
        if hiddenNew > 0 { s += "\n  +\(hiddenNew) more new" }
        return s
    }
}

/// Goals about playing media get a longer step budget: a stream site throws overlays and pop-unders before the play button.
public enum MediaGoal {
    private static let words: Set<String> = [
        "play", "plays", "playing", "watch", "watches", "watching", "stream", "streams", "streaming",
        "video", "videos", "game", "games", "match", "matches", "movie", "movies", "episode", "episodes",
        "livestream", "livestreams", "listen", "listening",
    ]

    public static func matches(_ goal: String) -> Bool {
        !words.isDisjoint(with: CommandGrammar.normalize(goal))
    }
}

/// Code-level safety net for the tab actions: a step may only close a tab or window the task opened (marked
/// `new`), never the task's own tab, unless the goal asks to close something. Numbers must exist in the listing
/// the model was shown. Selecting a tab is never blocked.
public enum TabGuard {
    public static func blocked(_ actions: [Action], listing: TabListing?, goal: String) -> String? {
        let mayClose = ShortcutGuard.allowsClose(goal: goal)
        for action in actions {
            switch action {
            case .closeTab(let n):
                guard let tab = listing?.tab(n) else { return "blocked: no tab \(n)" }
                if !mayClose, !tab.new || tab.task { return "blocked: tab \(n) is not one this task opened" }
            case .closeWindow(let n):
                guard let window = listing?.window(n) else { return "blocked: no window \(n)" }
                if !mayClose, !window.new || window.task { return "blocked: window \(n) is not one this task opened" }
            case .selectTab(let n):
                if listing?.tab(n) == nil { return "blocked: no tab \(n)" }
            default:
                continue
            }
        }
        return nil
    }
}

/// Picks tabs for the spoken tab commands and words the "list tabs" line.
public enum TabMatch {
    /// The index in `tabs` of the tab `words` names, or nil. Titles and words are compared as the grammar normalizes
    /// them, so case and punctuation don't matter. First tier with a hit wins: a title equal to the words, a title
    /// that starts with them, a title holding every word. A word also matches its plural or singular ("doc" finds
    /// "Docs"). Inside the tier, a tab that is not the active one wins (saying "the YouTube tab" from one YouTube tab
    /// goes to the other), then the leftmost. No fuzzy guess.
    public static func best(_ words: String, in tabs: [BrowserTab]) -> Int? {
        let wanted = CommandGrammar.normalize(words)
        guard !wanted.isEmpty else { return nil }
        func same(_ a: String, _ b: String) -> Bool { a == b || a + "s" == b || b + "s" == a }
        let titles = tabs.map { CommandGrammar.normalize($0.title) }
        let tiers: [([String]) -> Bool] = [
            { $0.count == wanted.count && zip($0, wanted).allSatisfy(same) },
            { $0.count >= wanted.count && zip($0, wanted).allSatisfy(same) },
            { title in wanted.allSatisfy { w in title.contains { same($0, w) } } },
        ]
        for tier in tiers {
            let hits = titles.indices.filter { tier(titles[$0]) }
            if let pick = hits.first(where: { !tabs[$0].active }) ?? hits.first { return pick }
        }
        return nil
    }

    /// The keyboard shortcut that selects the target without reading the strip: command-1 to command-8 for a number
    /// from 1 to 8, command-9 (the last tab) for `.last`. Nil when the tab must be found and pressed.
    public static func chord(for target: TabTarget) -> KeyChord? {
        let digits: [Key] = [.one, .two, .three, .four, .five, .six, .seven, .eight]
        switch target {
        case .number(let n): return digits.indices.contains(n - 1) ? KeyChord(digits[n - 1], [.command]) : nil
        case .last: return KeyChord(.nine, [.command])
        case .named: return nil
        }
    }

    /// The board's one notice line, at most 80 characters: `1 YouTube · 2* Inbox · 3 GitHub`, the active tab starred.
    /// Each title is cut to its first 3 words and 16 characters. A strip that does not fit ends `+N more`.
    public static func listLine(_ tabs: [BrowserTab]) -> String {
        let limit = 80, joiner = " \u{00B7} "
        let entries = tabs.enumerated().map { i, tab -> String in
            let words = TabListing.clean(tab.title).split(separator: " ").prefix(3).joined(separator: " ")
            let title = String(words.prefix(16)).trimmingCharacters(in: .whitespaces)
            return "\(i + 1)\(tab.active ? "*" : "") \(title.isEmpty ? "untitled" : title)"
        }
        for shown in stride(from: entries.count, through: 1, by: -1) {
            let line = entries.prefix(shown).joined(separator: joiner)
                + (shown < entries.count ? joiner + "+\(entries.count - shown) more" : "")
            if line.count <= limit { return line }
        }
        return "\(entries.count) tabs"
    }
}
