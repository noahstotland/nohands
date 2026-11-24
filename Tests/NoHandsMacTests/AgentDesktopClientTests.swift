import Testing
import Foundation
import NoHandsCore
@testable import NoHandsMac

private func tempDir() -> URL {
    let d = FileManager.default.temporaryDirectory.appendingPathComponent("nohands-" + UUID().uuidString)
    try! FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
}

/// A shell script standing in for the agent-desktop binary.
private func script(_ body: String) -> URL {
    let url = tempDir().appendingPathComponent("agent-desktop")
    FileManager.default.createFile(atPath: url.path, contents: Data(("#!/bin/sh\n" + body + "\n").utf8),
                                   attributes: [.posixPermissions: 0o755])
    return url
}

@Test func locatorOrderAndNvmNewestFirst() throws {
    let home = tempDir()
    for v in ["v18.18.2", "v22.1.0"] {
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".nvm/versions/node/\(v)/bin"), withIntermediateDirectories: true)
    }
    let bin = home.appendingPathComponent(".nvm/versions/node/v22.1.0/bin/agent-desktop")
    FileManager.default.createFile(atPath: bin.path, contents: Data(), attributes: [.posixPermissions: 0o755])
    #expect(AgentDesktopLocator.find(configPath: nil, environment: [:], home: home) == bin)
    let c = AgentDesktopLocator.candidates(configPath: "/x/agent-desktop", environment: ["AGENT_DESKTOP_BIN": "/y/agent-desktop", "PATH": "/p:/q"], home: home).map(\.path)
    #expect(Array(c.prefix(4)) == ["/x/agent-desktop", "/y/agent-desktop", "/opt/homebrew/bin/agent-desktop", "/usr/local/bin/agent-desktop"])
    #expect(c.suffix(2) == ["/p/agent-desktop", "/q/agent-desktop"])
    let new = c.firstIndex(of: home.appendingPathComponent(".nvm/versions/node/v22.1.0/bin/agent-desktop").path)!
    let old = c.firstIndex(of: home.appendingPathComponent(".nvm/versions/node/v18.18.2/bin/agent-desktop").path)!
    #expect(new < old)
    for dir in [".bun/bin", ".volta/bin", ".npm-global/bin", ".local/bin"] {
        #expect(c.contains(home.appendingPathComponent(dir + "/agent-desktop").path), "\(dir)")
    }
}

@Test func locatorSkipsNonExecutableAndMissingFiles() throws {
    let home = tempDir()
    let plain = home.appendingPathComponent(".local/bin/agent-desktop")
    try FileManager.default.createDirectory(at: plain.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: plain.path, contents: Data(), attributes: [.posixPermissions: 0o644])
    #expect(AgentDesktopLocator.find(configPath: "/nonexistent/agent-desktop", environment: ["PATH": ""], home: home) == nil)
}

@Test func runDecodesStdoutAndPassesArgs() async {
    let c = AgentDesktopClient(binary: script(#"printf '{"version":"2.6","ok":true,"command":"type","data":{"echo":"%s"}}' "$3""#), defaultDeadline: .seconds(2))
    let e = await c.run(["type", "@s1:e1", "hello"], isObservation: false)
    #expect(e.ok && (e.data?["echo"] as? String) == "hello")
}

@Test func runReturnsStructuredErrorsDespiteExitStatusOne() async {
    let c = AgentDesktopClient(binary: script(#"printf '{"version":"2.6","ok":false,"command":"click","error":{"code":"STALE_REF","message":"gone","disposition":{"delivery":"not_delivered","retry":"safe"}}}'; exit 1"#), defaultDeadline: .seconds(2))
    let e = await c.run(["click", "@s1:e1"], isObservation: false)
    #expect(!e.ok && e.error?.code == "STALE_REF" && e.error?.notDelivered == true)
}

@Test func runKillsAtDeadline() async {
    let c = AgentDesktopClient(binary: script("sleep 5"), defaultDeadline: .milliseconds(200))
    let t = ContinuousClock.now
    let e = await c.run(["snapshot"], isObservation: true)
    #expect(e.error?.code == "TIMEOUT" && e.error?.notDelivered == true && t.duration(to: .now) < .seconds(2))
    let action = await c.run(["click", "@s1:e1"], deadline: .milliseconds(100), isObservation: false)
    #expect(action.error?.code == "TIMEOUT" && action.error?.notDelivered == false)
}

@Test func runReportsProcessFailureAndMalformedOutput() async {
    let bad = AgentDesktopClient(binary: script("echo nope; exit 1"), defaultDeadline: .seconds(10))
    #expect(await bad.run(["status"], isObservation: true).error?.code == "PROCESS_FAILED")
    let missing = AgentDesktopClient(binary: URL(fileURLWithPath: "/nonexistent/agent-desktop"), defaultDeadline: .seconds(10))
    #expect(await missing.run(["status"], isObservation: true).error?.code == "PROCESS_FAILED")
}

@Test func runIsCancellable() async {
    let c = AgentDesktopClient(binary: script("sleep 5"), defaultDeadline: .seconds(10))
    let task = Task { await c.run(["click", "@s1:e1"], isObservation: false) }
    try? await Task.sleep(for: .milliseconds(100))
    task.cancel()
    let t = ContinuousClock.now
    let e = await task.value
    #expect(e.error?.code == "CANCELLED" && t.duration(to: .now) < .seconds(2))
}

@Test func runReturnsWhenTheChildExitsEvenIfAGrandchildHoldsStdout() async {
    // The grandchild outlives the test on purpose: it must hold stdout well past the 8 s bound.
    let c = AgentDesktopClient(binary: script(#"(sleep 20 &); printf '{"version":"2.6","ok":true,"command":"status","data":{}}'"#), defaultDeadline: .seconds(10))
    let t = ContinuousClock.now
    let e = await c.run(["status"], isObservation: true)
    #expect(e.ok && t.duration(to: .now) < .seconds(8))
}

@Test func cancellationRacingTheLaunchNeverTerminatesAnUnlaunchedProcess() async {
    // Cancelling in the window between creating and launching the child used to raise an uncaught
    // NSInvalidArgumentException (terminate() on a Process that never ran). Hammer the window.
    let c = AgentDesktopClient(binary: script("sleep 1"), defaultDeadline: .seconds(5))
    for i in 0..<40 {
        let task = Task { await c.run(["click", "@s1:e1"], isObservation: false) }
        if i % 2 == 0 { await Task.yield() }
        task.cancel()
        let e = await task.value
        #expect(e.error?.code == "CANCELLED" || e.error?.code == "PROCESS_FAILED")
    }
}

@Test func runPassesEnvironmentToTheChild() async {
    let c = AgentDesktopClient(binary: script(#"printf '{"version":"2.6","ok":true,"command":"status","data":{"session":"%s"}}' "$AGENT_DESKTOP_SESSION""#), defaultDeadline: .seconds(2))
    let e = await c.run(["status"], isObservation: true, environment: ["AGENT_DESKTOP_SESSION": "abc"])
    #expect((e.data?["session"] as? String) == "abc")
}
