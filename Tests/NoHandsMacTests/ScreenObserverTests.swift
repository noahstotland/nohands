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

    @Test func shownLabelsAreObservedWithTheirBadgeNumbers() {
        let f = FakeElements()
        f.elements = [UIElementInfo(id: 0, frame: CGRect(x: 0, y: 0, width: 50, height: 50), title: "Other", role: "AXButton")]
        let badges = [
            4: UIElementInfo(id: 4, frame: CGRect(x: 0, y: 0, width: 50, height: 50), title: "Save", role: "AXButton"),
            11: UIElementInfo(id: 11, frame: CGRect(x: 100, y: 0, width: 50, height: 50), title: "Home", role: "AXLink"),
            12: UIElementInfo(id: 12, frame: CGRect(x: 200, y: 0, width: 50, height: 50), title: "", role: "AXButton"),
        ]
        let (obs, labels) = ScreenObserver(ax: f, maxElements: 10).observe(mode: .command, overlay: .labels(badges))
        #expect(obs.overlay == "labels")
        #expect(obs.elements.map(\.number) == [4, 11])
        #expect(obs.elements.map(\.title) == ["Save", "Home"])
        #expect(labels == [4: badges[4]!, 11: badges[11]!])
        #expect(f.walks == 0)                                   // no fresh walk with different numbering
    }

    @Test func taskLoopNumbersTheMenuBarAfterThePageAndOneShotDoesNot() async {
        let f = FakeElements()
        func at(_ y: Int) -> CGRect { CGRect(x: 0, y: y, width: 50, height: 20) }
        f.elements = [UIElementInfo(id: 0, frame: at(0), title: "Edit", role: "AXMenuBarItem"),
                      UIElementInfo(id: 0, frame: at(100), title: "Videos", role: "AXLink")]
        let o = ScreenObserver(ax: f, maxElements: 1)
        let task = await o.observe(mode: .command, overlay: .none, harnessKind: .native).observation
        #expect(task.elements.map(\.title) == ["Videos"])      // the cap now cuts the menu bar
        #expect(task.menuBarTitles == ["Edit"])                 // but its titles are still known
        #expect(o.observe(mode: .command, overlay: .none).observation.elements.map(\.title) == ["Edit"])
    }

    // MARK: harness

    private func harnessSnapshot() -> DesktopSnapshot {
        DesktopSnapshot(app: "Notes", snapshotID: "s1", windowID: "w-1", windowTitle: "Notes", complete: true, elements: [
            UIElementInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 10, height: 10), title: "Save", role: "button", ref: "@s1:e1"),
            UIElementInfo(id: 2, frame: .zero, title: "", role: "group", ref: "@s1:e2"),
            UIElementInfo(id: 3, frame: .zero, title: "", role: "textfield", ref: "@s1:e3", value: "cats"),
            UIElementInfo(id: 4, frame: .zero, title: "More", role: "button", ref: "@s1:e4", states: ["disabled"]),
        ])
    }

    @Test func observerUsesHarnessElementsAndKeepsRefs() async {
        let f = FakeElements(); f.front = "Notes"; f.windowTitle = "Notes"
        f.elements = [UIElementInfo(id: 0, frame: CGRect(x: 0, y: 0, width: 5, height: 5), title: "Native", role: "AXButton")]
        let h = FakeHarness(); h.snapshotResults = [harnessSnapshot()]
        let (obs, labels, fromHarness) = await ScreenObserver(ax: f, maxElements: 2, harness: h, snapshotTimeoutMs: 2500)
            .observe(mode: .command, overlay: .none, harnessKind: .agentDesktop, readings: ["clipboard: hi"])
        #expect(fromHarness)
        #expect(obs.harness == .agentDesktop && obs.app == "Notes" && obs.windowTitle == "Notes")
        #expect(obs.elements.map(\.number) == [1, 2] && obs.elements.map(\.title) == ["Save", ""])   // unnamed group skipped, cap 2
        #expect(obs.elements[1].role == "textfield" && obs.elements[1].value == "cats")
        #expect(labels[1]?.ref == "@s1:e1" && labels[2]?.ref == "@s1:e3" && labels.count == 2)
        #expect(obs.readings == ["clipboard: hi"] && obs.surface == nil)
        #expect(f.walks == 0 && h.calls == ["snapshot:Notes"])
    }

    @Test func observerFallsBackToNativeOnProcessFailure() async {
        let f = FakeElements(); f.front = "Notes"
        f.elements = [UIElementInfo(id: 0, frame: CGRect(x: 0, y: 0, width: 5, height: 5), title: "Native", role: "AXButton")]
        let h = FakeHarness(); h.snapshotResults = [nil]
        let o = ScreenObserver(ax: f, maxElements: 10, harness: h)
        let (obs, labels, fromHarness) = await o.observe(mode: .command, overlay: .none, harnessKind: .agentDesktop)
        #expect(obs.harness == .agentDesktop && obs.elements.map(\.title) == ["Native"] && labels[1]?.ref == nil && !fromHarness)
        #expect(f.walks == 1)
        #expect(await o.probe() == false)
        h.snapshotResults = [harnessSnapshot()]
        #expect(await o.probe() == true)
    }

    @Test func observerSnapshotsOpenSurfaceInsteadOfWindow() async {
        let f = FakeElements(); f.front = "TextEdit"
        let h = FakeHarness(); h.snapshotResults = [harnessSnapshot()]; h.surfacesToReport = ["sheet"]
        let (obs, _, _) = await ScreenObserver(ax: f, maxElements: 10, harness: h).observe(mode: .command, overlay: .none, harnessKind: .agentDesktop)
        #expect(h.calls == ["snapshot:sheet"] && obs.surface == "sheet" && obs.elements.count == 3)
        // A surface agent-desktop cannot snapshot (not a sheet/menu/alert/popover) is ignored.
        let h2 = FakeHarness(); h2.snapshotResults = [harnessSnapshot()]; h2.surfacesToReport = ["toolbar"]
        let (obs2, _, _) = await ScreenObserver(ax: f, maxElements: 10, harness: h2).observe(mode: .command, overlay: .none, harnessKind: .agentDesktop)
        #expect(h2.calls == ["snapshot:TextEdit"] && obs2.surface == nil)
    }

    @Test func badgesOverlayAndNativeKindSkipTheHarness() async {
        let f = FakeElements(); f.front = "Notes"
        f.elements = [UIElementInfo(id: 0, frame: CGRect(x: 0, y: 0, width: 5, height: 5), title: "Native", role: "AXButton")]
        let h = FakeHarness(); h.snapshotResults = [harnessSnapshot()]
        let badges = [4: UIElementInfo(id: 4, frame: CGRect(x: 0, y: 0, width: 50, height: 50), title: "Save", role: "AXButton")]
        let o = ScreenObserver(ax: f, maxElements: 10, harness: h)
        let (obs, _, fromHarness) = await o.observe(mode: .command, overlay: .labels(badges), harnessKind: .agentDesktop)
        #expect(obs.elements.map(\.number) == [4] && h.calls.isEmpty && obs.harness == .agentDesktop && !fromHarness)
        let (native, _, _) = await o.observe(mode: .command, overlay: .none, harnessKind: .native)
        #expect(native.harness == .native && native.elements.map(\.title) == ["Native"] && h.calls.isEmpty)
    }
}

@Test func taskObservationReportsMediaFromEveryElementAndAsksAudioOnlyWithoutAControl() async {
    let f = FakeElements(), audio = FakeAudio()
    f.front = "Safari"
    func media(_ titles: [String], maxElements: Int = 1) async -> MediaState? {
        f.elements = titles.enumerated().map { UIElementInfo(id: $0.offset, frame: CGRect(x: 0, y: $0.offset * 40, width: 10, height: 10), title: $0.element, role: "AXButton") }
        return await ScreenObserver(ax: f, maxElements: maxElements, audio: audio)
            .observe(mode: .command, overlay: .none, harnessKind: .native).observation.media
    }
    // The Pause control is past the element cap and still counts.
    #expect(await media(["Reload", "Pause (k)"]) == .playing && audio.asked == 0)
    #expect(await media(["Reload", "Play"]) == .paused && audio.asked == 0)
    #expect(await media(["Reload"]) == MediaState.none && audio.asked == 1)
    audio.playing = true
    #expect(await media(["Reload"]) == .playing)
    #expect(ScreenObserver(ax: f, maxElements: 1, audio: audio).observe(mode: .command, overlay: .none).observation.media == nil)
}
