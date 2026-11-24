import Foundation

/// One step of a saved route: what the model intended and what it did, by name. Never text the user typed or searched.
public struct RouteStep: Codable, Equatable, Sendable {
    /// The model's step intent (or, for a question step, the question).
    public var intent: String
    /// One short string per action: its kind, and the name of its target when it has one (`click "Raptors vs Lakers"`).
    public var actions: [String]
    /// A question step (NH-47). The user's answer is not kept.
    public var asked: Bool
    public init(intent: String, actions: [String], asked: Bool = false) {
        self.intent = intent; self.actions = actions; self.asked = asked
    }
}

/// A task that ended `done` (NH-46): its goal and the steps that worked, kept so a similar goal later starts with a hint.
public struct Route: Codable, Equatable, Sendable {
    /// The spoken goal as the task got it, cut to `RouteMemory.goalLimit`.
    public var goal: String
    /// The host of the last page the task saw (`www.` dropped); nil when it did not end in a browser.
    public var host: String?
    public var steps: [RouteStep]
    /// Breaks ties between equally good matches.
    public var savedAt: Date
    public init(goal: String, host: String?, steps: [RouteStep], savedAt: Date) {
        self.goal = goal; self.host = host; self.steps = steps; self.savedAt = savedAt
    }
}

/// Pure rules for route memory: what is saved, how a goal finds a route, and how the file is read and written.
public enum RouteMemory {
    public static let version = 1
    public static let maxRoutes = 50
    public static let maxSteps = 15
    public static let minSteps = 2
    public static let goalLimit = 300
    public static let intentLimit = 80
    static let nameLimit = 60
    static let actionLimit = 120
    static let minScore = 0.6
    static let minShared = 2
    static let filler: Set<String> = ["the", "a", "an", "my", "me", "please", "on", "in", "of", "to", "for", "and"]

    // MARK: Steps

    /// The steps of `history` that ran clean (and question steps), in order; a failed step is dropped. `names[i]` is the
    /// title each label number had on step i's screen, so a click is saved by name, not by a number that means nothing later.
    public static func steps(from history: [StepRecord], names: [[Int: String]]) -> [RouteStep] {
        var kept: [RouteStep] = []
        // The user's answers are words they said, not the route's: they are cut out of every intent, as is any text a step typed.
        let secrets = (history.compactMap(\.userAnswer) + history.flatMap(\.actions).flatMap(typedText)).filter { $0.count >= 3 }
        let typed = history.contains { $0.actions.contains { !typedText($0).isEmpty } }
        for (i, record) in history.enumerated() where record.failure == nil {
            let titles = i < names.count ? names[i] : [:]
            let asked = record.userAnswer != nil
            guard asked || !record.actions.isEmpty else { continue }
            kept.append(RouteStep(intent: intent(record.intent, secrets: secrets, anyTyped: typed),
                                  actions: record.actions.map { describe($0, names: titles) }, asked: asked))
        }
        return Array(kept.prefix(maxSteps))
    }

