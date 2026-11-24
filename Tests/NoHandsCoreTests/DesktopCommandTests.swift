import Testing
import CoreGraphics
@testable import NoHandsCore

@Test func snapshotArgv() {
    let c = DesktopCommand.snapshot(app: "Finder", windowID: nil, surface: nil, timeoutMs: 2500)
    #expect(c.argv(headed: false, session: nil) == ["snapshot", "--app", "Finder", "-i", "--compact", "--include-bounds", "--max-depth", "25", "--timeout-ms", "2500"])
    let scoped = DesktopCommand.snapshot(app: "Finder", windowID: "w-1", surface: .sheet, timeoutMs: 2500).argv(headed: false, session: nil)
    #expect(scoped.contains(["--window-id", "w-1"]) && scoped.contains(["--surface", "sheet"]))
    #expect(DesktopCommand.snapshot(app: nil, windowID: nil, surface: .menuBarExtras, timeoutMs: 1).argv(headed: false, session: nil).contains(["--surface", "menu-bar-extras"]))
}

@Test func headedSessionAndTextArgs() {
    #expect(DesktopCommand.setValue(ref: "@s1:e2", text: "cats").argv(headed: true, session: "abc") == ["--headed", "--session", "abc", "set-value", "@s1:e2", "cats"])
    #expect(DesktopCommand.type(ref: "@s1:e2", text: "hi").argv(headed: false, session: nil) == ["type", "@s1:e2", "hi"])
    #expect(DesktopCommand.clipboardSet(text: "x").argv(headed: false, session: nil) == ["clipboard-set", "x"])
    #expect(DesktopCommand.click(ref: "@s1:e2", button: .right, count: 1).argv(headed: false, session: nil) == ["right-click", "@s1:e2"])
    #expect(DesktopCommand.click(ref: "@s1:e2", button: .left, count: 2).commandName == "double-click")
    #expect(DesktopCommand.click(ref: "@s1:e2", button: .left, count: 3).commandName == "triple-click")
    #expect(DesktopCommand.click(ref: "@s1:e2", button: .left, count: 2).needsHeaded)
    #expect(!DesktopCommand.click(ref: "@s1:e2", button: .left, count: 1).needsHeaded)
}

@Test func elementCommandsArgv() {
    func a(_ c: DesktopCommand) -> [String] { c.argv(headed: false, session: nil) }
    #expect(a(.clear(ref: "@s:e1")) == ["clear", "@s:e1"])
    #expect(a(.select(ref: "@s:e1", option: "Blue")) == ["select", "@s:e1", "Blue"])
    #expect(a(.check(ref: "@s:e1", true)) == ["check", "@s:e1"] && a(.check(ref: "@s:e1", false)) == ["uncheck", "@s:e1"])
    #expect(a(.toggle(ref: "@s:e1")) == ["toggle", "@s:e1"])
    #expect(a(.expand(ref: "@s:e1", true)) == ["expand", "@s:e1"] && a(.expand(ref: "@s:e1", false)) == ["collapse", "@s:e1"])
    #expect(a(.focus(ref: "@s:e1")) == ["focus", "@s:e1"] && a(.scrollTo(ref: "@s:e1")) == ["scroll-to", "@s:e1"])
    #expect(a(.scroll(ref: "@s:e1", .down, amount: 3)) == ["scroll", "@s:e1", "--direction", "down", "--amount", "3"])
    #expect(a(.get(ref: "@s:e1", property: "value")) == ["get", "@s:e1", "--property", "value"])
}

