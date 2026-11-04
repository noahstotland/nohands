import Testing
import Foundation
@testable import NoHandsCore

@Test func stopWordsMatchExactPhrases() {
    for p in ["stop", "Stop.", "stop it", "Stop that!", "cancel", "Cancel that.", "never mind", "Nevermind", "abort", "halt", "stop the task"] {
        #expect(StopWords.isStop(p), "\(p)")
    }
    for p in ["stop dictating", "", "stop the music", "click stop"] {
        #expect(!StopWords.isStop(p), "\(p)")
    }
}

@Test func stopWordsAcceptRepeatsAndFillers() {
    for p in ["stop stop", "Stop, stop!", "no stop", "stop stop it", "um stop", "uh, cancel that", "stop, never mind"] {
        #expect(StopWords.isStop(p), "\(p)")
    }
    for p in ["um", "no", "the task", "stop the music", "stop dictating", "stop it now and click save", "please"] {
        #expect(!StopWords.isStop(p), "\(p)")
    }
}

@Test func repeatDetectorFiresAfterLimit() {
    var r = RepeatDetector(limit: 3)
    let a: [Action] = [.pressKey(KeyChord(.return))]
    let r1 = r.record(a), r2 = r.record(a), r3 = r.record(a)
    #expect(!r1); #expect(!r2); #expect(r3)
}

@Test func repeatDetectorResetsOnDifferentOrEmpty() {
    var r = RepeatDetector(limit: 3)
    let a: [Action] = [.pressKey(KeyChord(.return))], b: [Action] = [.pressKey(KeyChord(.tab))]
    _ = r.record(a); _ = r.record(a)
    let x1 = r.record(b), x2 = r.record(a), x3 = r.record(a)
    #expect(!x1); #expect(!x2); #expect(!x3)
    let y0 = r.record([]), y1 = r.record(a), y2 = r.record(a), y3 = r.record(a)
    #expect(!y0); #expect(!y1); #expect(!y2); #expect(y3)
}

@Test func settleIgnoresNumberingAndOrder() {
    let a = ScreenObservation(app: "Safari", windowTitle: "W", url: "u", mode: .command, elements: [
        ObservedElement(number: 1, role: "button", title: "Save"), ObservedElement(number: 2, role: "link", title: "Home")])
    let b = ScreenObservation(app: "Safari", windowTitle: "W", url: "u", mode: .dictation, overlay: "labels", elements: [
        ObservedElement(number: 7, role: "link", title: "Home"), ObservedElement(number: 9, role: "button", title: "Save")])
    #expect(Settle.same(a, b))
}

@Test func settleDetectsDifferences() {
    let e = [ObservedElement(number: 1, role: "button", title: "Save")]
    let a = ScreenObservation(app: "Safari", windowTitle: "W", url: "u", mode: .command, elements: e)
    var b = a; b.windowTitle = "X"; #expect(!Settle.same(a, b))
    b = a; b.url = nil; #expect(!Settle.same(a, b))
    b = a; b.app = "Mail"; #expect(!Settle.same(a, b))
    b = a; b.elements = e + e; #expect(!Settle.same(a, b))
    b = a; b.elements = [ObservedElement(number: 1, role: "link", title: "Save")]; #expect(!Settle.same(a, b))
}

@Test func secondInterruptExits() {
    var p = InterruptPolicy()
    #expect(p.interrupt() == .stopTask)
    #expect(p.interrupt() == .exitNow)
    #expect(p.interrupt() == .exitNow)
    #expect(InterruptPolicy.exitStatus == 130)
}
