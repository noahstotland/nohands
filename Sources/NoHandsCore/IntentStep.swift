import Foundation

public enum StepStatus: String, Codable, Sendable, CaseIterable { case `continue`, done, stuck, ignore, ask }

public struct IntentStep: Equatable, Sendable {
    public var intent: String
    public var status: StepStatus
    public var actions: [Action]
    public init(intent: String, status: StepStatus, actions: [Action]) {
        self.intent = intent; self.status = status; self.actions = actions
    }
}

public struct ObservedElement: Equatable, Sendable {
    public var number: Int
    public var role: String
    public var title: String
    public var value: String?
    public var states: [String]
    /// The words just before a generic link or button (`PageText.near`); rendered as `near: "…"`.
    public var near: String?
    public init(number: Int, role: String, title: String, value: String? = nil, states: [String] = [], near: String? = nil) {
        self.number = number; self.role = role; self.title = title; self.value = value; self.states = states; self.near = near
    }
}

/// Which backend observed the screen and may act on it; fixed for a whole task.
public enum HarnessKind: String, Codable, Sendable { case native, agentDesktop = "agent-desktop" }

public struct ScreenObservation: Equatable, Sendable {
    public var app: String
    public var windowTitle: String
    public var url: String?
    public var mode: Mode
    /// "none" | "grid" | "labels"
    public var overlay: String
    public var elements: [ObservedElement]
    public var harness: HarnessKind = .native
    /// An open overlay surface (menu, sheet, alert, popover) whose elements are listed instead of the window's.
    public var surface: String? = nil
    /// The frontmost browser's windows and tabs as read; nil when the front app is not a browser. The task loop
    /// turns it into `tabs`.
    public var browserWindows: [BrowserWindow]? = nil
    /// The app `browserWindows` was read from (which can differ from `app` if focus moved during the walk); the
    /// tab ledger is keyed on it.
    public var browserApp: String? = nil
    /// The numbered, capped window and tab list the model sees (the `Tabs:` block); nil for a non-browser.
    public var tabs: TabListing? = nil
    /// Text the model asked to read in the previous step (clipboard, an element value, notifications).
    public var readings: [String] = []
    /// Whether media plays in the front window; nil when not observed (the one-shot path), which prints no line.
    public var media: MediaState? = nil
    /// Every menu-bar title found, before the element list's cap cut any off. Not shown to the model; the menu-bar
    /// guard and name binding read it. Empty under agent-desktop, whose window snapshots hold no menu bar.
    public var menuBarTitles: [String] = []
    public init(app: String, windowTitle: String = "", url: String? = nil, mode: Mode,
                overlay: String = "none", elements: [ObservedElement] = []) {
        self.app = app; self.windowTitle = windowTitle; self.url = url
        self.mode = mode; self.overlay = overlay; self.elements = elements
    }

    /// Adapter for the one-shot `IntentContext`, which carries no window title, URL or roles.
    public init(context: IntentContext) {
        self.init(app: context.frontmostApp, mode: context.mode, overlay: context.overlay,
                  elements: context.labeledElements.map { ObservedElement(number: $0.number, role: "element", title: $0.title) })
    }
}

public struct StepRecord: Equatable, Sendable {
    public var intent: String
    public var actions: [Action]
    public var failure: String?
    /// Set only by the task loop on a step where the model asked a question (`intent` is the question): what the user
    /// said back. The request builder alone writes the `User answered:` marker, so no model text can carry it.
    public var userAnswer: String?
    public init(intent: String, actions: [Action], failure: String? = nil, userAnswer: String? = nil) {
        self.intent = intent; self.actions = actions; self.failure = failure; self.userAnswer = userAnswer
    }
}

/// The last task as a follow-up request sees it (NH-48): its goal, its last steps, how it ended and the screen it ended on.
/// The element list is not kept; the follow-up reads the screen again.
public struct EarlierTask: Equatable, Sendable {
    public static let historyLimit = 8
    public static let resultLimit = 120
    public static let goalLimit = 300
    public var goal: String
    public var history: [StepRecord]
    /// How it ended: `done: <text>`, `stuck: <text>` or `stopped` (the text cut to `resultLimit`).
    public var result: String
    public var endedApp: String
    public var endedWindow: String
    public var endedURL: String?
    public init(goal: String, history: [StepRecord], result: String, endedApp: String = "", endedWindow: String = "", endedURL: String? = nil) {
        self.goal = goal; self.history = Array(history.suffix(Self.historyLimit))
        self.result = result; self.endedApp = endedApp; self.endedWindow = endedWindow; self.endedURL = endedURL
    }
}

/// What the step carries about the screen picture: the picture itself, or why there is none (sent to the model so
/// it stops asking).
public enum VisionInput: Sendable, Equatable {
    case image(StepScreenshot)
    case unavailable(String)
}

public struct StepRequest: Sendable {
    public var goal: String
    public var step: Int
    public var maxSteps: Int
    public var history: [StepRecord]
    public var observation: ScreenObservation
    /// Set by the task loop on a step that gets a picture (or a reason for none); nil everywhere else.
    public var vision: VisionInput? = nil
    /// The task this one follows up on; nil for a normal request. Sent on every step, before the goal.
    public var earlier: EarlierTask? = nil
    public init(goal: String, step: Int, maxSteps: Int, history: [StepRecord], observation: ScreenObservation,
                vision: VisionInput? = nil, earlier: EarlierTask? = nil) {
        self.goal = goal; self.step = step; self.maxSteps = maxSteps
        self.history = history; self.observation = observation; self.vision = vision; self.earlier = earlier
    }

    /// Step 1 of a one-shot request (eval, CLI, legacy callers).
    public init(oneShot transcript: String, context: IntentContext, maxSteps: Int = 12) {
        self.init(goal: transcript, step: 1, maxSteps: maxSteps, history: [],
                  observation: ScreenObservation(context: context))
    }
}