    /// The intent as saved: the model often quotes what it typed or what the user answered, and the file must hold neither.
    /// Every text any step typed or searched for and every answer is cut out (any case), and when the route typed anything
    /// the quoted spans go too, and a mention of a label number ("element 6") goes, since a number means nothing on a later screen.
    static func intent(_ text: String, secrets: [String], anyTyped: Bool) -> String {
        var s = text
        for secret in secrets.sorted(by: { $0.count > $1.count }) {
            s = s.replacingOccurrences(of: secret, with: "…", options: .caseInsensitive)
        }
        if anyTyped { s = s.replacingOccurrences(of: #"\"[^\"]*\"|“[^”]*”|(?<!\w)'[^']*'|‘[^’]*’"#, with: "…", options: .regularExpression) }
        s = s.replacingOccurrences(of: #"(?i)\b(element|label|number|badge)\s*#?\d+"#, with: "the element", options: .regularExpression)
        return ClaudeRequestBuilder.sanitize(s, limit: intentLimit)
    }

    /// The words an action types, searches for, sets or looks up: the text `describe` leaves out.
    static func typedText(_ action: Action) -> [String] {
        switch action {
        case .typeText(let t), .search(let t), .clipboardSet(let t), .typeInto(_, let t), .setValue(_, let t), .findOnPage(let t, _): [t]
        case .searchSite(let q, _): [q]
        case .editText(let e, let other):
            [other].compactMap { $0 } + ({ switch e {
                case .selectPhrase(let p), .deletePhrase(let p), .caretBefore(let p), .caretAfter(let p): [p]
                case .replace(let a, let b): [a, b]
                default: [] } })()
        case .rewriteText(let how):
            switch how { case .translate(let language): [language]; case .custom(let words): [words]; case .style: [] }
        default: []
        }
    }

    /// The route to save for a task that ended `done`, or nil when fewer than `minSteps` clean steps ran (a one-step
    /// route costs nothing to rediscover). `url` is the last page the task saw.
    public static func route(goal: String, url: String?, history: [StepRecord], names: [[Int: String]], savedAt: Date) -> Route? {
        let kept = steps(from: history, names: names)
        guard kept.filter({ !$0.asked }).count >= minSteps else { return nil }
        return Route(goal: ClaudeRequestBuilder.sanitize(goal, limit: goalLimit), host: host(of: url), steps: kept, savedAt: savedAt)
    }

    /// One action as its kind and, where it has one, a target by name. Typed, searched and set text is never kept (not its
    /// length either); a raw point, grid cell or tab number is not a name, so it is left out.
    static func describe(_ action: Action, names: [Int: String]) -> String {
        func named(_ kind: String, _ name: String?) -> String {
            guard let name = name.map(cleanName), !name.isEmpty else { return kind }
            return "\(kind) \"\(name)\""
        }
        func element(_ t: ElementTarget) -> String? {
            switch t { case .label(let n): names[n]; case .named(let s): s }
        }
        switch action {
        case .typeText: return "type_text"
        case .pressKey: return "press_key"
        case .click(let t, _, _):
            switch t { case .label(let n): return named("click", names[n]); case .element(let s): return named("click", s); default: return "click" }
        case .pressMouse: return "press_mouse"
        case .releaseMouse: return "release_mouse"
        case .moveCursor(let t):
            switch t { case .label(let n): return named("move_cursor", names[n]); case .element(let s): return named("move_cursor", s); default: return "move_cursor" }
        case .scroll: return "scroll"
        case .showGrid: return "show_grid"
        case .zoomGrid: return "zoom_grid"
        case .showLabels: return "show_labels"
        case .hideOverlay: return "hide_overlay"
        case .setMode: return "set_mode"
        case .setSpokenFeedback: return "set_spoken_feedback"
        case .openApp(let app): return named("open_app", app)
        case .openFile(let request):
            // The words the speaker said for a name are dropped, like typed text.
            switch request {
            case .folder(let f): return "open_file folder \(f.rawValue)"
            case .named(_, let kind), .recent(let kind): return "open_file kind \(kind.rawValue)"
            }
        case .openURL(let url, _): return urlText(url).map { "open_url \($0)" } ?? "open_url"
        case .moveWindow: return "move_window"
        case .search: return "search"
        case .searchSite(_, let site): return "search_site \(cleanName(site.split(separator: ".").first.map(String.init) ?? ""))"
        case .findOnPage: return "find_on_page"
        case .wait: return "wait"
        case .checkMedia: return "check_media"
        case .ignore: return "ignore"
        case .setValue: return "set_value"
        case .typeInto: return "type_into"
        case .clearField(let t): return named("clear", element(t))
        case .selectOption(let t, _): return named("select", element(t))
        case .setChecked(let t, let on): return named(on == nil ? "toggle" : on == true ? "check" : "uncheck", element(t))
        case .setExpanded(let t, let open): return named(open ? "expand" : "collapse", element(t))
        case .focusElement(let t): return named("focus", element(t))
        case .scrollTo(let t): return named("scroll_to", element(t))
        case .scrollIn(let t, _, _): return named("scroll_element", element(t))
        case .drag: return "drag"
        case .clickIn(let surface, let name): return named("click_in \(surface.rawValue)", name)
        case .menuItem(let name, _): return named("menu_item", name)
        case .closeApp(let app): return named("close_app", app)
        case .windowAction(let op, let app, _): return named("window \(op.rawValue)", app)
        case .clipboardSet: return "clipboard_set"
        case .readClipboard: return "read_clipboard"
        case .readPage: return "read_page"
        case .readValue(let t): return named("read_value", element(t))
        case .readNotifications: return "read_notifications"
        case .dismissNotifications(let app): return named("dismiss_notifications", app)
        case .waitFor: return "wait_for"
        case .closeTab: return "close_tab"
        case .closeWindow: return "close_window"
        case .selectTab: return "select_tab"
        case .goToTab(let t): if case .named(let title) = t { return named("go_to_tab", title) } else { return "go_to_tab" }
        case .closeOtherTabs: return "close_other_tabs"
        case .listTabs: return "list_tabs"
        case .editText: return "edit_text"
        case .rewriteText: return "rewrite_text"
        case .media: return "media"
        case .volume: return "volume"
        case .system: return "system"
        case .look: return "look"
        }
    }

    /// A name safe to quote in one line: control characters and newlines gone, no double quote, short.
    private static func cleanName(_ s: String) -> String {
        ClaudeRequestBuilder.sanitize(s.replacingOccurrences(of: "\"", with: "'"), limit: nameLimit)
    }

    /// `host/path` of a web address (`www.` dropped, no query, fragment or trailing slash); nil for anything that is not
    /// a web address with a host.
    private static func urlText(_ url: URL) -> String? {
        guard let host = host(of: url.absoluteString) else { return nil }
        let path = url.path.hasSuffix("/") ? String(url.path.dropLast()) : url.path
        return cleanName(host + path)
    }

    /// The lower-cased host of a page address (`www.` dropped), with or without a scheme; nil when it has none.
    public static func host(of address: String?) -> String? {
        guard let address, !address.isEmpty else { return nil }
        let text = address.contains("://") ? address : "https://" + address
        guard var host = URL(string: text)?.host?.lowercased(), host.contains(".") else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }

    // MARK: Saving and matching

    /// `routes` with `route` added as the newest. A route with the same goal and host is replaced; past `maxRoutes` the
    /// oldest go.
    public static func saving(_ route: Route, into routes: [Route]) -> [Route] {
        let key = goalKey(route.goal)
        var kept = routes.filter { !(goalKey($0.goal) == key && $0.host == route.host) }
        kept.append(route)
        return Array(kept.suffix(maxRoutes))
    }

    /// The saved route that best fits `goal`, or nil. Words are compared after dropping filler; a route needs at least
    /// `minShared` shared words and `minScore` of the larger word set. A route for another host is dropped when the page
    /// is on a host and the goal does not name the route's site.
    public static func match(goal: String, currentHost: String?, in routes: [Route]) -> Route? {
        let words = significantWords(goal)
        let spoken = Set(goalKey(goal).split(separator: " ").map(String.init))
        let current = currentHost.flatMap { host(of: $0) }
        var best: (route: Route, score: Double)?
        for route in routes {
            let theirs = significantWords(route.goal)
            let shared = words.intersection(theirs).count
            let score = Double(shared) / Double(max(words.count, theirs.count, 1))
            guard shared >= minShared, score >= minScore else { continue }
            if let current, let host = route.host, host != current, spoken.isDisjoint(with: siteWords(host)) { continue }
            if let top = best, (score, route.savedAt) < (top.score, top.route.savedAt) { continue }
            best = (route, score)   // a later route wins a full tie: the list is newest last
        }
        return best?.route
    }

    private static func goalKey(_ goal: String) -> String {
        CommandGrammar.normalize(goal.filter { !$0.isPunctuation }).joined(separator: " ")
    }

    private static func significantWords(_ goal: String) -> Set<String> {
        Set(goalKey(goal).split(separator: " ").map(String.init)).subtracting(filler)
    }

    /// The words that name a site in a goal: the labels of its host before the top-level one ("espn" for espn.com).
    private static func siteWords(_ host: String) -> Set<String> {
        Set(host.split(separator: ".").dropLast().map(String.init).filter { $0.count >= 3 })
    }

    // MARK: The file

    /// The routes in `data` (`{"version": 1, "routes": [...]}`). Never throws: missing data, invalid JSON or another
    /// version give an empty list, and an entry that does not decode is dropped. The file is untrusted, so every string and
    /// list is cut to its limit on the way in.
    public static func decode(_ data: Data?) -> [Route] {
        guard let data else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let file = try? decoder.decode(File.self, from: data), file.version == version else { return [] }
        return file.routes.compactMap(\.value).suffix(maxRoutes).map(clamped)
    }

    public static func encoded(_ routes: [Route]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(File(version: version, routes: routes.map { Lossy(value: $0) }))
    }

    private struct File: Codable {
        var version: Int
        var routes: [Lossy]
    }

    private struct Lossy: Codable {
        var value: Route?
        init(value: Route) { self.value = value }
        init(from decoder: Decoder) throws { value = try? Route(from: decoder) }
        func encode(to encoder: Encoder) throws { try value?.encode(to: encoder) }
    }

    private static func clamped(_ route: Route) -> Route {
        Route(goal: ClaudeRequestBuilder.sanitize(route.goal, limit: goalLimit), host: route.host.flatMap { host(of: $0) },
              steps: route.steps.prefix(maxSteps).map {
                  RouteStep(intent: ClaudeRequestBuilder.sanitize($0.intent, limit: intentLimit),
                            actions: $0.actions.prefix(maxSteps).map { ClaudeRequestBuilder.sanitize($0, limit: actionLimit) },
                            asked: $0.asked)
              }, savedAt: route.savedAt)
    }
}
