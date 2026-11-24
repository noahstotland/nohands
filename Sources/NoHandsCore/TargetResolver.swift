import Foundation
import CoreGraphics

public enum TargetResolution: Equatable, Sendable { case point(CGPoint), failure(String) }

/// Resolves click/move targets to screen points (CG coordinates) at execution time.
public enum TargetResolver {
    // Two names, not an overload: `.numbered(1)` would be ambiguous between ClickTarget and MoveTarget.
    public static func resolveClick(_ t: ClickTarget, overlay: OverlayState, cursor: CGPoint,
                                    elements: [UIElementInfo], screens: [CGRect] = [],
                                    labels: [Int: UIElementInfo]? = nil) -> TargetResolution {
        switch t {
        case .label(let n): return snapshotLabel(n, labels: labels, screens: screens)
        case .cursor: return .point(cursor)
        case .point(let p): return .point(p)
        case .numbered(let n): return numbered(n, overlay: overlay, screens: screens)
        case .element(let name): return element(name, in: elements, screens: screens, labels: labels)
        }
    }

    public static func resolveMove(_ t: MoveTarget, overlay: OverlayState, cursor: CGPoint,
                                   elements: [UIElementInfo], screens: [CGRect] = [],
                                   labels: [Int: UIElementInfo]? = nil) -> TargetResolution {
        switch t {
        case .label(let n): return snapshotLabel(n, labels: labels, screens: screens)
        case .point(let p): return .point(p)
        case .numbered(let n): return numbered(n, overlay: overlay, screens: screens)
        case .element(let name): return element(name, in: elements, screens: screens, labels: labels)
        case .relative(let dx, let dy): return .point(CGPoint(x: cursor.x + CGFloat(dx), y: cursor.y + CGFloat(dy)))
        case .screenCenter:
            guard let screen = screens.first(where: { $0.contains(cursor) }) ?? screens.first else { return .failure("no screen") }
            return .point(CGPoint(x: screen.midX, y: screen.midY))
        }
    }

    /// `.label(n)` resolves ONLY against the snapshot the LLM was shown; never against a grid or the overlay.
    private static func snapshotLabel(_ n: Int, labels: [Int: UIElementInfo]?, screens: [CGRect]) -> TargetResolution {
        guard let e = labels?[n] else { return .failure("no label \(n)") }
        return .point(e.clickPoint(screens: screens))
    }

    private static func numbered(_ n: Int, overlay: OverlayState, screens: [CGRect]) -> TargetResolution {
        switch overlay {
        case .none: return .failure("no grid or labels shown")
        case .grid(let g):
            guard let c = g.center(of: n) else { return .failure("no cell \(n)") }
            return .point(c)
        case .labels(let labels):
            guard let e = labels[n] else { return .failure("no label \(n)") }
            return .point(e.clickPoint(screens: screens))
        }
    }

    /// An exact title wins; then a position ("first video") over the list the model saw; then a looser title match
    /// (prefix, contains), so a video titled "Reacting to my first video" cannot take over "first video".
    private static func element(_ name: String, in elements: [UIElementInfo], screens: [CGRect],
                                labels: [Int: UIElementInfo]?) -> TargetResolution {
        if let e = LabelAssigner.find(exactly: name, in: elements) { return .point(e.clickPoint(screens: screens)) }
        let ordinal = OrdinalTarget.parse(name)
        if let ordinal {
            let shown = labels ?? LabelAssigner.assign(elements)
            if let n = ordinal.label(in: shown), let e = shown[n] { return .point(e.clickPoint(screens: screens)) }
        }
        if let e = LabelAssigner.find(named: name, in: elements) { return .point(e.clickPoint(screens: screens)) }
        return .failure("no element named '\(name)'" + (ordinal == nil ? "" : "; say its label number from the list"))
    }
}
