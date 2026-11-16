import Foundation
import NoHandsCore

extension ActionExecutor {
    static let systemSettings = "System Settings"
    private static let emptyTrashTitles: Set<String> = ["Empty Trash…", "Empty Trash..."]

    /// "lock screen", "screenshot", "mission control", "next space", "notification center", "open bluetooth settings",
    /// "empty trash". Chords are the system's own hotkeys (the WindowServer and Dock take them before any app), so a
    /// shortcut the user rebound makes the phrase do nothing. Returns the failure line, nil on success.
    func runSystem(_ command: SystemCommand) async -> String? {
        do {
            switch command {
            case .lockScreen:
                try input.press(KeyChord(.q, [.control, .command]))
            case .screenshot(let kind):
                // A crosshair left over from an earlier screenshot makes the process look started at once.
                let wasRunning = kind == .window && system.isScreenCaptureUIRunning()
                try input.press(KeyChord(kind == .screen ? .three : .four, [.command, .shift]))
                if kind == .window {
                    // Space turns the crosshair into the window camera only once the screenshot tool has put it up.
                    if wasRunning {
                        try? await Task.sleep(for: .milliseconds(300))
                    } else {
                        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
                        while !system.isScreenCaptureUIRunning() {
                            if Task.isCancelled { return Self.cancelled }
                            if ContinuousClock.now >= deadline { return "the screenshot tool did not start" }
                            try? await Task.sleep(for: .milliseconds(25))
                        }
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                    if Task.isCancelled { return Self.cancelled }
                    try input.press(KeyChord(.space))
                }
            case .missionControl:
                guard await system.openMissionControl(showDesktop: false) else { return "couldn't open Mission Control" }
            case .showDesktop:
                guard await system.openMissionControl(showDesktop: true) else { return "couldn't show the desktop" }
            case .space(let direction):
                guard direction == .left || direction == .right else { return "can't switch space that way" }
                try input.pressHardwareArrow(KeyChord(direction == .left ? .left : .right, [.control]))
            case .notificationCenter:
                guard system.pressMenuBarClock() else { return "can't find the menu bar clock: show it in System Settings > Control Center" }
            case .openSettings(let pane):
                guard ax.open(url: pane.url, appNamed: Self.systemSettings) != nil else { return "can't open \(Self.systemSettings)" }
            case .emptyTrash:
                return await emptyTrash()
            case .appearance(let appearance):
                return await setAppearance(appearance)
            case .doNotDisturb(let on):
                return await runDoNotDisturb(on: on)
            }
            return nil
        } catch {
            return "couldn't post input event"
        }
    }

    /// "dark mode", "light mode", "toggle dark mode": the one fixed script, through System Events. The Automation prompt is
    /// only started here, never awaited: this action runs inline, so waiting on the user's answer would hold `stop` and
    /// `press enter` behind it. The speaker says the phrase again after allowing.
    private func setAppearance(_ appearance: Appearance) async -> String? {
        var step = AutomationAccess.step(status: system.automationStatus())
        if step == .startSystemEvents {
            guard await system.startSystemEvents() else { return AutomationAccess.startFailedLine }
            if Task.isCancelled { return Self.cancelled }
            step = AutomationAccess.step(status: system.automationStatus())
        }
        if step == .ask { system.requestAutomation() }
        if let line = AutomationAccess.line(for: step) { return line }
        let result = await system.runAppearance(appearance)
        if Task.isCancelled { return Self.cancelled }
        switch AutomationAccess.outcome(result) {
        case .success(let now):
            addResult(AutomationAccess.doneLine(now))
            return nil
        case .failure(let failure):
            return failure.line
        }
    }

    /// "do not disturb on" and "off": the user's shortcut of that fixed name.
    private func runDoNotDisturb(on: Bool) async -> String? {
        let result = await system.runShortcut(DoNotDisturb.shortcutName(on: on))
        if Task.isCancelled { return Self.cancelled }
        var list: String?
        if case .exited(0, _) = result {} else if result != .timedOut { list = await system.listShortcuts() }
        if let line = DoNotDisturb.failure(result, on: on, list: list) { return line }
        addResult(DoNotDisturb.doneLine(on: on))
        return nil
    }

    /// Finder's own `Empty Trash…` menu item, which asks "Are you sure…?" for the speaker to answer (`enter` or
    /// `escape`). Never the option-held item or the chord, which skip the question, and nothing when Finder's own
    /// warning is off: no spoken confirm covers a fixed phrase yet.
    private func emptyTrash() async -> String? {
        if let refusal = EmptyTrash.refusal(warnOnEmptyTrash: system.finderWarnsOnEmptyTrash()) { return refusal }
        guard ax.activate(appNamed: "Finder") else { return "can't open Finder" }
        guard await waitForFront("Finder") else { return "Finder did not come to front" }
        // A spoken stop while Finder came forward must not press the item.
        if Task.isCancelled { return Self.cancelled }
        let entries = menus.entries()
        guard let i = entries.firstIndex(where: { Self.emptyTrashTitles.contains($0.title) && !$0.hasSubmenu }) else {
            // Plain "Empty Trash" is the item that does not ask.
            return entries.contains { $0.title == "Empty Trash" } ? EmptyTrash.warningOff : "no Empty Trash item in Finder"
        }
        guard entries[i].enabled else { return EmptyTrash.alreadyEmpty }
        return menus.press(i) ? nil : "couldn't press Empty Trash"
    }
}
