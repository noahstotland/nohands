import Foundation

extension Action {
    /// True when the action's payload is words the speaker may still be saying (typed text, an app or site, a search,
    /// a spoken element name). Such a command keeps the full silence window, so "type hello … world" is not cut in half.
    /// Exhaustive on purpose: a new action must choose. The harness and tab actions only come from the model; the
    /// ones that carry text or a name answer true.
    public var carriesSpokenText: Bool {
        switch self {
        case .typeText, .openApp, .openURL, .search, .searchSite, .setValue, .typeInto, .selectOption, .clickIn,
             .menuItem, .closeApp, .clipboardSet, .findOnPage:
            return true
        case .click(let target, _, _):
            if case .element = target { return true }
            return false
        case .moveCursor(let target):
            if case .element = target { return true }
            return false
        // A name may still be coming; a standard folder or "my last <kind>" is whole.
        case .openFile(let request):
            if case .named = request { return true }
            return false
        case .windowAction(_, let app, let title): return app != nil || title != nil
        case .goToTab(let target):
            if case .named = target { return true }
            return false
        case .editText(let edit, _): return edit.targetsPhrase
        // A language or the speaker's own words may still be coming; a preset is complete.
        case .rewriteText(let how):
            if case .style = how { return false }
            return true
        // Open-ended leads: "play ... bohemian rhapsody", "skip ahead ... thirty seconds", "volume up ... three".
        case .media(let command):
            if case .play = command { return true }
            if case .skip = command { return true }
            return false
        case .volume(let change):
            if case .mute = change { return false }
            return true
        case .pressKey, .pressMouse, .releaseMouse, .scroll, .showGrid, .zoomGrid, .showLabels, .hideOverlay, .setMode, .setSpokenFeedback,
             .moveWindow, .wait, .checkMedia, .ignore, .clearField, .setChecked, .setExpanded, .focusElement, .scrollTo,
             .scrollIn, .drag, .readClipboard, .readPage, .readValue, .readNotifications, .dismissNotifications, .waitFor,
             .closeTab, .closeWindow, .selectTab, .closeOtherTabs, .listTabs, .look, .system:
            return false
        }
    }
}

extension CommandGrammar {
    /// True when the utterance opens with "rewrite": "rewrite that" may be followed, after a pause, by the speaker's own
    /// instruction ("as a formal email"), so it counts as open-ended even though the preset it parses to is complete.
    public static func opensRewrite(_ transcript: String) -> Bool { normalize(transcript).first == "rewrite" }
}

extension Sequence where Element == Action {
    public var carriesSpokenText: Bool { contains { $0.carriesSpokenText } }
}
