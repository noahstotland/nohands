import Foundation
import CoreGraphics

/// What the overlay currently shows. Lives in Core so resolvers can read it without AppKit.
public enum OverlayState: Equatable, Sendable {
    case none
    case grid(GridModel)
    case labels([Int: UIElementInfo])
}

/// Pure drawing math for the overlay (all in CG, top-left-origin space).
public enum OverlayMath {
    /// Top-left corner of the element, shifted so the badge stays fully inside `screen`.
    /// If the badge is larger than the screen it is pinned to the screen's origin.
    public static func badgeOrigin(for frame: CGRect, badgeSize: CGSize, in screen: CGRect) -> CGPoint {
        let maxX = screen.maxX - badgeSize.width
        let maxY = screen.maxY - badgeSize.height
        let x = max(screen.minX, min(frame.minX, maxX))
        let y = max(screen.minY, min(frame.minY, maxY))
        return CGPoint(x: x, y: y)
    }

    /// 14 pt by default; shrinks so a two-digit number fits in small cells; never below 9 pt.
    public static func fontSize(forCell cell: CGSize) -> CGFloat {
        let fitW = cell.width / 2.4
        let fitH = cell.height / 1.6
        return max(9, min(14, fitW, fitH))
    }
}
