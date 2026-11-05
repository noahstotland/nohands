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
    public init(id: String, title: String, front: Bool = false, tabs: [BrowserTab] = []) {
        self.id = id; self.title = title; self.front = front; self.tabs = tabs
    }
}

/// Tells the user's tabs and windows from the ones a task opened (pop-unders, pop-ups, new windows), one ledger
/// per task. Each browser app gets a baseline the first time the task sees it in front: everything in it is the
/// user's. A tab or window is `new` when neither its id nor its title was in the baseline; the title check keeps
/// the user's tabs safe if the browser ever rebuilds its accessibility elements and every id changes.
public struct TabLedger: Sendable {
    private struct Baseline: Sendable {
        var windowIDs: Set<String> = [], tabIDs: Set<String> = []
        var titles: Set<String> = []
    }
    private var baselines: [String: Baseline] = [:]
    /// Per app: ids of tabs the task navigated (or of tabless windows).
    private var taskIDs: [String: Set<String>] = [:]

    public init() {}

    /// Records `windows` as the user's the first time `app` is seen; later calls do nothing. True when it recorded.
    @discardableResult
    public mutating func baseline(app: String, windows: [BrowserWindow]) -> Bool {
        guard baselines[app] == nil else { return false }
        var b = Baseline()
        for w in windows {
            b.windowIDs.insert(w.id)
            b.titles.insert(w.title)
            for t in w.tabs { b.tabIDs.insert(t.id); b.titles.insert(t.title) }
        }
        baselines[app] = b
        return true
    }

    /// The active tab of the front window (the window itself when it has no tabs) is the task's: it is never
    /// closable without a close word, even though it is new. Call it at the first settled observation after a
    /// step that navigated.
    public mutating func markTaskTab(app: String, windows: [BrowserWindow]) {
        guard let front = windows.first(where: \.front) ?? windows.first else { return }
        let id = front.tabs.isEmpty ? front.id : (front.tabs.first(where: \.active) ?? front.tabs[0]).id
        taskIDs[app, default: []].insert(id)
    }

    /// Numbers the windows and tabs for one observation, with their `new` and `task` flags.
    public func listing(app: String, windows: [BrowserWindow]) -> TabListing {
        let base = baselines[app]
        let tasks = taskIDs[app] ?? []
        let frontIndex = windows.firstIndex(where: \.front) ?? 0
        func tabNew(_ t: BrowserTab) -> Bool {
            guard let base else { return false }
            return !base.tabIDs.contains(t.id) && !base.titles.contains(t.title)
        }
        func windowNew(_ w: BrowserWindow) -> Bool {
            guard let base else { return false }
            if w.tabs.isEmpty { return !base.windowIDs.contains(w.id) && !base.titles.contains(w.title) }
            return !base.windowIDs.contains(w.id) && !base.titles.contains(w.title) && w.tabs.allSatisfy(tabNew)
        }
        var out: [TabListing.Window] = []
        var hiddenWindows = 0
        var tabNumber = 0
        for (wi, w) in windows.enumerated() {
            let isNew = windowNew(w)
            let isTask = tasks.contains(w.id) || w.tabs.contains { tasks.contains($0.id) }
            var shown: [TabListing.Tab] = []
            for (ti, t) in w.tabs.enumerated() {
                let new = tabNew(t), task = tasks.contains(t.id)
                guard (wi == frontIndex && (ti < TabListing.frontTabCap || t.active)) || new || task else { continue }
                tabNumber += 1
                shown.append(.init(number: tabNumber, id: t.id, title: TabListing.clean(t.title),
                                   active: t.active, new: new, task: task))
            }
            guard wi == frontIndex || isNew || !shown.isEmpty else { hiddenWindows += 1; continue }
            out.append(.init(number: out.count + 1, id: w.id, title: TabListing.clean(w.title), front: wi == frontIndex,
                             new: isNew, task: isTask, tabs: shown, hiddenTabs: w.tabs.count - shown.count))
        }
        return TabListing(app: app, windows: out, hiddenWindows: hiddenWindows)
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
    static let titleLimit = 60

    public var app: String
    public var windows: [Window]
    /// Old windows that are not listed.
    public var hiddenWindows: Int

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
