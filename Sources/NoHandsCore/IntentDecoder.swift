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
        case "ignore": return .ignore
        default: return nil
        }
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
