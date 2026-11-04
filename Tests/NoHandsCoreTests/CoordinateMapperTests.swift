import Testing
import CoreGraphics
@testable import NoHandsCore

@Test func coordinateFlip() {
    #expect(CoordinateMapper.toAppKit(CGPoint(x: 10, y: 20), primaryScreenHeight: 1000) == CGPoint(x: 10, y: 980))
    #expect(CoordinateMapper.toCG(CGPoint(x: 10, y: 980), primaryScreenHeight: 1000) == CGPoint(x: 10, y: 20))
    #expect(CoordinateMapper.toAppKit(CGRect(x: 0, y: 0, width: 100, height: 50), primaryScreenHeight: 1000) == CGRect(x: 0, y: 950, width: 100, height: 50))
}
