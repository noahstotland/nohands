import Foundation
import CoreGraphics

public enum PlanMove: Equatable, Sendable {
    /// Run this step through the loop's usual path.
    case step(IntentStep)
    /// Every step ran and its check passed; the string is the finish line.
    case finish(String)
    /// The plan ends here and the model's loop takes over; the string says why, in fixed words.
    case handOver(String)
}

/// Runs a validated `TaskPlan` as a pure state machine over observations. Each call reads the previous step's check
/// against the new observation, then emits the next step. It compiles steps to ordinary `Action`s only; the runner
/// sends them through the same guards, trail and step cap as a model step.
public struct PlanEngine: Sendable {
    static let settleMs = 1500
    static let playTimeoutMs = 20_000

    private let plan: TaskPlan
    /// The index of the next step to emit.
    private var next = 0
    /// Whether the last emitted step still has its check to read.
    private var checking = false
    /// Whether the extra look (one `wait`) for the current check or target has been used.
    private var looked = false
    private var clickedPlay = false

    public init(plan: TaskPlan) { self.plan = plan }

    public mutating func next(_ observation: ScreenObservation, frames: [Int: CGRect] = [:]) -> PlanMove {
        if checking {
            let done = plan.steps[next - 1]
            if Self.passes(done.check, observation) {
                checking = false
                looked = false
            } else if !looked {
                looked = true
                return .step(Self.look)
            } else {
                return .handOver("plan step \(next) did not reach its \(done.check.kind.rawValue) check")
            }
        }
        guard next < plan.steps.count else { return .finish(plan.steps.last?.intent ?? "") }
        let step = plan.steps[next]
        let n = next + 1
        switch Self.compile(step, observation, frames: frames, clickedPlay: &clickedPlay) {
        case .actions(let actions):
            self.next += 1
            checking = true
            looked = false
            return .step(IntentStep(intent: step.intent, status: .continue, actions: actions))
        case .missing(retry: let retry):
            if retry, !looked {
                looked = true
                return .step(Self.look)
            }
            return .handOver("plan step \(n) found nothing to \(step.kind.rawValue)")
        }
    }

    private static let look = IntentStep(intent: "Give the page a moment", status: .continue, actions: [.wait(ms: settleMs)])

    private enum Compiled { case actions([Action]), missing(retry: Bool) }

    private static func compile(_ step: PlanStep, _ o: ScreenObservation, frames: [Int: CGRect], clickedPlay: inout Bool) -> Compiled {
        switch step.kind {
        case .openSite:
            // The address comes from the site table, never from the plan.
            guard let site = step.site, SiteSearch.siteNames.contains(site), let url = WebAddress.url(for: site) else {
                return .missing(retry: false)
            }
            return .actions([.openURL(url, app: nil), .wait(ms: settleMs)])
        case .search:
            guard let site = step.site, SiteSearch.siteNames.contains(site), let text = step.text else { return .missing(retry: false) }
            return .actions([.searchSite(text, site: site), .wait(ms: settleMs)])
        case .click:
            guard let n = PlanTargets.click(text: step.text ?? "", in: o.elements) else { return .missing(retry: true) }
            return .actions([.click(.label(n), button: .left, count: 1)])
        case .clickFirstItem:
            // Without frames the navigation-stack test cannot run, so waiting would not help.
            guard frames.values.contains(where: { $0.width > 0 }) else { return .missing(retry: false) }
            guard let n = PlanTargets.firstItem(after: step.after, in: o.elements, frames: frames) else { return .missing(retry: true) }
            return .actions([.click(.label(n), button: .left, count: 1)])
        case .waitForMedia:
            var actions: [Action] = []
            if !clickedPlay, let play = o.elements.first(where: { MediaSignal.control(role: $0.role, name: $0.title, value: $0.value) == .play }) {
                clickedPlay = true
                actions.append(.click(.label(play.number), button: .left, count: 1))
            }
            return .actions(actions + [.waitFor(.mediaPlaying, timeoutMs: playTimeoutMs)])
        }
    }

    private static func passes(_ check: PlanCheck, _ o: ScreenObservation) -> Bool {
        switch check.kind {
        case .titleContains: PlanText.matches(check.text, in: o.windowTitle)
        case .urlContains: o.url.map { PlanText.matches(check.text, in: $0) } ?? false
        case .elementPresent: PlanTargets.click(text: check.text, in: o.elements) != nil
        case .mediaPlaying: o.media == .playing
        }
    }
}
