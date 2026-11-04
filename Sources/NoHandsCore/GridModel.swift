import Foundation
import CoreGraphics

public struct GridModel: Equatable, Sendable {
    public let bounds: CGRect
    public let columns: Int
    public let rows: Int

    public init(bounds: CGRect, columns: Int = 10, rows: Int = 8) {
        self.bounds = bounds
        self.columns = max(1, columns)
        self.rows = max(1, rows)
    }

    public var cellCount: Int { columns * rows }

    /// 1-based, row-major; nil if out of range.
    public func frame(of cell: Int) -> CGRect? {
        guard cell >= 1, cell <= cellCount else { return nil }
        let index = cell - 1
        let col = index % columns
        let row = index / columns
        let w = bounds.width / CGFloat(columns)
        let h = bounds.height / CGFloat(rows)
        return CGRect(x: bounds.minX + CGFloat(col) * w,
                      y: bounds.minY + CGFloat(row) * h,
                      width: w, height: h)
    }

    public func center(of cell: Int) -> CGPoint? {
        guard let f = frame(of: cell) else { return nil }
        return CGPoint(x: f.midX, y: f.midY)
    }

    public func zoomed(into cell: Int) -> GridModel? {
        guard let f = frame(of: cell) else { return nil }
        return GridModel(bounds: f, columns: columns, rows: rows)
    }
}
