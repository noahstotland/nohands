import Foundation

/// What a plan step does. The whole set: a plan can do nothing else.
public enum PlanStepKind: String, Sendable, CaseIterable {
    case openSite = "open_site", search, click, clickFirstItem = "click_first_item", waitForMedia = "wait_for_media"
}

/// What the screen must show after a step for the plan to go on.
public enum PlanCheckKind: String, Sendable, CaseIterable {
    case titleContains = "title_contains", urlContains = "url_contains", elementPresent = "element_present"
    case mediaPlaying = "media_playing"
}

public struct PlanCheck: Equatable, Sendable {
    public var kind: PlanCheckKind
    /// Empty for `mediaPlaying`.
    public var text: String
    public init(kind: PlanCheckKind, text: String = "") { self.kind = kind; self.text = text }
}

public struct PlanStep: Equatable, Sendable {
    public var intent: String
    public var kind: PlanStepKind
    /// `openSite` and `search`: a `SiteSearch.siteNames` entry. The model never writes an address; code builds it.
    public var site: String?
    /// `click`: the title to click. `search`: the words to search for.
    public var text: String?
    /// `clickFirstItem`: pick the first content link after the element with this title.
    public var after: String?
    public var check: PlanCheck
    public init(intent: String, kind: PlanStepKind, site: String? = nil, text: String? = nil, after: String? = nil,
                check: PlanCheck) {
        self.intent = intent; self.kind = kind; self.site = site; self.text = text; self.after = after; self.check = check
    }
}

/// A short plan the model writes once from the goal alone, then code runs and checks. Model output is untrusted:
/// `decode` rejects anything outside the closed step and check sets, and `validated` applies the content rules.
/// A plan holds no address: a step names a site from `SiteSearch.siteNames` and code builds the page from it.
public struct TaskPlan: Equatable, Sendable {
    public var steps: [PlanStep]
    public init(steps: [PlanStep]) { self.steps = steps }

    /// Elements read per step while a plan runs. The lists are never sent to the model, so the cap that protects
    /// the local model's context does not apply.
    public static let observedElements = 200
    static let stepRange = 2...8
    static let textLimit = 80

    // MARK: Decoding

    /// The plan in a Claude Messages response; nil for no plan, a refusal or anything malformed.
    public static func decode(fromResponse data: Data) -> TaskPlan? {
        guard let root = object(data), root["stop_reason"] as? String != "refusal",
              let blocks = root["content"] as? [[String: Any]],
              let text = blocks.first(where: { $0["type"] as? String == "text" })?["text"] as? String else { return nil }
        return decode(fromPayloadText: text)
    }

    /// The plan in an Ollama chat response.
    public static func decode(fromOllamaResponse data: Data) -> TaskPlan? {
        guard let message = object(data)?["message"] as? [String: Any], let text = message["content"] as? String else { return nil }
        return decode(fromPayloadText: text)
    }

    /// `{"plan":[...]}`. `{"plan":null}`, an empty list, non-JSON, and any unknown step or check kind (or a step
    /// missing what its kind needs) all give nil: a plan never runs with a hole in it. An empty string is an absent
    /// field (the schema makes every field required, so a step writes `""` for one it does not use).
    public static func decode(fromPayloadText text: String) -> TaskPlan? {
        guard let list = object(Data(text.utf8))?["plan"] as? [Any], !list.isEmpty else { return nil }
        var steps: [PlanStep] = []
        for item in list {
            guard let step = (item as? [String: Any]).flatMap(Self.step(from:)) else { return nil }
            steps.append(step)
        }
        return TaskPlan(steps: steps)
    }

