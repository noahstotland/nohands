import Testing
import Foundation
import CoreGraphics
@testable import NoHandsCore

private func el(_ n: Int, _ role: String, _ title: String) -> ObservedElement { ObservedElement(number: n, role: role, title: title) }
private func screen(title: String = "", url: String? = nil, media: MediaState? = nil, _ elements: [ObservedElement] = []) -> ScreenObservation {
    var o = ScreenObservation(app: "Browser", windowTitle: title, url: url, mode: .command, elements: elements)
    o.media = media
    return o
}
private func frames(_ numbers: Int...) -> [Int: CGRect] {
    Dictionary(uniqueKeysWithValues: numbers.map { ($0, CGRect(x: 300, y: 100 * $0, width: 400, height: 40)) })
}
private func step(_ kind: PlanStepKind, _ check: PlanCheck, url: String? = nil, text: String? = nil, after: String? = nil) -> PlanStep {
    PlanStep(intent: "do \(kind.rawValue)", kind: kind, url: url, text: text, after: after, check: check)
}
private let click1 = Action.click(.label(1), button: .left, count: 1)
private let look = PlanMove.step(IntentStep(intent: "Give the page a moment", status: .continue, actions: [.wait(ms: 1500)]))

private func actions(_ m: PlanMove) -> [Action]? { if case .step(let s) = m { s.actions } else { nil } }

@Test func engineCompilesEachStepTypeAndFinishesAfterTheLastCheck() {
    let site = URL(string: "https://videos.acme.dev/x")!
    var e = PlanEngine(plan: TaskPlan(steps: [
        step(.openURL, PlanCheck(kind: .urlContains, text: "acme"), url: site.absoluteString),
        step(.click, PlanCheck(kind: .elementPresent, text: "Latest"), text: "Videos"),
        step(.clickFirstItem, PlanCheck(kind: .titleContains, text: "workbench"), after: "Latest"),
        step(.waitForMedia, PlanCheck(kind: .mediaPlaying)),
    ]))
    let wide = [el(1, "radiobutton", "Videos"), el(2, "radiobutton", "Latest"), el(3, "link", "Building a Cedar Workbench")]
    #expect(actions(e.next(screen(), frames: [:])) == [.openURL(site, app: nil), .wait(ms: 1500)])
    #expect(actions(e.next(screen(url: "https://videos.acme.dev/x", wide), frames: [:])) == [.click(.label(1), button: .left, count: 1)])
    // The third step's target needs frames: it is a link wide enough to be content.
    var big = frames(1, 2, 3); big[3] = CGRect(x: 300, y: 300, width: 350, height: 44)
    let third = e.next(screen(url: "https://videos.acme.dev/x", wide), frames: big)
    #expect(actions(third) == [.click(.label(3), button: .left, count: 1)])
    let play = wide + [el(9, "button", "Play (k)")]
    #expect(actions(e.next(screen(title: "Cedar Workbench", play), frames: big)) == [click9, .waitFor(.mediaPlaying, timeoutMs: 20_000)])
    #expect(e.next(screen(title: "Cedar Workbench", media: .playing), frames: big) == .finish("do wait_for_media"))
}
private let click9 = Action.click(.label(9), button: .left, count: 1)

@Test func engineLooksOnceThenHandsOverOnAMissedCheckOrTarget() {
    func plan(_ s: PlanStep...) -> TaskPlan { TaskPlan(steps: s) }
    let open = step(.openURL, PlanCheck(kind: .titleContains, text: "outdoor"), url: "https://acme.dev")
    // A missed check: one extra look, then a fixed reason naming the step number and check kind.
    var e = PlanEngine(plan: plan(open, step(.waitForMedia, PlanCheck(kind: .mediaPlaying))))
    _ = e.next(screen())
    #expect(e.next(screen(title: "Loading")) == look)
    #expect(e.next(screen(title: "Loading")) == .handOver("plan step 1 did not reach its title_contains check"))
    // The page loading late is not a miss.
    e = PlanEngine(plan: plan(open, step(.waitForMedia, PlanCheck(kind: .mediaPlaying))))
    _ = e.next(screen())
    #expect(e.next(screen(title: "Loading")) == look)
    #expect(actions(e.next(screen(title: "Outdoor Boys"))) == [.waitFor(.mediaPlaying, timeoutMs: 20_000)])
    // A missing target: the same single look, then a hand-over; no frames hands over at once.
    let click = step(.click, PlanCheck(kind: .elementPresent, text: "x"), text: "Videos")
    e = PlanEngine(plan: plan(click))
    #expect(e.next(screen([el(1, "button", "Home")])) == look)
    #expect(e.next(screen([el(1, "button", "Home")])) == .handOver("plan step 1 found nothing to click"))
    e = PlanEngine(plan: plan(step(.clickFirstItem, PlanCheck(kind: .titleContains, text: "x"))))
    #expect(e.next(screen([el(1, "link", "Three word title")]), frames: [:]) == .handOver("plan step 1 found nothing to click_first_item"))
    // The vision fallback keys on these prefixes; a plan's reasons must not trip it.
    for reason in ["plan step 1 did not reach its element_present check", "plan step 2 found nothing to click"] {
        #expect(!reason.hasPrefix("no element") && !reason.hasPrefix("element changed"))
    }
}

@Test func engineClicksPlayAtMostOnce() {
    let wait = step(.waitForMedia, PlanCheck(kind: .mediaPlaying))
    var e = PlanEngine(plan: TaskPlan(steps: [wait, wait]))
    let paused = screen(media: .paused, [el(1, "button", "Play")])
    #expect(actions(e.next(paused)) == [click1, .waitFor(.mediaPlaying, timeoutMs: 20_000)])
    // Still paused: look, then hand over; the Play control is not clicked again.
    #expect(e.next(paused) == look)
    #expect(e.next(paused) == .handOver("plan step 1 did not reach its media_playing check"))
    // A second wait step finds a Play control again (a new pop-up player): still no second click.
    e = PlanEngine(plan: TaskPlan(steps: [wait, wait]))
    _ = e.next(paused)
    #expect(actions(e.next(screen(media: .playing, [el(1, "button", "Play")]))) == [.waitFor(.mediaPlaying, timeoutMs: 20_000)])
}
