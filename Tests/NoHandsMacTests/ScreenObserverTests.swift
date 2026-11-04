import Testing
import CoreGraphics
import NoHandsCore
@testable import NoHandsMac

@Suite struct ScreenObserverTests {
    @Test func observesTitledElementsWithRolesWindowAndURL() {
        let f = FakeElements()
        f.front = "Google Chrome"; f.windowTitle = "Videos"; f.url = "https://example.com/v"
        func r(_ i: Int) -> CGRect { CGRect(x: i * 100, y: 0, width: 50, height: 50) }
        f.elements = [
            UIElementInfo(id: 0, frame: r(0), title: "Save", role: "AXButton"),
            UIElementInfo(id: 1, frame: r(1), title: "  ", role: "AXButton"),
            UIElementInfo(id: 2, frame: r(2), title: "Video A", role: "AXLink"),
            UIElementInfo(id: 3, frame: r(3), title: "Video B", role: "AXLink"),
        ]
        let (obs, labels) = ScreenObserver(ax: f, maxElements: 2).observe(mode: .command, overlay: .none)
        #expect(obs.app == "Google Chrome" && obs.windowTitle == "Videos" && obs.url == "https://example.com/v")
        #expect(obs.overlay == "none")
        #expect(obs.elements.map(\.title) == ["Save", "Video A"])
        #expect(obs.elements.map(\.role) == ["button", "link"])
        #expect(Set(labels.keys) == Set(obs.elements.map(\.number)))
    }
}
