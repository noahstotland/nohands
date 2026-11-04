import Testing
import CoreGraphics
@testable import NoHandsCore

@Suite struct TitleSourceTests {
    @Test func valueFallback() {
        #expect(!TitleSource.allowsValueFallback(role: "AXTextField", subrole: "AXSecureTextField"))
        #expect(!TitleSource.allowsValueFallback(role: "AXTextField", subrole: nil))
        #expect(!TitleSource.allowsValueFallback(role: "AXTextArea", subrole: nil))
        #expect(!TitleSource.allowsValueFallback(role: "AXComboBox", subrole: nil))
        for role in ["AXPopUpButton", "AXCheckBox", "AXRadioButton", "AXSlider", "AXMenuItem", "AXTab"] {
            #expect(TitleSource.allowsValueFallback(role: role, subrole: nil))
        }
        for role in ["AXButton", "AXCell", "AXRow", "AXStaticText", "AXLink"] {
            #expect(!TitleSource.allowsValueFallback(role: role, subrole: nil))
        }
    }

    @Test func appMatching() {
        let c = [(name: "Safari Technology Preview", id: 1), (name: "Safari", id: 2), (name: "Visual Studio Code", id: 3)]
        #expect(AppNameMatcher.best(for: "safari", in: c) == 2)
        #expect(AppNameMatcher.best(for: "safari tech", in: c) == 1)
        #expect(AppNameMatcher.best(for: "code", in: c) == 3)
        #expect(AppNameMatcher.best(for: "nothing", in: c) == nil)
    }

    @Test func installedAppMatchingHasNoContains() {
        let c = [(name: "Visual Studio Code", id: 3), (name: "Safari", id: 2)]
        #expect(AppNameMatcher.best(for: "code", in: c, allowContains: false) == nil)
        #expect(AppNameMatcher.best(for: "visual", in: c, allowContains: false) == 3)
        #expect(AppNameMatcher.best(for: "SAFARI", in: c, allowContains: false) == 2)
    }

    @Test func clickPointClipsToScreen() {
        let e = UIElementInfo(id: 0, frame: CGRect(x: 900, y: 100, width: 400, height: 40), title: "", role: "AXButton")
        let p = e.clickPoint(screens: [CGRect(x: 0, y: 0, width: 1000, height: 800)])
        #expect(p == CGPoint(x: 950, y: 120))
    }
}
