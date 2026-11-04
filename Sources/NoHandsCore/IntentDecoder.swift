import Foundation

public enum IntentDecodeError: Error, Equatable { case refusal, noTextBlock, malformed(String) }

public enum IntentDecoder {
    public static func actions(fromResponse data: Data) throws -> [Action] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw IntentDecodeError.malformed("response is not a JSON object")
        }
        if root["stop_reason"] as? String == "refusal" { throw IntentDecodeError.refusal }
        let blocks = root["content"] as? [[String: Any]] ?? []
        guard let block = blocks.first(where: { $0["type"] as? String == "text" }),
              let text = block["text"] as? String else {
            throw IntentDecodeError.noTextBlock
        }
        guard let payload = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any],
              let list = payload["actions"] as? [Any] else {
            throw IntentDecodeError.malformed("text block is not {\"actions\":[...]}")
        }
        return list.compactMap { ($0 as? [String: Any]).flatMap(action(from:)) }
    }

    private static func int(_ v: Any?) -> Int? {
        if let i = v as? Int { return i }
        if let d = v as? Double, d == d.rounded() { return Int(d) }
        return nil
    }
    private static func double(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue }

    private static func action(from o: [String: Any]) -> Action? {
        guard let kind = o["kind"] as? String else { return nil }
        let button = (o["button"] as? String).flatMap(MouseButton.init(rawValue:))
        switch kind {
        case "type_text":
            return (o["text"] as? String).map(Action.typeText)
        case "press_key":
            guard let k = (o["key"] as? String).flatMap(Key.init(rawValue:)) else { return nil }
            let mods = (o["modifiers"] as? [String] ?? []).compactMap(Modifier.init(rawValue:))
            return .pressKey(KeyChord(k, Set(mods)))
        case "click":
            guard let t = clickTarget(o) else { return nil }
            return .click(t, button: button ?? .left, count: max(1, int(o["count"]) ?? 1))
        case "press_mouse": return .pressMouse(button ?? .left)
        case "release_mouse": return .releaseMouse(button ?? .left)
        case "move_cursor":
            return moveTarget(o).map(Action.moveCursor)
        case "scroll":
            guard let d = (o["direction"] as? String).flatMap(Direction.init(rawValue:)) else { return nil }
            return .scroll(d, amount: int(o["amount"]) ?? 1)
        case "show_grid": return .showGrid
        case "zoom_grid": return int(o["target_number"]).map(Action.zoomGrid)
        case "show_labels": return .showLabels
        case "hide_overlay": return .hideOverlay
        case "set_mode":
            return (o["mode"] as? String).flatMap(Mode.init(rawValue:)).map(Action.setMode)
        case "open_app":
            return (o["app_name"] as? String).map(Action.openApp)
        case "ignore": return .ignore
        default: return nil
        }
    }

    private static func clickTarget(_ o: [String: Any]) -> ClickTarget? {
        switch o["target_kind"] as? String {
        case "cursor": return .cursor
        case "grid_cell", "label": return int(o["target_number"]).map(ClickTarget.numbered)
        case "element": return (o["target_name"] as? String).map { .element(named: $0) }
        case "point":
            guard let x = double(o["x"]), let y = double(o["y"]) else { return nil }
            return .point(CGPoint(x: x, y: y))
        default: return nil
        }
    }

    private static func moveTarget(_ o: [String: Any]) -> MoveTarget? {
        switch o["target_kind"] as? String {
        case "grid_cell", "label": return int(o["target_number"]).map(MoveTarget.numbered)
        case "element": return (o["target_name"] as? String).map { .element(named: $0) }
        case "point":
            guard let x = double(o["x"]), let y = double(o["y"]) else { return nil }
            return .point(CGPoint(x: x, y: y))
        case "relative":
            guard let dx = int(o["dx"]), let dy = int(o["dy"]) else { return nil }
            return .relative(dx: dx, dy: dy)
        default: return nil
        }
    }
}
