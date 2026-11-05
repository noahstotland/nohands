import Foundation
import CoreGraphics

/// An agent-desktop `snapshot` flattened into numbered elements (depth-first, as agent-desktop drills).
public struct DesktopSnapshot: Equatable, Sendable {
    public var app: String
    public var snapshotID: String
    public var windowID: String?
    public var windowTitle: String?
    public var complete: Bool
    /// Every node with a `ref_id`, ids 1…N in depth-first order; `frame` is zero when the node had no bounds.
    public var elements: [UIElementInfo]

    public static let editableRoles: Set<String> = ["textfield", "textarea", "searchfield", "combobox"]

    /// Worth showing the model: it has a ref and a name, or a value, or is a field the user could type into.
    public static func listable(_ e: UIElementInfo) -> Bool {
        guard e.ref != nil else { return false }
        if !e.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if let v = e.value, !v.isEmpty { return true }
        return editableRoles.contains(e.role)
    }

    /// `data` of a snapshot envelope; nil without a `tree`.
    public static func parse(_ data: [String: Any]) -> DesktopSnapshot? {
        guard let tree = data["tree"] as? [String: Any] else { return nil }
        var elements: [UIElementInfo] = []
        func walk(_ node: [String: Any]) {
            if let ref = node["ref_id"] as? String {
                elements.append(UIElementInfo(
                    id: elements.count + 1, frame: frame(node["bounds"]),
                    title: node["name"] as? String ?? "", role: node["role"] as? String ?? "",
                    ref: ref, value: value(node["value"]), states: node["states"] as? [String] ?? []))
            }
            for child in node["children"] as? [[String: Any]] ?? [] { walk(child) }
        }
        walk(tree)
        let window = data["window"] as? [String: Any]
        return DesktopSnapshot(app: data["app"] as? String ?? "", snapshotID: data["snapshot_id"] as? String ?? "",
                               windowID: window?["id"] as? String, windowTitle: window?["title"] as? String,
                               complete: data["complete"] as? Bool ?? true, elements: elements)
    }

    private static func frame(_ v: Any?) -> CGRect {
        guard let b = v as? [String: Any], let x = b["x"] as? Double, let y = b["y"] as? Double,
              let w = b["width"] as? Double, let h = b["height"] as? Double else { return .zero }
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// Strings as they are; numbers and booleans as text; anything else (null, objects) nil.
    public static func value(_ v: Any?) -> String? {
        switch v {
        case let s as String: return s
        case let n as NSNumber: return CFGetTypeID(n) == CFBooleanGetTypeID() ? (n.boolValue ? "true" : "false") : n.stringValue
        default: return nil
        }
    }
}

/// `data.match` of a `find --first` envelope.
public struct DesktopFindMatch: Equatable, Sendable {
    public var ref: String
    public var role: String
    public var name: String
    public var path: [String]
    public var disabled: Bool

    public static func parse(_ data: [String: Any]) -> DesktopFindMatch? {
        guard let m = data["match"] as? [String: Any], let ref = m["ref_id"] as? String else { return nil }
        return DesktopFindMatch(ref: ref, role: m["role"] as? String ?? "", name: m["name"] as? String ?? "",
                                path: m["path"] as? [String] ?? [],
                                disabled: (m["states"] as? [String] ?? []).contains("disabled"))
    }
}
