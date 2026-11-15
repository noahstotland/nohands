import Foundation

/// How long the task loop waits for the screen after a step, by what the step did.
public enum SettlePolicy: Int, Comparable, Sendable {
    /// One observation, no sleep: the step changed nothing on screen.
    case none
    /// One short sleep, then one observation: a local edit that lands at once.
    case oneLook
    /// Poll until two readings match, up to `settleMs`: the step may load something.
    case full

    public static func < (a: SettlePolicy, b: SettlePolicy) -> Bool { a.rawValue < b.rawValue }

    /// The highest level among the step's actions; an empty step is `none`.
    public static func `for`(_ actions: [Action]) -> SettlePolicy {
        actions.map(level).max() ?? .none
    }

    /// No `default`: a new action kind must choose a level.
    private static func level(_ action: Action) -> SettlePolicy {
        switch action {
        case .wait, .look, .checkMedia, .ignore, .readClipboard, .readValue, .readNotifications, .clipboardSet:
            return .none
        case .typeText, .typeInto, .setValue, .clearField, .scroll, .scrollIn, .scrollTo, .focusElement, .moveCursor,
             .moveWindow, .setChecked, .waitFor:
            return .oneLook
        case .pressKey(let chord):
            // Return submits; Command, Control and Option chords can switch tabs, reload or go back.
            let loads = chord.key == .return || !chord.modifiers.isDisjoint(with: [.command, .control, .option])
            return loads ? .full : .oneLook
        case .openURL, .openApp, .click, .search, .searchSite, .menuItem, .clickIn, .windowAction, .selectOption,
             .setExpanded, .drag, .closeApp, .closeTab, .closeWindow, .selectTab, .pressMouse, .releaseMouse,
             .showGrid, .zoomGrid, .showLabels, .hideOverlay, .setMode, .dismissNotifications:
            return .full
        }
    }
}

/// Decides when a polled screen has settled. Fed one reading at a time. Settled when the last two readings match,
/// or when a value that keeps changing (a clock, a counter) is the only thing that differs, so it cannot hold the
/// loop until `settleMs` runs out.
public struct SettleWatch: Sendable {
    private var readings: [ScreenObservation] = []

    public init() {}

    /// Adds a reading; true when the screen has settled.
    public mutating func feed(_ reading: ScreenObservation) -> Bool {
        readings.append(reading)
        if readings.count > 3 { readings.removeFirst() }
        let n = readings.count
        guard n >= 2 else { return false }
        let (a, b) = (readings[n - 2], readings[n - 1])
        if Settle.same(a, b) { return true }
        // Ticking: the last two differ only in values, and the same elements also changed value just before.
        guard n == 3, Settle.sameExceptValues(a, b), Settle.sameExceptValues(readings[0], a) else { return false }
        return Settle.changedValues(a, b).isSubset(of: Settle.changedValues(readings[0], a))
    }
}
