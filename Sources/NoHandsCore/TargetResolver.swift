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
        case .element(let name): return element(name, in: elements, screens: screens)
        }
    }

    public static func resolveMove(_ t: MoveTarget, overlay: OverlayState, cursor: CGPoint,
                                   elements: [UIElementInfo], screens: [CGRect] = [],
                                   labels: [Int: UIElementInfo]? = nil) -> TargetResolution {
        switch t {
        case .label(let n): return snapshotLabel(n, labels: labels, screens: screens)
        case .point(let p): return .point(p)
        case .numbered(let n): return numbered(n, overlay: overlay, screens: screens)
        case .element(let name): return element(name, in: elements, screens: screens)
        case .relative(let dx, let dy): return .point(CGPoint(x: cursor.x + CGFloat(dx), y: cursor.y + CGFloat(dy)))
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

    private static func element(_ name: String, in elements: [UIElementInfo], screens: [CGRect]) -> TargetResolution {
        guard let e = LabelAssigner.find(named: name, in: elements) else { return .failure("no element named '\(name)'") }
        return .point(e.clickPoint(screens: screens))
    }
}
