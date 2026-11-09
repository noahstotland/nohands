import Foundation

extension Action {
    /// True when the action's payload is words the speaker may still be saying (typed text, an app or site, a search,
    /// a spoken element name). Such a command keeps the full silence window, so "type hello … world" is not cut in half.
    /// Exhaustive on purpose: a new action must choose. The harness and tab actions only come from the model; the
    /// ones that carry text or a name answer true.
    public var carriesSpokenText: Bool {
        switch self {
        case .typeText, .openApp, .openURL, .search, .searchSite, .setValue, .typeInto, .selectOption, .clickIn,
             .menuItem, .closeApp, .clipboardSet:
            return true
        case .click(let target, _, _):
            if case .element = target { return true }
            return false
        case .moveCursor(let target):
            if case .element = target { return true }
            return false
        case .windowAction(_, let app, let title): return app != nil || title != nil
        case .pressKey, .pressMouse, .releaseMouse, .scroll, .showGrid, .zoomGrid, .showLabels, .hideOverlay, .setMode,
             .moveWindow, .wait, .checkMedia, .ignore, .clearField, .setChecked, .setExpanded, .focusElement, .scrollTo,
             .scrollIn, .drag, .readClipboard, .readValue, .readNotifications, .dismissNotifications, .waitFor,
             .closeTab, .closeWindow, .selectTab:
            return false
        }
    }
}

extension Sequence where Element == Action {
    public var carriesSpokenText: Bool { contains { $0.carriesSpokenText } }
}
