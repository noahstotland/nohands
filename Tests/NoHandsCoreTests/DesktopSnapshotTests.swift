import Testing
import Foundation
import CoreGraphics
@testable import NoHandsCore

func fixture(_ name: String) -> [String: Any] {
    let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!
    let root = try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    return root["data"] as! [String: Any]
}

@Test func parsesWindowSnapshotDepthFirstWithRefsValuesAndStates() {
    let s = DesktopSnapshot.parse(fixture("agent-desktop-window"))!
    #expect(s.app == "Claude" && s.snapshotID == "sydxanrtq4m1a" && s.windowID == "w-100" && s.windowTitle == "Claude" && s.complete)
    #expect(s.elements.count == 5 && s.elements.map(\.id) == [1, 2, 3, 4, 5])
    let listed = s.elements.filter(DesktopSnapshot.listable)
    #expect(listed.map(\.title) == ["Hide sidebar", "New chat", "", "Remember me"])   // textfield listed by role, unnamed group dropped
    #expect(listed[2].role == "textfield" && listed[2].value == "cats")
    #expect(listed[3].states == ["checked"] && listed[3].value == "1" && listed[0].ref == "@sydxanrtq4m1a:e2")
    #expect(listed[0].frame == CGRect(x: 84, y: 40, width: 28, height: 28))
}

@Test func elementsWithoutBoundsGetZeroFrame() {
    let s = DesktopSnapshot.parse(fixture("agent-desktop-finder-menubar"))!
    #expect(!s.complete && s.elements.count == 294)
    #expect(s.elements.allSatisfy { $0.frame == .zero } && s.elements[1].title == "About This Mac")
    #expect(s.windowID == "w-11305")
}

@Test func parseRejectsEnvelopesWithoutATree() {
    #expect(DesktopSnapshot.parse(["app": "X"]) == nil)
}

@Test func findMatchParses() {
    let data: [String: Any] = ["match": ["ref_id": "@s1:e1", "role": "menuitem", "name": "New Folder", "path": ["menu", "menuitem:File"], "states": ["disabled"]], "snapshot_id": "s1"]
    let m = DesktopFindMatch.parse(data)!
    #expect(m.ref == "@s1:e1" && m.disabled && m.path == ["menu", "menuitem:File"] && m.name == "New Folder" && m.role == "menuitem")
    #expect(DesktopFindMatch.parse(["match": NSNull(), "snapshot_id": "s1"]) == nil)
}

@Test func uiElementInfoKeepsItsOldInitializer() {
    let e = UIElementInfo(id: 1, frame: .zero, title: "t", role: "AXButton")
    #expect(e.ref == nil && e.value == nil && e.states.isEmpty)
}
