import Foundation
import CoreGraphics

/// A picture of the focused window, in memory only. `windowFrame` is in global display coordinates with a top-left
/// origin (a window on a screen left of the primary has a negative x).
public struct StepScreenshot: Sendable, Equatable {
    public var jpeg: Data
    public var imageSize: CGSize
    public var windowFrame: CGRect
    public var app: String
    public init(jpeg: Data, imageSize: CGSize, windowFrame: CGRect, app: String) {
        self.jpeg = jpeg; self.imageSize = imageSize; self.windowFrame = windowFrame; self.app = app
    }
}

public enum PointMapping: Equatable, Sendable { case mapped([Action]), refused(String) }

/// Pure maths between a window picture and the screen.
public enum ScreenshotGeometry {
    public static let outsideReason = "point outside the screenshot"
    public static let notFirstReason = "point must be the step's first action"

    /// Longest side at most `maxSide`, never larger than the window's real pixels. Aspect kept, whole pixels, each side at least 1.
    public static func imageSize(window: CGSize, backingScale: CGFloat, maxSide: CGFloat = 1200) -> CGSize {
        let w = window.width * backingScale, h = window.height * backingScale
        let k = min(1, maxSide / max(w, h, 1))
        return CGSize(width: max(1, (w * k).rounded()), height: max(1, (h * k).rounded()))
    }

    public static func screenPoint(fromImage p: CGPoint, shot: StepScreenshot) -> CGPoint {
        CGPoint(x: shot.windowFrame.minX + p.x * shot.windowFrame.width / shot.imageSize.width,
                y: shot.windowFrame.minY + p.y * shot.windowFrame.height / shot.imageSize.height)
    }

    public static func imagePoint(fromScreen p: CGPoint, shot: StepScreenshot) -> CGPoint {
        CGPoint(x: (p.x - shot.windowFrame.minX) * shot.imageSize.width / shot.windowFrame.width,
                y: (p.y - shot.windowFrame.minY) * shot.imageSize.height / shot.windowFrame.height)
    }

    /// Rewrites the `.point` in click, move_cursor or drag (both ends) from picture to screen coordinates, or says
    /// why not. A point is valid only in the step's first action, and only one action may hold one.
    public static func mapPoints(_ actions: [Action], shot: StepScreenshot) -> PointMapping {
        let holders = actions.indices.filter { !points(in: actions[$0]).isEmpty }
        if holders.isEmpty { return .mapped(actions) }
        if holders != [0] { return .refused(notFirstReason) }
        // Inclusive of the far edge: CGRect.contains is not.
        let size = shot.imageSize
        if points(in: actions[0]).contains(where: { !(0...size.width).contains($0.x) || !(0...size.height).contains($0.y) }) { return .refused(outsideReason) }
        var mapped = actions
        mapped[0] = rewrite(actions[0]) { screenPoint(fromImage: $0, shot: shot) }
        return .mapped(mapped)
    }

    private static func points(in action: Action) -> [CGPoint] {
        func p(_ t: MoveTarget) -> [CGPoint] { if case .point(let q) = t { [q] } else { [] } }
        switch action {
        case .click(.point(let q), _, _): return [q]
        case .moveCursor(let t): return p(t)
        case .drag(let from, let to): return p(from) + p(to)
        default: return []
        }
    }

    private static func rewrite(_ action: Action, _ f: (CGPoint) -> CGPoint) -> Action {
        func m(_ t: MoveTarget) -> MoveTarget { if case .point(let q) = t { .point(f(q)) } else { t } }
        switch action {
        case .click(.point(let q), let b, let n): return .click(.point(f(q)), button: b, count: n)
        case .moveCursor(let t): return .moveCursor(m(t))
        case .drag(let from, let to): return .drag(from: m(from), to: m(to))
        default: return action
        }
    }
}
