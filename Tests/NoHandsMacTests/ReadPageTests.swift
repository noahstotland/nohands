import Testing
import CoreGraphics
import Foundation
import NoHandsCore
@testable import NoHandsMac

@MainActor @Test func readPageKeepsOneLongPageReadingAndLeavesOtherReadingsShort() async {
    let (x, i, e, _) = make()
    e.pageRuns = ["Header", "", "Header", String(repeating: "t", count: 2000), "Watch"]
    #expect(await x.execute([.readPage]) == nil)
    let long = x.takeReadings()
    #expect(long == ["page: Header | " + String(repeating: "t", count: 2000) + " | Watch"])
    #expect(x.takeReadings().isEmpty && i.calls.isEmpty)
    // A reading from anywhere else keeps the 300-character cap, whatever its text says.
    // Nor can an element title spelling the page label (read_value uses the title as the label).
    for label in ["clipboard", "page", "Page", "page: x"] {
        x.addReading(label, "page: " + String(repeating: "c", count: 2000))
        let r = x.takeReadings().first ?? ""
        #expect(r.count == ActionExecutor.readingLimit && !r.hasPrefix("page: "))
    }
    // A page too long for one reading is cut at the page limit.
    e.pageRuns = (0..<400).map { "run number \($0) of the schedule" }
    #expect(await x.execute([.readPage]) == nil)
    let cut = x.takeReadings().first ?? ""
    #expect(cut.hasPrefix("page: run number 0") && cut.hasSuffix(" …") && cut.count <= PageText.limit)
}

@MainActor @Test func readPageFailsOnAnEmptyPageAndOnAStop() async {
    let (x, _, e, _) = make()
    e.pageRuns = ["", "   "]
    #expect(await x.execute([.readPage]) == "no text on this page")
    #expect(x.takeReadings().isEmpty)
    // A spoken stop during the walk: nothing is kept.
    e.pageRuns = ["Raptors vs Celtics"]
    e.onPageText = { withUnsafeCurrentTask { $0?.cancel() } }
    let result = await Task { @MainActor in await x.execute([.readPage]) }.value
    #expect(result == ActionExecutor.cancelled && x.takeReadings().isEmpty)
}

@Test func theObservationCarriesNearOnlyWhereTheWalkSetIt() async {
    let f = FakeElements(); f.front = "Chrome"
    f.elements = [
        UIElementInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 80, height: 30), title: "Watch", role: "AXLink", near: "Raptors vs Celtics"),
        UIElementInfo(id: 2, frame: CGRect(x: 0, y: 40, width: 80, height: 30), title: "Home", role: "AXLink"),
    ]
    let r = await ScreenObserver(ax: f, maxElements: 10).observe(mode: .command, overlay: .none, harnessKind: .native)
    #expect(r.observation.elements.map(\.near) == ["Raptors vs Celtics", nil])
}