    private static func object(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func nonBlank(_ v: Any?) -> String? {
        guard let s = v as? String, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func step(from o: [String: Any]) -> PlanStep? {
        guard let kind = (o["do"] as? String).flatMap(PlanStepKind.init(rawValue:)),
              let expect = o["expect"] as? [String: Any],
              let checkKind = (expect["kind"] as? String).flatMap(PlanCheckKind.init(rawValue:)) else { return nil }
        let checkText = nonBlank(expect["text"])
        if checkKind != .mediaPlaying, checkText == nil { return nil }
        let check = PlanCheck(kind: checkKind, text: checkKind == .mediaPlaying ? "" : checkText ?? "")
        let site = nonBlank(o["site"]), text = nonBlank(o["text"]), after = nonBlank(o["after"])
        switch kind {
        case .openSite: guard site != nil else { return nil }
        case .search: guard site != nil, text != nil else { return nil }
        case .click: guard text != nil else { return nil }
        case .clickFirstItem, .waitForMedia: break
        }
        let usesSite = kind == .openSite || kind == .search, usesText = kind == .search || kind == .click
        return PlanStep(intent: nonBlank(o["intent"]) ?? "", kind: kind, site: usesSite ? site : nil,
                        text: usesText ? text : nil, after: kind == .clickFirstItem ? after : nil, check: check)
    }

    // MARK: Validation

    /// General words that never identify what the goal is about: verbs, articles, and recency words.
    private static let generalWords: Set<String> = [
        "the", "and", "for", "from", "with", "that", "this", "then", "into", "onto", "about", "some", "any",
        "put", "turn", "open", "show", "find", "get", "go", "take", "bring", "pull", "load", "start", "launch",
        "click", "press", "search", "look", "please", "can", "you", "let", "want", "need", "like",
        "latest", "newest", "recent", "new", "last", "top", "first", "best", "most", "popular", "random",
        "one", "page", "site", "website", "link", "result", "results", "right", "now", "again", "just",
    ]

    /// The goal's words of three or more letters that a check may be tied to.
    static func distinctiveWords(of goal: String) -> [String] {
        goal.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
            .filter { $0.count >= 3 && !generalWords.contains($0) && !MediaGoal.matches($0) }
    }

    /// The plan with its intents sanitized, or nil when it breaks a rule: 2 to 8 steps; every `site` is one of
    /// `SiteSearch.siteNames`; a `search` has text a search may type; every text field is short; at least one check
    /// or search text names a distinctive word of the goal; a goal that wants something playing ends with
    /// `wait_for_media`; the first step is `open_site` or `search`.
    public func validated(goal: String) -> TaskPlan? {
        guard Self.stepRange.contains(steps.count) else { return nil }
        // A plan never sees the screen it starts on, so its first step must open a page: a click first would land on
        // whatever app is in front, which the user did not target.
        guard let first = steps.first?.kind, first == .openSite || first == .search else { return nil }
        var out: [PlanStep] = []
        for var step in steps {
            for field in [step.text, step.after, step.check.text] {
                if let field, field.count > Self.textLimit { return nil }
            }
            if step.kind == .openSite || step.kind == .search {
                guard let site = step.site, SiteSearch.siteNames.contains(site) else { return nil }
            }
            if step.kind == .search {
                guard let typed = step.text.flatMap(SiteSearch.typable) else { return nil }
                step.text = typed
            }
            step.intent = ClaudeRequestBuilder.sanitize(step.intent, limit: Self.textLimit)
            out.append(step)
        }
        let words = Self.distinctiveWords(of: goal)
        guard out.contains(where: { s in
            let texts = [s.check.kind != .mediaPlaying ? s.check.text : nil, s.kind == .search ? s.text : nil]
            return texts.contains { t in t.map { text in words.contains { PlanText.matches($0, in: text) } } ?? false }
        }) else { return nil }
        // A goal to play something ends by waiting for playback. A plan that stops short of it gets that step from
        // code, so a model that forgets it still gets its plan checked against the screen; the `done` path verifies.
        if MediaSignal.wantsPlayback(goal: goal), out.last?.kind != .waitForMedia {
            guard Self.stepRange.contains(out.count + 1) else { return nil }
            out.append(PlanStep(intent: "Start it and wait for it to play.", kind: .waitForMedia,
                                check: PlanCheck(kind: .mediaPlaying, text: "")))
        }
        return TaskPlan(steps: out)
    }
}
