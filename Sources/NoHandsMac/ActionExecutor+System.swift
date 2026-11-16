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
                try input.press(KeyChord(kind == .screen ? .three : .four, [.command, .shift]))
                if kind == .window {
                    // The crosshair needs a moment before space turns it into the window camera.
                    try? await Task.sleep(for: .milliseconds(150))
                    if Task.isCancelled { return Self.cancelled }
                    try input.press(KeyChord(.space))
                }
            case .missionControl: system.openMissionControl(showDesktop: false)
            case .showDesktop: system.openMissionControl(showDesktop: true)
            case .space(let direction):
                guard direction == .left || direction == .right else { return "can't switch space that way" }
                try input.pressHardwareArrow(KeyChord(direction == .left ? .left : .right, [.control]))
            case .notificationCenter:
                guard system.pressMenuBarClock() else { return "can't find the menu bar clock: show it in System Settings > Control Center" }
            case .openSettings(let pane):
                guard ax.open(url: pane.url, appNamed: Self.systemSettings) != nil else { return "can't open \(Self.systemSettings)" }
            case .emptyTrash:
                return await emptyTrash()
            }
            return nil
        } catch {
            return "couldn't post input event"
        }
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
