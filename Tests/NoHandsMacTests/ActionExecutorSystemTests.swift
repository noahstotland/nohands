import Testing
import Foundation
import os
import NoHandsCore
@testable import NoHandsMac

private final class FakeSystem: SystemControlling {
    let warns: Bool?
    let clock: Bool
    let opens: Bool
    let captureUI: Bool
    let calls = OSAllocatedUnfairLock<[String]>(initialState: [])
    init(warns: Bool? = nil, clock: Bool = true, opens: Bool = true, captureUI: Bool = true) {
        self.warns = warns; self.clock = clock; self.opens = opens; self.captureUI = captureUI
    }
    func openMissionControl(showDesktop: Bool) async -> Bool { calls.withLock { $0.append(showDesktop ? "desktop" : "mission") }; return opens }
    func isScreenCaptureUIRunning() -> Bool { captureUI }
    func pressMenuBarClock() -> Bool { calls.withLock { $0.append("clock") }; return clock }
    func finderWarnsOnEmptyTrash() -> Bool? { warns }
}

@MainActor private func system(_ fake: FakeSystem = FakeSystem(), menus: [MenuEntry] = [])
    -> (ActionExecutor, FakeInput, FakeElements, FakeMenus) {
    let i = FakeInput(), e = FakeElements(), m = FakeMenus(menus)
    e.apps = ["Finder", ActionExecutor.systemSettings]
    e.front = "Finder"
    return (ActionExecutor(input: i, ax: e, overlay: FakeOverlay(), config: AppConfig(), menus: m, system: fake), i, e, m)
}

@MainActor @Test func systemCommandsPostTheirChordsAndCalls() async {
    let table: [(SystemCommand, [KeyChord], [KeyChord], [String])] = [
        (.lockScreen, [KeyChord(.q, [.control, .command])], [], []),
        (.screenshot(.screen), [KeyChord(.three, [.command, .shift])], [], []),
        (.screenshot(.selection), [KeyChord(.four, [.command, .shift])], [], []),
        (.screenshot(.window), [KeyChord(.four, [.command, .shift]), KeyChord(.space)], [], []),
        (.space(.right), [], [KeyChord(.right, [.control])], []), (.space(.left), [], [KeyChord(.left, [.control])], []),
        (.missionControl, [], [], ["mission"]), (.showDesktop, [], [], ["desktop"]), (.notificationCenter, [], [], ["clock"]),
    ]
    for (command, chords, arrows, calls) in table {
        let fake = FakeSystem()
        let (x, i, _, _) = system(fake)
        #expect(await x.execute([.system(command)]) == nil, "\(command)")
        #expect(i.chords == chords && i.hardwareArrows == arrows && fake.calls.withLock { $0 } == calls, "\(command)")
    }
    let (x, _, e, _) = system(FakeSystem(clock: false))
    #expect(await x.execute([.system(.notificationCenter)])?.hasPrefix("can't find the menu bar clock") == true)
    // The window camera never came up: the crosshair stays, and space is not pressed.
    let (y, yi, _, _) = system(FakeSystem(captureUI: false))
    #expect(await y.execute([.system(.screenshot(.window))]) == "the screenshot tool did not start")
    #expect(yi.chords == [KeyChord(.four, [.command, .shift])])
    #expect(await system(FakeSystem(opens: false)).0.execute([.system(.missionControl)]) == "couldn't open Mission Control")
    #expect(await x.execute([.system(.openSettings(.bluetooth))]) == nil)
    #expect(e.opened.map(\.url) == [SettingsPane.bluetooth.url] && e.opened.map(\.app) == [ActionExecutor.systemSettings])
}

@MainActor @Test func emptyTrashPressesOnlyTheItemThatAsks() async {
    func item(_ title: String, enabled: Bool = true) -> MenuEntry { MenuEntry(title: title, path: ["Finder"], enabled: enabled) }
    // (Finder's warning setting, Finder's menu, the failure line, the item pressed)
    let table: [(Bool?, [MenuEntry], String?, [Int])] = [
        (nil, [item("About Finder"), item("Empty Trash…")], nil, [1]),
        (true, [item("Empty Trash…")], nil, [0]),
        (false, [item("Empty Trash…")], EmptyTrash.warningOff, []),
        (nil, [item("Empty Trash")], EmptyTrash.warningOff, []),
        (nil, [item("Empty Trash…", enabled: false)], EmptyTrash.alreadyEmpty, []),
        (nil, [item("About Finder")], "no Empty Trash item in Finder", []),
    ]
    for (warns, menus, failure, pressed) in table {
        let (x, i, _, m) = system(FakeSystem(warns: warns), menus: menus)
        #expect(await x.execute([.system(.emptyTrash)]) == failure, "\(String(describing: warns)) \(menus.map(\.title))")
        #expect(m.pressed == pressed && i.chords.isEmpty, "\(String(describing: warns)) \(menus.map(\.title))")
    }
}
