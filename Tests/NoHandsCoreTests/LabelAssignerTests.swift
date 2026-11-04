import Testing
import CoreGraphics
@testable import NoHandsCore

@Test func labelsOrderedTopToBottomLeftToRight() {
    let a = UIElementInfo(id: 1, frame: CGRect(x: 300, y: 10, width: 50, height: 20), title: "Save", role: "AXButton")
    let b = UIElementInfo(id: 2, frame: CGRect(x: 10, y: 14, width: 50, height: 20), title: "Cancel", role: "AXButton")
    let c = UIElementInfo(id: 3, frame: CGRect(x: 10, y: 200, width: 50, height: 20), title: "Help", role: "AXLink")
    let dup = UIElementInfo(id: 4, frame: a.frame, title: "Save", role: "AXButton")
    let labels = LabelAssigner.assign([a, c, b, dup])
    #expect(labels.count == 3)
    #expect(labels[1] == b); #expect(labels[2] == a); #expect(labels[3] == c)
    #expect(LabelAssigner.assign([a, b, c], limit: 2).count == 2)
}

@Test func findByNamePrefersExact() {
    let els = [UIElementInfo(id: 1, frame: .zero, title: "Save As…", role: "AXButton"),
               UIElementInfo(id: 2, frame: .zero, title: "Save", role: "AXButton"),
               UIElementInfo(id: 3, frame: .zero, title: "Don't Save", role: "AXButton")]
    #expect(LabelAssigner.find(named: "save", in: els)?.id == 2)
    #expect(LabelAssigner.find(named: "save as", in: els)?.id == 1)
    #expect(LabelAssigner.find(named: "don't", in: els)?.id == 3)
    #expect(LabelAssigner.find(named: "quit", in: els) == nil)
    #expect(LabelAssigner.find(named: "  ", in: els) == nil)
}
