import Foundation
import CoreGraphics

public enum CoordinateMapper {
    public static func toAppKit(_ p: CGPoint, primaryScreenHeight: CGFloat) -> CGPoint {
        CGPoint(x: p.x, y: primaryScreenHeight - p.y)
    }

    public static func toAppKit(_ r: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: r.minX, y: primaryScreenHeight - r.maxY, width: r.width, height: r.height)
    }

    public static func toCG(_ p: CGPoint, primaryScreenHeight: CGFloat) -> CGPoint {
        CGPoint(x: p.x, y: primaryScreenHeight - p.y)
    }
}
