import Foundation

public struct IntentContext: Sendable {
    public var frontmostApp: String
    public var mode: Mode
    public var labeledElements: [(number: Int, title: String)]
    public init(frontmostApp: String, mode: Mode, labeledElements: [(number: Int, title: String)]) {
        self.frontmostApp = frontmostApp
        self.mode = mode
        self.labeledElements = labeledElements
    }
}

public enum IntentSchema {
    static let kinds = ["type_text", "press_key", "click", "press_mouse", "release_mouse", "move_cursor",
                        "scroll", "show_grid", "zoom_grid", "show_labels", "hide_overlay", "set_mode",
                        "open_app", "ignore"]
    static let targetKinds = ["cursor", "grid_cell", "label", "element", "point", "relative"]

    nonisolated(unsafe) public static let actionsJSONSchema: [String: Any] = {
        let action: [String: Any] = [
            "type": "object",
            "properties": [
                "kind": ["type": "string", "enum": kinds],
                "text": ["type": "string"],
                "key": ["type": "string", "enum": Key.allCases.map(\.rawValue)],
                "modifiers": ["type": "array", "items": ["type": "string", "enum": Modifier.allCases.map(\.rawValue)]],
                "button": ["type": "string", "enum": ["left", "right", "middle"]],
                "count": ["type": "integer"],
                "target_kind": ["type": "string", "enum": targetKinds],
                "target_number": ["type": "integer"],
                "target_name": ["type": "string"],
                "x": ["type": "number"],
                "y": ["type": "number"],
                "dx": ["type": "integer"],
                "dy": ["type": "integer"],
                "direction": ["type": "string", "enum": ["up", "down", "left", "right"]],
                "amount": ["type": "integer"],
                "mode": ["type": "string", "enum": ["command", "dictation", "sleep"]],
                "app_name": ["type": "string"],
            ] as [String: Any],
            "required": ["kind"],
            "additionalProperties": false,
        ]
        return [
            "type": "object",
            "properties": ["actions": ["type": "array", "items": action] as [String: Any]] as [String: Any],
            "required": ["actions"],
            "additionalProperties": false,
        ]
    }()

    public static let systemPrompt: String = """
    You convert a spoken request for a hands-free macOS voice-control app into a list of actions. \
    Reply only with JSON matching the provided schema: {"actions":[...]}. Each action has a "kind":
    - type_text: type literal text. Fields: text.
    - press_key: press a key chord. Fields: key, modifiers (command, shift, option, control, function).
    - click: click something. Fields: target_kind (cursor, grid_cell, label, element), target_number (for grid_cell or label), target_name (for element), button (left, right, middle; default left), count (default 1).
    - press_mouse: hold a mouse button down. Fields: button (default left).
    - release_mouse: release a held mouse button. Fields: button (default left).
    - move_cursor: move the pointer. Fields: target_kind (grid_cell, label, element, point, relative), target_number, target_name, x and y (point), dx and dy (relative, in pixels).
    - scroll: scroll the view. Fields: direction (up, down, left, right), amount (lines).
    - show_grid: show the numbered screen grid. No fields.
    - zoom_grid: zoom into a grid cell. Fields: target_number.
    - show_labels: label clickable elements in the frontmost app. No fields.
    - hide_overlay: hide any grid or labels. No fields.
    - set_mode: switch mode. Fields: mode (command, dictation, sleep).
    - open_app: open or switch to an application. Fields: app_name.
    - ignore: do nothing. No fields.

    Rules:
    1. Emit the fewest actions that accomplish the request.
    2. If the request is ambiguous or is not an action, return [{"kind":"ignore"}].
    3. Refer to visible elements by their label number when one is listed; never invent app names.
    """
}
