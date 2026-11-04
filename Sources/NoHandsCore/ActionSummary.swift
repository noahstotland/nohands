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
        case .ignore: "ignore"
        }
    }
}
