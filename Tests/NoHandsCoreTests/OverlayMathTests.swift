import Testing
import CoreGraphics
@testable import NoHandsCore

@Suite struct OverlayMathTests {
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let badge = CGSize(width: 30, height: 18)

    @Test func insideUnchanged() {
        let p = OverlayMath.badgeOrigin(for: CGRect(x: 100, y: 50, width: 80, height: 20), badgeSize: badge, in: screen)
        #expect(p == CGPoint(x: 100, y: 50))
    }
    @Test func clampsRightAndBottom() {
        let p = OverlayMath.badgeOrigin(for: CGRect(x: 990, y: 795, width: 50, height: 50), badgeSize: badge, in: screen)
        #expect(p == CGPoint(x: 970, y: 782))
    }
    @Test func clampsLeftAndTop() {
        let p = OverlayMath.badgeOrigin(for: CGRect(x: -20, y: -5, width: 50, height: 50), badgeSize: badge, in: screen)
        #expect(p == CGPoint(x: 0, y: 0))
    }
    @Test func offsetScreen() {
        let s = CGRect(x: 1000, y: -200, width: 500, height: 400)
        let p = OverlayMath.badgeOrigin(for: CGRect(x: 1490, y: -300, width: 10, height: 10), badgeSize: badge, in: s)
        #expect(p == CGPoint(x: 1470, y: -200))
    }
    @Test func fontDefaultAndShrink() {
        #expect(OverlayMath.fontSize(forCell: CGSize(width: 190, height: 135)) == 14)
        let mid = OverlayMath.fontSize(forCell: CGSize(width: 24, height: 100))
        #expect(mid == 10)
        #expect(OverlayMath.fontSize(forCell: CGSize(width: 5, height: 5)) == 9)
    }
}
