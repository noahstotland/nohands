import Foundation

public enum IntentDecodeError: Error, Equatable { case refusal, noTextBlock, malformed(String) }

public enum IntentDecoder {
    public static func step(fromResponse data: Data) throws -> IntentStep {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw IntentDecodeError.malformed("response is not a JSON object")
        }
        if root["stop_reason"] as? String == "refusal" { throw IntentDecodeError.refusal }
        let blocks = root["content"] as? [[String: Any]] ?? []
        guard let block = blocks.first(where: { $0["type"] as? String == "text" }),
              let text = block["text"] as? String else {
            throw IntentDecodeError.noTextBlock
        }
        return try step(fromPayloadText: text)
    }

    public static func step(fromPayloadText text: String) throws -> IntentStep {
        guard let payload = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any],
              let list = payload["actions"] as? [Any] else {
            throw IntentDecodeError.malformed("text block is not {\"actions\":[...]}")
        }
        // Missing or unknown status: an old-style one-shot payload, which means "run these and finish".
        let status = (payload["status"] as? String).flatMap(StepStatus.init(rawValue:)) ?? .done
        return IntentStep(intent: payload["intent"] as? String ?? "", status: status,
                          actions: list.compactMap { ($0 as? [String: Any]).flatMap(action(from:)) })
    }

    public static func step(fromOllamaResponse data: Data) throws -> IntentStep {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw IntentDecodeError.malformed("response is not a JSON object")
        }
        guard let message = root["message"] as? [String: Any], let content = message["content"] as? String else {
            throw IntentDecodeError.noTextBlock
        }
        return try step(fromPayloadText: content)
    }

    public static func actions(fromResponse data: Data) throws -> [Action] { try step(fromResponse: data).actions }
    public static func actions(fromPayloadText text: String) throws -> [Action] { try step(fromPayloadText: text).actions }
    public static func actions(fromOllamaResponse data: Data) throws -> [Action] { try step(fromOllamaResponse: data).actions }

    /// Strict integer: JSON number (not boolean), finite, integral, exactly representable.
    private static func int(_ v: Any?) -> Int? {
        guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        let d = n.doubleValue
        guard d.isFinite, d == d.rounded() else { return nil }
        return Int(exactly: d)
    }
    private static func double(_ v: Any?) -> Double? {
        guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        let d = n.doubleValue
        return d.isFinite ? d : nil
    }
    private static func clamp(_ v: Int, _ r: ClosedRange<Int>) -> Int { min(max(v, r.lowerBound), r.upperBound) }

    private enum Opt<T> { case absent, invalid, value(T) }
    private static func optInt(_ o: [String: Any], _ k: String) -> Opt<Int> {
        guard let v = o[k] else { return .absent }
        return int(v).map(Opt.value) ?? .invalid
    }
    private static func optButton(_ o: [String: Any]) -> Opt<MouseButton> {
        guard let v = o["button"] else { return .absent }
        return (v as? String).flatMap(MouseButton.init(rawValue:)).map(Opt.value) ?? .invalid
    }
    private static func nonBlank(_ v: Any?) -> String? {
        guard let s = v as? String, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return s
    }
    private static func number(_ v: Any?) -> Int? { int(v).flatMap { $0 >= 1 ? $0 : nil } }

    private static func action(from o: [String: Any]) -> Action? {
        guard let kind = o["kind"] as? String else { return nil }
        switch kind {
        case "type_text":
            return nonBlank(o["text"]).map(Action.typeText)
        case "press_key":
            guard let k = (o["key"] as? String).flatMap(Key.init(rawValue:)) else { return nil }
            var mods = Set<Modifier>()
            if let raw = o["modifiers"] {
                guard let arr = raw as? [Any] else { return nil }
                for m in arr {
                    guard let name = m as? String, let mod = Modifier(rawValue: name) else { return nil }
                    mods.insert(mod)
                }
            }
            return .pressKey(KeyChord(k, mods))
        case "click":
            guard let t = clickTarget(o) else { return nil }
            var count = 1
            switch optInt(o, "count") {
            case .absent: break
            case .invalid: return nil
            case .value(let c): count = clamp(c, 1...10)
            }
            switch optButton(o) {
            case .absent: return .click(t, button: .left, count: count)
            case .invalid: return nil
            case .value(let b): return .click(t, button: b, count: count)
            }
        case "press_mouse", "release_mouse":
            var b = MouseButton.left
            switch optButton(o) {
            case .absent: break
            case .invalid: return nil
            case .value(let v): b = v
            }
            return kind == "press_mouse" ? .pressMouse(b) : .releaseMouse(b)
        case "move_cursor":
            return moveTarget(o).map(Action.moveCursor)
        case "scroll":
            guard let d = (o["direction"] as? String).flatMap(Direction.init(rawValue:)) else { return nil }
            switch optInt(o, "amount") {
            case .absent: return .scroll(d, amount: 1)
            case .invalid: return nil
            case .value(let a): return .scroll(d, amount: clamp(a, 1...100))
            }
        case "show_grid": return .showGrid
        case "zoom_grid": return number(o["target_number"]).map(Action.zoomGrid)
        case "show_labels": return .showLabels
        case "hide_overlay": return .hideOverlay
        case "set_mode":
            return (o["mode"] as? String).flatMap(Mode.init(rawValue:)).map(Action.setMode)
        case "open_app":
            return nonBlank(o["app_name"]).map(Action.openApp)
        case "open_url":
            guard let url = nonBlank(o["url"]).flatMap(WebAddress.url(for:)) else { return nil }
            return .openURL(url, app: nonBlank(o["app_name"]))
        case "move_window":
            return (o["placement"] as? String).flatMap(WindowPlacement.init(rawValue:)).map(Action.moveWindow)
        case "search": return nonBlank(o["text"]).map(Action.search)
        case "wait":
            if o["wait_for"] != nil { return waitFor(o) }
            switch optInt(o, "ms") {
            case .absent, .invalid: return .wait(ms: 1000)
            case .value(let ms): return .wait(ms: clamp(ms, 100...5000))
            }
        case "ignore": return .ignore

        // Harness kinds.
        case "set_value":
            guard let t = elementTarget(o), let v = o["value"] as? String else { return nil }
            return v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .clearField(t) : .setValue(t, v)
        case "type_into":
            guard let t = elementTarget(o), let text = nonBlank(o["text"]) else { return nil }
            return .typeInto(t, text)
        case "clear": return elementTarget(o).map(Action.clearField)
        case "select":
            guard let t = elementTarget(o), let option = nonBlank(o["option"]) else { return nil }
            return .selectOption(t, option)
        case "check": return elementTarget(o).map { .setChecked($0, true) }
        case "uncheck": return elementTarget(o).map { .setChecked($0, false) }
        case "toggle": return elementTarget(o).map { .setChecked($0, nil) }
        case "expand": return elementTarget(o).map { .setExpanded($0, true) }
        case "collapse": return elementTarget(o).map { .setExpanded($0, false) }
        case "focus": return elementTarget(o).map(Action.focusElement)
        case "scroll_to": return elementTarget(o).map(Action.scrollTo)
        case "scroll_element":
            guard let t = elementTarget(o), let d = (o["direction"] as? String).flatMap(Direction.init(rawValue:)) else { return nil }
            switch optInt(o, "amount") {
            case .absent: return .scrollIn(t, d, amount: 3)
            case .invalid: return nil
            case .value(let a): return .scrollIn(t, d, amount: clamp(a, 1...100))
            }
        case "drag":
            guard let from = dragSource(o), let to = moveTarget(o) else { return nil }
            return .drag(from: from, to: to)
        case "click_in":
            guard let s = (o["surface"] as? String).flatMap(DesktopSurface.init(rawValue:)),
                  let name = nonBlank(o["target_name"]) else { return nil }
            return .clickIn(s, name: name)
        case "menu_item": return nonBlank(o["target_name"]).map(Action.menuItem)
        case "close_app": return nonBlank(o["app_name"]).map(Action.closeApp)
        case "window":
            guard let op = (o["window_action"] as? String).flatMap(DesktopWindowOp.init(rawValue:)) else { return nil }
            return .windowAction(op, app: nonBlank(o["app_name"]), title: op == .focus ? nonBlank(o["title"]) : nil)
        case "clipboard_set": return (o["value"] as? String).map(Action.clipboardSet)
        case "read_clipboard": return .readClipboard
        case "read_value": return elementTarget(o).map(Action.readValue)
        case "read_notifications": return .readNotifications
        case "close_tab": return number(o["target_number"]).map(Action.closeTab)
        case "close_window": return number(o["target_number"]).map(Action.closeWindow)
        case "select_tab": return number(o["target_number"]).map(Action.selectTab)
        case "dismiss_notifications": return .dismissNotifications(app: nonBlank(o["app_name"]))
        default: return nil
        }
    }

    private static func elementTarget(_ o: [String: Any]) -> ElementTarget? {
        switch o["target_kind"] as? String {
        case "label": return number(o["target_number"]).map(ElementTarget.label)
        case "element": return nonBlank(o["target_name"]).map(ElementTarget.named)
        default:
            // Without a target_kind, a bare number or name still identifies the element.
            if let n = number(o["target_number"]) { return .label(n) }
            if let name = nonBlank(o["target_name"]) { return .named(name) }
            return nil
        }
    }

    /// `drag`'s source: `from_number`, `from_name`, or `from_x`/`from_y`.
    private static func dragSource(_ o: [String: Any]) -> MoveTarget? {
        if let n = number(o["from_number"]) { return .label(n) }
        if let name = nonBlank(o["from_name"]) { return .element(named: name) }
        if let x = double(o["from_x"]), let y = double(o["from_y"]),
           (-20000...20000).contains(x), (-20000...20000).contains(y) { return .point(CGPoint(x: x, y: y)) }
        return nil
    }

    private static func waitFor(_ o: [String: Any]) -> Action? {
        guard let kind = (o["wait_for"] as? String).flatMap(DesktopWaitKind.init(rawValue:)) else { return nil }
        var timeout = 5000
        switch optInt(o, "timeout_ms") {
        case .absent: break
        case .invalid: return nil
        case .value(let t): timeout = clamp(t, 500...30000)
        }
        let condition: WaitCondition
        switch kind {
        case .text: guard let v = nonBlank(o["value"]) else { return nil }; condition = .text(v)
        case .window: guard let v = nonBlank(o["value"]) else { return nil }; condition = .window(v)
        case .event:
            guard let e = (o["event"] as? String).flatMap(DesktopEvent.init(rawValue:)) else { return nil }
            condition = .event(e)
        case .menu: condition = .menu
        case .menuClosed: condition = .menuClosed
        case .mediaPlaying: condition = .mediaPlaying
        case .element:
            guard let t = elementTarget(o) else { return nil }
            condition = .element(t, predicate: nonBlank(o["value"]) ?? nonBlank(o["predicate"]) ?? "exists")
        }
        return .waitFor(condition, timeoutMs: timeout)
    }

    private static func point(_ o: [String: Any]) -> CGPoint? {
        guard let x = double(o["x"]), let y = double(o["y"]),
              (-20000...20000).contains(x), (-20000...20000).contains(y) else { return nil }
        return CGPoint(x: x, y: y)
    }

    private static func clickTarget(_ o: [String: Any]) -> ClickTarget? {
        switch o["target_kind"] as? String {
        case "cursor": return .cursor
        case "grid_cell": return number(o["target_number"]).map(ClickTarget.numbered)
        case "label": return number(o["target_number"]).map(ClickTarget.label)
        case "element": return nonBlank(o["target_name"]).map { .element(named: $0) }
        case "point":
            return point(o).map { .point($0) }
        default: return nil
        }
    }

    private static func moveTarget(_ o: [String: Any]) -> MoveTarget? {
        switch o["target_kind"] as? String {
        case "grid_cell": return number(o["target_number"]).map(MoveTarget.numbered)
        case "label": return number(o["target_number"]).map(MoveTarget.label)
        case "element": return nonBlank(o["target_name"]).map { .element(named: $0) }
        case "point":
            return point(o).map { .point($0) }
        case "relative":
            guard let dx = int(o["dx"]), let dy = int(o["dy"]) else { return nil }
            return .relative(dx: clamp(dx, -10000...10000), dy: clamp(dy, -10000...10000))
        default: return nil
        }
    }
}
