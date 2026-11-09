import Foundation

/// Payload-free description of actions, safe for persistent public logs: action kinds and typed-text length
/// only. Never includes typed text, element names, app names or key names.
public enum ActionSummary {
    public static func kinds(_ actions: [Action]) -> String {
        "[" + actions.map(kind).joined(separator: ", ") + "]"
    }

    public static func kind(_ action: Action) -> String {
        switch action {
        case .typeText(let t): "typeText(len=\(t.count))"
        case .pressKey: "pressKey"
        case .click: "click"
        case .pressMouse: "pressMouse"
        case .releaseMouse: "releaseMouse"
        case .moveCursor: "moveCursor"
        case .scroll: "scroll"
        case .showGrid: "showGrid"
        case .zoomGrid: "zoomGrid"
        case .showLabels: "showLabels"
        case .hideOverlay: "hideOverlay"
        case .setMode(let m): "setMode(\(m.rawValue))"
        case .openApp: "openApp"
        case .openURL: "openURL"
        case .moveWindow(let p): "moveWindow(\(p.rawValue))"
        case .search(let q): "search(len=\(q.count))"
        case .searchSite(let q, let site): "searchSite(len=\(q.count), site=\(site))"
        case .wait: "wait"
        case .checkMedia: "checkMedia"
        case .ignore: "ignore"
        case .setValue(_, let t): "setValue(len=\(t.count))"
        case .typeInto(_, let t): "typeInto(len=\(t.count))"
        case .clearField: "clearField"
        case .selectOption: "selectOption"
        case .setChecked: "setChecked"
        case .setExpanded: "setExpanded"
        case .focusElement: "focusElement"
        case .scrollTo: "scrollTo"
        case .scrollIn: "scrollIn"
        case .drag: "drag"
        case .clickIn(let s, _): "clickIn(\(s.rawValue))"
        case .menuItem: "menuItem"
        case .closeApp: "closeApp"
        case .windowAction(let op, _, _): "windowAction(\(op.rawValue))"
        case .clipboardSet(let t): "clipboardSet(len=\(t.count))"
        case .readClipboard: "readClipboard"
        case .readValue: "readValue"
        case .readNotifications: "readNotifications"
        case .dismissNotifications: "dismissNotifications"
        case .waitFor(let c, _): "waitFor(\(Self.waitKind(c)))"
        case .closeTab(let n): "closeTab(\(n))"
        case .closeWindow(let n): "closeWindow(\(n))"
        case .selectTab(let n): "selectTab(\(n))"
        case .look: "look"
        }
    }

    static func waitKind(_ c: WaitCondition) -> String {
        switch c {
        case .text: "text"
        case .window: "window"
        case .event: "event"
        case .menu: "menu"
        case .menuClosed: "menu_closed"
        case .element: "element"
        case .mediaPlaying: "media_playing"
        }
    }
}