@Test func findWaitWindowAndDragArgv() {
    func a(_ c: DesktopCommand) -> [String] { c.argv(headed: false, session: nil) }
    #expect(a(.find(app: "Finder", surface: .menubar, name: "New Folder", exact: true)) == ["find", "--app", "Finder", "--surface", "menubar", "--name", "New Folder", "--exact", "--first"])
    #expect(a(.find(app: nil, surface: .dock, name: "Safari", exact: false)) == ["find", "--surface", "dock", "--name", "Safari", "--first"])
    #expect(a(.wait(.event, value: "window_opened", app: "Finder", ref: nil, timeoutMs: 4000)) == ["wait", "--event", "window-opened", "--app", "Finder", "--timeout", "4000"])
    #expect(a(.wait(.element, value: "actionable", app: nil, ref: "@s1:e3", timeoutMs: 4000)) == ["wait", "--element", "@s1:e3", "--predicate", "actionable", "--timeout", "4000"])
    #expect(a(.wait(.text, value: "Done", app: "App", ref: nil, timeoutMs: 100)) == ["wait", "--text", "Done", "--app", "App", "--timeout", "100"])
    #expect(a(.wait(.window, value: "Save", app: nil, ref: nil, timeoutMs: 100)) == ["wait", "--window", "Save", "--timeout", "100"])
    #expect(a(.wait(.menu, value: nil, app: "Finder", ref: nil, timeoutMs: 100)) == ["wait", "--menu", "--app", "Finder", "--timeout", "100"])
    #expect(a(.wait(.menuClosed, value: nil, app: nil, ref: nil, timeoutMs: 100)) == ["wait", "--menu-closed", "--timeout", "100"])
    #expect(a(.window(.focus, app: "Safari", title: "GitHub")) == ["focus-window", "--app", "Safari", "--title", "GitHub"])
    #expect(a(.window(.minimize, app: "Safari", title: nil)) == ["minimize", "--app", "Safari"])
    #expect(a(.window(.maximize, app: nil, title: nil)) == ["maximize"])
    #expect(a(.drag(fromRef: nil, fromXY: CGPoint(x: 1, y: 2), toRef: "@s1:e9", toXY: nil)) == ["--headed", "drag", "--from-xy=1,2", "--to", "@s1:e9"])
    #expect(a(.drag(fromRef: "@s1:e1", fromXY: nil, toRef: nil, toXY: CGPoint(x: 3.6, y: 4.2))) == ["--headed", "drag", "--from", "@s1:e1", "--to-xy=4,4"])
    #expect(a(.drag(fromRef: nil, fromXY: CGPoint(x: -100, y: 50), toRef: nil, toXY: CGPoint(x: -3, y: -4))) == ["--headed", "drag", "--from-xy=-100,50", "--to-xy=-3,-4"])
    #expect(DesktopCommand.drag(fromRef: "@s1:e1", fromXY: nil, toRef: "@s1:e2", toXY: nil).needsHeaded)
    #expect(a(.closeApp("Slack")) == ["close-app", "Slack"])
    #expect(a(.listWindows(app: "Finder")) == ["list-windows", "--app", "Finder"] && a(.listSurfaces(app: "Finder")) == ["list-surfaces", "--app", "Finder"])
    #expect(a(.clipboardGet) == ["clipboard-get"] && a(.listNotifications) == ["--headed", "list-notifications"])
    #expect(a(.dismissAllNotifications(app: "Mail")) == ["--headed", "dismiss-all-notifications", "--app", "Mail"])
    #expect(DesktopCommand.listNotifications.needsHeaded && DesktopCommand.dismissAllNotifications(app: nil).needsHeaded)
}

@Test func observationClassification() {
    #expect(DesktopCommand.snapshot(app: nil, windowID: nil, surface: nil, timeoutMs: 1).isObservation)
    #expect(DesktopCommand.find(app: nil, surface: nil, name: "x", exact: true).isObservation)
    #expect(DesktopCommand.get(ref: "@s:e1", property: "value").isObservation && DesktopCommand.clipboardGet.isObservation)
    #expect(DesktopCommand.version.isObservation && DesktopCommand.status.isObservation && DesktopCommand.listNotifications.isObservation)
    #expect(!DesktopCommand.closeApp("X").isObservation && !DesktopCommand.wait(.menu, value: nil, app: nil, ref: nil, timeoutMs: 1).isObservation)
    #expect(DesktopCommand.sessionStart(name: "n").argv(headed: false, session: nil) == ["session", "start", "--name", "n"])
    #expect(DesktopCommand.sessionEnd(id: "abc").argv(headed: false, session: nil) == ["session", "end", "abc"])
    #expect(DesktopCommand.version.argv(headed: false, session: "s") == ["version"])
    #expect(DesktopCommand.setValue(ref: "@s:e1", text: "t").commandName == "set-value")
}
