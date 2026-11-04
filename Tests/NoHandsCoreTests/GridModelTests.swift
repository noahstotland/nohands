import Testing
import CoreGraphics
@testable import NoHandsCore

@Test func gridCellsAreRowMajorOneBased() {
    let g = GridModel(bounds: CGRect(x: 0, y: 0, width: 1000, height: 800))
    #expect(g.cellCount == 80)
    #expect(g.frame(of: 1) == CGRect(x: 0, y: 0, width: 100, height: 100))
    #expect(g.frame(of: 10) == CGRect(x: 900, y: 0, width: 100, height: 100))
    #expect(g.frame(of: 11) == CGRect(x: 0, y: 100, width: 100, height: 100))
    #expect(g.center(of: 80) == CGPoint(x: 950, y: 750))
    #expect(g.frame(of: 0) == nil)
    #expect(g.frame(of: 81) == nil)
}

@Test func zoomSubdividesCell() {
    let g = GridModel(bounds: CGRect(x: 0, y: 0, width: 1000, height: 800))
    let z = g.zoomed(into: 12)!
    #expect(z.bounds == CGRect(x: 100, y: 100, width: 100, height: 100))
    #expect(z.center(of: 1) == CGPoint(x: 105, y: 106.25))
    #expect(g.zoomed(into: 99) == nil)
}
