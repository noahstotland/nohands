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

    @Test func hudTextCollapsesAndTruncates() {
        #expect(OverlayMath.hudText("  a \n\t b  ") == "a b")
        #expect(OverlayMath.hudText(" \n ") == nil)
        #expect(OverlayMath.hudText("") == nil)
        let long = String(repeating: "x", count: 200)
        let out = OverlayMath.hudText(long)!
        #expect(out.count == 80)
        #expect(out.hasSuffix("\u{2026}"))
        #expect(OverlayMath.hudText(String(repeating: "y", count: 80))!.count == 80)
    }
    @Test func screenIndexSelection() {
        let screens = [CGRect(x: 0, y: 0, width: 100, height: 100), CGRect(x: 100, y: 0, width: 100, height: 100)]
        #expect(OverlayMath.screenIndex(for: CGRect(x: 150, y: 10, width: 10, height: 10), in: screens) == 1)
        #expect(OverlayMath.screenIndex(for: CGRect(x: -5, y: 10, width: 20, height: 10), in: screens) == 0)
        #expect(OverlayMath.screenIndex(for: CGRect(x: 500, y: 500, width: 10, height: 10), in: screens) == nil)
    }

    @Test func drawnLabelsDropsOffScreen() {
        let screens = [CGRect(x: 0, y: 0, width: 100, height: 100)]
        func el(_ id: Int, _ f: CGRect) -> UIElementInfo { UIElementInfo(id: id, frame: f, title: "", role: "") }
        let labels = [3: el(3, CGRect(x: 10, y: 10, width: 5, height: 5)),
                      7: el(7, CGRect(x: -5, y: 10, width: 20, height: 5)),
                      9: el(9, CGRect(x: 500, y: 500, width: 5, height: 5))]
        let out = OverlayMath.drawnLabels(labels, screens: screens)
        #expect(Set(out.keys) == [3, 7])
        #expect(out[7]?.id == 7)
    }
}
