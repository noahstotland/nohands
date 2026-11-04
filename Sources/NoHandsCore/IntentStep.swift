import Foundation

public enum StepStatus: String, Codable, Sendable, CaseIterable { case `continue`, done, stuck, ignore }

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
    public init(number: Int, role: String, title: String) { self.number = number; self.role = role; self.title = title }
}

public struct ScreenObservation: Equatable, Sendable {
    public var app: String
    public var windowTitle: String
    public var url: String?
    public var mode: Mode
    /// "none" | "grid" | "labels"
    public var overlay: String
    public var elements: [ObservedElement]
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
    public init(intent: String, actions: [Action], failure: String? = nil) {
        self.intent = intent; self.actions = actions; self.failure = failure
    }
}

public struct StepRequest: Sendable {
    public var goal: String
    public var step: Int
    public var maxSteps: Int
    public var history: [StepRecord]
    public var observation: ScreenObservation
    public init(goal: String, step: Int, maxSteps: Int, history: [StepRecord], observation: ScreenObservation) {
        self.goal = goal; self.step = step; self.maxSteps = maxSteps
        self.history = history; self.observation = observation
    }

    /// Step 1 of a one-shot request (eval, CLI, legacy callers).
    public init(oneShot transcript: String, context: IntentContext, maxSteps: Int = 12) {
        self.init(goal: transcript, step: 1, maxSteps: maxSteps, history: [],
                  observation: ScreenObservation(context: context))
    }
}
