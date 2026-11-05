import Testing
import Foundation
import NoHandsCore
@testable import NoHandsMac

private let bin = URL(fileURLWithPath: "/opt/homebrew/bin/agent-desktop")

@Test func harnessStatusTextAndChoice() {
    let ok = HarnessStatus(choice: .auto, binary: bin, version: "1.1.0", accessibility: "granted")
    #expect(ok.chosen == .agentDesktop && ok.text == "Harness: agent-desktop 1.1.0")
    let missing = HarnessStatus(choice: .auto, binary: nil, version: nil, accessibility: nil)
    #expect(missing.chosen == .native && missing.text == "Harness: native (agent-desktop not found — npm i -g agent-desktop)")
    let denied = HarnessStatus(choice: .auto, binary: bin, version: "1.1.0", accessibility: "denied")
    #expect(denied.chosen == .native && denied.text == "Harness: native (agent-desktop: accessibility not granted)")
    let silent = HarnessStatus(choice: .auto, binary: bin, version: nil, accessibility: nil)
    #expect(silent.chosen == .native && silent.text == "Harness: native (agent-desktop not responding)")
    let off = HarnessStatus(choice: .native, binary: bin, version: "1.1.0", accessibility: "granted")
    #expect(off.chosen == .native && off.text == "Harness: native (desktopHarness = native)")
    // An explicit choice trusts the binary over the permission report (it may read "unknown").
    let forced = HarnessStatus(choice: .agentDesktop, binary: bin, version: "1.1.0", accessibility: "unknown")
    #expect(forced.chosen == .agentDesktop && forced.text == "Harness: agent-desktop 1.1.0")
    #expect(HarnessStatus(choice: .agentDesktop, binary: nil, version: nil, accessibility: nil).chosen == .native)
}

@Test func harnessStatusProbeReadsVersionAndPermissions() async {
    let c = ScriptedClient()
    c.responses["version"] = [okEnvelope("version", data: #"{"os":"macos","target":"aarch64","version":"1.1.0"}"#)]
    c.responses["status"] = [okEnvelope("status", data: #"{"permissions":{"accessibility":{"state":"granted"}},"platform":"macos"}"#)]
    var config = AppConfig()
    config.agentDesktopPath = bin.path
    let s = await HarnessStatus.probe(config: config, binary: bin, client: c)
    #expect(s.version == "1.1.0" && s.accessibility == "granted" && s.chosen == .agentDesktop && s.binary == bin)
    let none = await HarnessStatus.probe(config: config, binary: .some(nil), client: c)
    #expect(none.chosen == .native && none.version == nil)
}
