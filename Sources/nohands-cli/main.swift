import Foundation
import AppKit
import CoreGraphics
import NoHandsCore
import NoHandsMac

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func usage() -> Never {
    fail("""
    usage:
      nohands-cli type "<text>"      (waits 2 s, then types)
      nohands-cli key "<chord>"      e.g. "command shift s"
      nohands-cli click-at <x> <y>
      nohands-cli move <x> <y>
      nohands-cli transcribe <wav>
      nohands-cli vad-test <wav>
      nohands-cli endpoint-test <wav>...  (replays each file through the VAD, early close and ASR; prints how soon the
                                      early text is ready after the true end of speech)
      nohands-cli bench <dir>        (replays each .wav in the folder through the VAD, early close and ASR, parses the text,
                                      and prints per-file latency plus p50 and p95 per stage; executes nothing)
      nohands-cli elements           (waits 3 s, lists frontmost app's actionable elements)
      nohands-cli click "<name>"     (waits 3 s, clicks the named element's center)
      nohands-cli grid               (10x8 grid 4 s, zoom into cell 35 for 4 s, HUD "done")
      nohands-cli labels             (waits 3 s, badges for frontmost app's elements for 5 s)
      nohands-cli observe            (waits 3 s, prints the task-loop observation of the frontmost app)
      nohands-cli parse "<text>" [--app <bundle id>]
                                     (dry run: prints the grammar's actions, or "no match -> LLM"; executes nothing;
                                      --app parses with that app in front, so its pack, built in or installed, applies)
      nohands-cli pack add <file>    (checks the pack file, shows what it does, and installs it only if you answer y)
      nohands-cli pack list          (installed packs: id, version, on or off, phrases, notes)
      nohands-cli pack remove <id>   (removes an installed pack)
      nohands-cli pack builtin <id>  (prints a built-in pack as a pack file, as a template)
      nohands-cli pack new [--app <name or bundle id>] [--out <file>]
                                     (reads the app's top-level menu items, waits 3 s without --app to read the app in
                                      front, and writes a draft pack file, listing what it left out; never overwrites a
                                      file or installs: edit it, then pack add)
      nohands-cli pack search [words]  (fetches the pack registry's signed list and shows the packs that match; the
                                      network is used only when you run this, install or update)
      nohands-cli pack install <id>  (fetches that pack from the registry, shows what it does, installs only if you answer y)
      nohands-cli pack update [<id>] (for each installed pack with a newer registry version, shows what changed and
                                      updates it only if you answer y)
      nohands-cli registry keygen <path>  (publishers: makes a signing key file, mode 600; prints the public key)
      nohands-cli registry sign <index.json> --key <path> [--packs <dir>]
                                     (publishers: checks the index, and the pack files in <dir>, and prints the signed file)
      nohands-cli menu "<words>"     (waits 2 s, then prints the frontmost app's menu item those words name and presses it)
      nohands-cli menu --list        (waits 3 s, prints the frontmost app's menu items, without the Apple menu)
      nohands-cli run "<phrase>"...  (waits 2 s, executes each phrase in order, 0.8 s apart)
      nohands-cli resolve "<text>"   (waits 3 s, sends text + frontmost app's labels to the configured backend;
                                      prints the step's intent, status and actions; executes nothing)
      nohands-cli task "<goal>"      (waits 3 s, then runs the goal as a multi-step task on the frontmost app,
                                      printing each step and the outcome; Ctrl-C stops it)
      nohands-cli scenarios [file] [--only name]  (waits 3 s, then runs each scripted task goal for real and scores it
                                      against a fresh screen check; takes over the screen; exits 0 only when all pass;
                                      default file scripts/task-scenarios.json; Ctrl-C stops the suite)
      nohands-cli eval <file> [--runs N]  (scores the configured backend on a fixture set; executes nothing)
      nohands-cli listen             (mic -> VAD -> ASR; Ctrl-C to quit)
      nohands-cli claude-check       (sends one small request to Claude with your key and prints whether commands will
                                      work; exits 0 only when connected; spends about one step's input tokens)
      nohands-cli desktop-status     (agent-desktop binary, version, permissions and the harness in use)
      nohands-cli snapshot [app]     (waits 3 s, prints the task-loop observation through agent-desktop of the
                                      frontmost app, or of the named app)
    """)
}

/// The desktop harness the configured status picks (agent-desktop when installed and permitted), printed once.
func loadHarness(_ config: AppConfig, quiet: Bool = false) async -> (any DesktopHarness)? {
    let status = await HarnessStatus.probe(config: config)
    if !quiet { print(status.text) }
    return status.makeHarness(config: config)
}

func loadConfig() throws -> AppConfig {
    let cfgURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/nohands/config.json")
    return try AppConfig.load(from: try? Data(contentsOf: cfgURL), environment: ProcessInfo.processInfo.environment)
}

func point(_ args: [String]) -> CGPoint {
    guard args.count == 2, let x = Double(args[0]), let y = Double(args[1]), x.isFinite, y.isFinite else { usage() }
    return CGPoint(x: x, y: y)
}

setvbuf(stdout, nil, _IOLBF, 0)   // line-buffered even when piped, so `task` step lines appear as they happen
let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { usage() }
let rest = Array(args.dropFirst())
let synth = CGEventInputSynthesizer()
/// The process exit status once `runCommand()` returns (`task` sets 2 when it does not finish done).
var exitStatus: Int32 = 0

/// Ctrl-C state shared with the SIGINT handler (main queue only).
@MainActor final class InterruptState { var policy = InterruptPolicy() }

/// Every command runs on the main actor inside a top-level (non-nested) `NSApplication` run loop, so overlay
/// windows draw and main-actor tasks run. (Calling `app.run()` from inside an async main-actor job never drains
/// the main queue: the body of an overlay command would never start.)
@MainActor func runCommand() async {
    do {
        switch command {
        case "type":
            guard rest.count == 1 else { usage() }
            try await Task.sleep(for: .seconds(2))
            try synth.type(rest[0])
        case "key":
            guard rest.count == 1 else { usage() }
            guard let actions = CommandGrammar().parse("press " + rest[0]) else {
                fail("could not parse key spec: \(rest[0])")
            }
            guard actions.count == 1, case .pressKey(let chord) = actions[0] else {
                fail("key spec did not parse as a key press: \(rest[0])")
            }
            try synth.press(chord)
        case "click-at":
            try synth.click(at: point(rest), button: .left, count: 1)
        case "move":
            try synth.moveMouse(to: point(rest))
        case "transcribe":
            // transcribe <wav> [version] [encoderUnits] [precision]
            guard rest.count >= 1, rest.count <= 4 else { usage() }
            let samples = try loadSamples16k(path: rest[0])
            let t0 = ContinuousClock.now
            let asr = try await ParakeetTranscriber(
                version: rest.count > 1 ? rest[1] : "v2",
                encoderUnits: rest.count > 2 ? (rest[2] == "default" ? nil : rest[2]) : "gpu",
                precision: rest.count > 3 ? rest[3] : nil)
            print("load=\(Int(t0.duration(to: .now) / .milliseconds(1)))ms")
            var times: [Int] = []
            var text = ""
            for _ in 1...max(1, Int(ProcessInfo.processInfo.environment["NH_RUNS"] ?? "") ?? 8) {
                let t = ContinuousClock.now
                text = try await asr.transcribe(samples)
                times.append(Int(t.duration(to: .now) / .milliseconds(1)))
            }
            print("last breakdown: \(await asr.lastBreakdown)")
            let warm = (times.count > 2 ? Array(times.dropFirst(2)) : times).sorted()
            print("runs=\(times) warm-median=\(warm[warm.count / 2])ms audio=\(samples.count * 1000 / 16000)ms text=\(text)")
        case "vad-test":
            // vad-test <wav> [silenceMs] [speechThreshold] [negativeThreshold]
            guard rest.count >= 1, rest.count <= 4 else { usage() }
            var samples = try loadSamples16k(path: rest[0])
            // True end of the last speech: last 20 ms window with RMS above 0.005.
            var trueEnd = 0
            var w = 0
            while w + 320 <= samples.count {
                var e: Float = 0
                for v in samples[w..<w + 320] { e += v * v }
                if (e / 320).squareRoot() > 0.005 { trueEnd = w + 320 }
                w += 320
            }
            samples += [Float](repeating: 0, count: 24_000)   // trailing silence so speechEnd can fire
            let vad = try await VoiceActivity(
                silenceMs: rest.count > 1 ? Int(rest[1]) ?? 1000 : 1000,
                speechThreshold: rest.count > 2 ? Float(rest[2]) ?? 0.85 : 0.85,
                negativeThreshold: rest.count > 3 ? Float(rest[3]) : nil)
            var i = 0
            while i + 4096 <= samples.count {
                let ev = try await vad.process(Array(samples[i..<i + 4096]))
                if ev != .none {
                    let t = Double(i + 4096) / 16000
                    var line = String(format: "%.2fs %@", t, "\(ev)")
                    if ev == .speechEnd { line += String(format: "  lag=%.0fms (true speech end %.2fs)", (t - Double(trueEnd) / 16000) * 1000, Double(trueEnd) / 16000) }
                    print(line)
                }
                i += 4096
            }
        case "endpoint-test":
            // endpoint-test <wav>...  Default config silenceMs and earlySilenceMs. One line per file, then a summary.
            guard !rest.isEmpty else { usage() }
            let config = try loadConfig()
            let asr = try await ParakeetTranscriber(version: config.asrModelVersion)
            _ = try await asr.transcribe([Float](repeating: 0, count: 16_000))   // warm up
            print("silenceMs=\(config.silenceMs) earlySilenceMs=\(config.earlySilenceMs)")
            var fired = 0, accepted = 0, mismatched = 0, extra = 0
            var readyMs: [Double] = []
            for path in rest {
                let samples = try loadSamples16k(path: path)
                let r = try await EndpointReplay.run(samples: samples, config: config, transcriber: asr)
                if r.earlyFired > 0 { fired += 1 }
                if r.earlyAccepted { accepted += 1 }
                if r.earlyAccepted, r.sameAction == false { mismatched += 1 }
                if r.emitted.count > 1 { extra += 1 }
                if let ms = r.earlyReadyMs { readyMs.append(ms) }
                func q(_ s: String?) -> String { s.map { "\"\($0)\"" } ?? "none" }
                let same = r.sameAction.map { $0 ? "same" : "DIFFERENT" } ?? "n/a"
                let early = r.earlyAccepted ? String(format: "%.0fms", r.earlyReadyMs ?? 0) : "fallback"
                let full = r.fullReadyMs.map { String(format: "%.0fms", $0) } ?? "n/a"
                print("\((path as NSString).lastPathComponent): early=\(q(r.earlyText)) full=\(q(r.fullText)) fired=\(r.earlyFired) accepted=\(r.earlyAccepted) actions=\(same) trueEnd=\(String(format: "%.2f", r.trueEnd))s ready=\(early) fullReady=\(full) emits=\(r.emitted.count)")
            }
            let p50 = readyMs.sorted().isEmpty ? "n/a" : String(format: "%.0fms", readyMs.sorted()[readyMs.count / 2])
            print("summary: files=\(rest.count) fired=\(fired) accepted=\(accepted) fellBack=\(rest.count - accepted) wrongAction=\(mismatched) multipleEmits=\(extra) p50AcceptedReady=\(p50)")
        case "bench":
            // bench <dir>  Dry run: per-file latency from the true end of speech to the parsed actions. Executes nothing.
            guard rest.count == 1 else { usage() }
            let dir = rest[0]
            let readme = "record the phrases listed in Tests/Fixtures/audio/README.md, or run scripts/make-bench-audio.sh to generate a synthesized set"
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue else {
                fail("bench: \(dir) is not a directory; \(readme)")
            }
            let files = (try FileManager.default.contentsOfDirectory(atPath: dir))
                .filter { $0.lowercased().hasSuffix(".wav") }
                .sorted()
            guard !files.isEmpty else { fail("bench: no .wav files in \(dir); \(readme)") }

            var config = try loadConfig()
            config.attentionWord = ""   // recordings do not start with the attention word
            let t0 = ContinuousClock.now
            let asr = try await ParakeetTranscriber(version: config.asrModelVersion)
            for _ in 0..<2 { _ = try await asr.transcribe([Float](repeating: 0, count: 16_000)) }   // the first two runs are cold
            let loadMs = Int(t0.duration(to: .now) / .milliseconds(1))
            print("silenceMs=\(config.silenceMs) earlySilenceMs=\(config.earlySilenceMs) asr=\(config.asrModelVersion) attentionWord=ignored load=\(loadMs)ms")

            let grammar = CommandGrammar(config: config.grammarConfig)
            let width = files.map(\.count).max() ?? 0
            var lag: [Double] = [], asrTimes: [Double] = [], parseTimes: [Double] = [], total: [Double] = []
            var early = 0, full = 0, skipped = 0
            for file in files {
                let name = file.padding(toLength: width, withPad: " ", startingAt: 0)
                do {
                    let samples = try loadSamples16k(path: (dir as NSString).appendingPathComponent(file))
                    let r = try await EndpointReplay.run(samples: samples, config: config, transcriber: asr)
                    guard let closedBy = r.closedBy, let lagMs = r.speechEndLagMs, let asrMs = r.asrMs else {
                        print("\(name)  skipped: no utterance")
                        skipped += 1
                        continue
                    }
                    let text = r.actedText ?? ""
                    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        print("\(name)  skipped: empty transcript")
                        skipped += 1
                        continue
                    }
                    let p0 = ContinuousClock.now
                    let actions = grammar.parse(text)
                    let parseMs = Double(p0.duration(to: .now) / .nanoseconds(1)) / 1_000_000
                    let outcome: String
                    if config.attentionGate.isStop(text) {
                        outcome = "stop"   // the pipeline halts on a stop phrase before the grammar sees it
                    } else if let actions {
                        outcome = "\(actions)"
                    } else if let message = grammar.rejection(text) {
                        outcome = "rejected: \(message)"
                    } else {
                        outcome = "no match -> LLM"
                    }
                    let e2e = lagMs + asrMs + parseMs
                    lag.append(lagMs); asrTimes.append(asrMs); parseTimes.append(parseMs); total.append(e2e)
                    if closedBy == .early { early += 1 } else { full += 1 }
                    print("\(name)  close=\(closedBy == .early ? "early" : "full") lag=\(LatencyStats.format(lagMs)) asr=\(LatencyStats.format(asrMs)) parse=\(LatencyStats.format(parseMs)) e2e=\(LatencyStats.format(e2e)) utts=\(r.utterances) \"\(text)\" -> \(outcome)")
                } catch {
                    print("\(name)  skipped: \(error.localizedDescription)")
                    skipped += 1
                }
            }
            print("summary: files=\(files.count) measured=\(total.count) skipped=\(skipped) early=\(early) full=\(full)")
            print(LatencyStats.summaryLine(stage: "lag", values: lag))
            print(LatencyStats.summaryLine(stage: "asr", values: asrTimes))
            print(LatencyStats.summaryLine(stage: "parse", values: parseTimes))
            print(LatencyStats.summaryLine(stage: "end-to-end", values: total))
            if total.isEmpty { exitStatus = 1 }
        case "elements":
            let ax = try await frontElements()
            print("app: \(ax.app)")
            for n in ax.labels.keys.sorted() {
                let e = ax.labels[n]!
                print(String(format: "%3d  %@  (%.0f,%.0f %.0fx%.0f)  %@", n, e.role, e.frame.minX, e.frame.minY, e.frame.width, e.frame.height, sanitized(e.title)))
            }
        case "click":
            guard rest.count == 1 else { usage() }
            let ax = try await frontElements()
            guard let hit = LabelAssigner.find(named: rest[0], in: ax.labels.keys.sorted().map { ax.labels[$0]! }) else {
                fail("no element named \"\(rest[0])\" in \(ax.app)")
            }
            try synth.click(at: hit.clickPoint(screens: AXQuery.screenRectsCG()), button: .left, count: 1)
        case "grid":
            await runOverlay { overlay in
                let bounds = OverlayController.screenBoundsCG(containing: CGPoint(x: 1, y: 1))
                let grid = GridModel(bounds: bounds)
                overlay.showGrid(grid)
                try? await Task.sleep(for: .seconds(4))
                if let z = grid.zoomed(into: 35) { overlay.showGrid(z) }
                try? await Task.sleep(for: .seconds(4))
                overlay.hide()
                overlay.showHUD("done", duration: .seconds(1.5))
                try? await Task.sleep(for: .seconds(1.8))
            }
        case "labels":
            let ax = try await frontElements()
            await runOverlay { overlay in
                overlay.showLabels(ax.labels)
                try? await Task.sleep(for: .seconds(5))
                overlay.hide()
            }
        case "observe":
            guard Permissions.accessibilityGranted(prompt: false) else {
                fail("Accessibility permission is not granted to this process (or its terminal). Enable it in System Settings > Privacy & Security > Accessibility, then rerun.")
            }
            let config = try loadConfig()
            let harness = await loadHarness(config)
            try await Task.sleep(for: .seconds(3))
            let query = AXQuery(budget: .milliseconds(1000), maxNodes: 6000)
            _ = query.actionableElements()   // exposes a Chromium page tree, which appears ~0.5 s later
            try await Task.sleep(for: .seconds(1))
            let observer = ScreenObserver(ax: query, maxElements: config.observedElementCap, harness: harness,
                                          snapshotTimeoutMs: config.agentDesktopSnapshotMs)
            let probed = harness != nil ? await observer.probe() : false
            let kind: HarnessKind = probed ? .agentDesktop : .native
            let (obs, _, _) = await observer.observe(mode: .command, overlay: .none, harnessKind: kind)
            print(ClaudeRequestBuilder.userMessage(request: StepRequest(goal: "-", step: 1, maxSteps: 12, history: [], observation: obs)))
        case "claude-check":
            guard rest.isEmpty else { usage() }
            let config = try loadConfig()
            let result = await ClaudeConnectionCheck(config: config).run()
            print(result.cliText(model: config.intentModel))
            exitStatus = result.kind == .connected ? 0 : 1
        case "desktop-status":
            let config = try loadConfig()
            let status = await HarnessStatus.probe(config: config)
            print("desktopHarness: \(config.desktopHarness.rawValue)")
            print("binary: \(status.binary?.path ?? "not found")")
            print("version: \(status.version ?? "-")")
            print("accessibility: \(status.accessibility ?? "-")")
            print(status.text)
        case "snapshot":
            guard rest.count <= 1 else { usage() }
            let config = try loadConfig()
            guard let harness = await loadHarness(config) else { fail("agent-desktop is not in use; see desktop-status") }
            if rest.isEmpty {
                print("bring the target app to the front; snapshot in 3 s...")
                try await Task.sleep(for: .seconds(3))
            }
            let app = rest.first ?? (AXQuery().frontmostAppName() ?? "")
            guard let snap = await harness.snapshot(app: app, surface: nil, timeoutMs: config.agentDesktopSnapshotMs) else {
                fail("agent-desktop could not snapshot \(app) (no window, off screen, or not permitted)")
            }
            let (obs, _) = ScreenObserver.list(snap, app: app, windowTitle: snap.windowTitle ?? "", url: nil, mode: .command,
                                               overlay: .none, limit: config.observedElementCap)
            var shown = obs
            shown.harness = .agentDesktop
            shown.media = MediaSignal.state(elements: snap.elements, audioPlaying: AudioOutputProbe().isPlaying)
            print("snapshot \(snap.snapshotID): \(snap.elements.count) refs, \(obs.elements.count) listed, complete=\(snap.complete)")
            print(ClaudeRequestBuilder.userMessage(request: StepRequest(goal: "-", step: 1, maxSteps: 12, history: [], observation: shown)))
        case "parse":
            guard rest.count == 1 || (rest.count == 3 && rest[1] == "--app") else { usage() }
            let bundleID: String? = rest.count == 3 ? rest[2] : nil
            let grammar = CommandGrammar(packs: PackSet(installed: (try? PackStore().loadEnabled()) ?? []))
            if let match = grammar.match(rest[0], frontmost: bundleID) {
                print("\(match.actions)\(match.confirm == nil ? "" : " (asks first)")")
            } else if let message = grammar.rejection(rest[0]) {
                print("rejected: \(message)")
            } else {
                print("no match -> LLM")
            }
        case "pack":
            await packCommand(rest)
        case "registry":
            registryCommand(rest)
        case "menu":
            guard rest.count == 1 else { usage() }
            guard Permissions.accessibilityGranted(prompt: false) else {
                fail("Accessibility permission is not granted to this process (or its terminal).")
            }
            let listing = rest[0] == "--list"
            try await Task.sleep(for: .seconds(listing ? 3 : 2))
            let reader = AXMenuReader()
            let entries = reader.entries()
            print("app: \(AXQuery().frontmostAppName() ?? ""), \(entries.count) menu items")
            if listing {
                for e in entries { print("\((e.path + [e.title]).joined(separator: " > "))\(e.enabled ? "" : "  (disabled)")") }
            } else {
                guard let i = MenuMatch.firstMatch(rest[0], in: entries) else { fail("no menu item called \(rest[0])") }
                let e = entries[i]
                print("match: \((e.path + [e.title]).joined(separator: " > "))\(e.enabled ? "" : "  (disabled)")")
                guard e.enabled else { fail("menu item \(e.title) is disabled") }
                print(reader.press(i) ? "pressed" : "the app ignored AXPress")
            }
        case "run":
            guard !rest.isEmpty else { usage() }
            guard Permissions.accessibilityGranted(prompt: false) else {
                fail("Accessibility permission is not granted to this process (or its terminal).")
            }
            var parsed: [[Action]] = []
            for phrase in rest {
                guard let match = CommandGrammar().match(phrase) else { fail("not a command: \(phrase)") }
                guard match.confirm == nil else { fail("asks first: not run from the CLI") }
                print("actions: \(match.actions)")
                parsed.append(match.actions)
            }
            let config = try loadConfig()
            let harness = await loadHarness(config)
            try await Task.sleep(for: .seconds(2))
            await runOverlay { overlay in
                let executor = ActionExecutor(input: synth, ax: AXQuery(), overlay: overlay, config: config, harness: harness)
                for (i, actions) in parsed.enumerated() {
                    if i > 0 { try? await Task.sleep(for: .milliseconds(800)) }
                    if let failure = await executor.execute(actions) { print("failed: \(failure)"); break }
                }
                try? await Task.sleep(for: .milliseconds(1800))   // let the HUD show
            }
        case "resolve":
            guard rest.count == 1 else { usage() }
            let (config, resolver, _) = try loadResolver()
            guard Permissions.accessibilityGranted(prompt: false) else {
                fail("Accessibility permission is not granted to this process (or its terminal).")
            }
            try await Task.sleep(for: .seconds(3))
            let context = IntentContextBuilder.make(elements: AXQuery(), mode: .command)
            let t0 = ContinuousClock.now
            do {
                let step = try await resolver.resolve(StepRequest(oneShot: rest[0], context: context,
                                                                  maxSteps: config.maxTaskSteps))
                print("intent: \(sanitized(step.intent))")
                print("status: \(step.status.rawValue)")
                print("actions: \(step.actions)")
                print("elapsed: \(Int(t0.duration(to: .now) / .milliseconds(1))) ms")
            } catch let e as IntentError {
                // Never print request details; IntentError carries no key material.
                fail("error: \(e)")
            }
        case "task":
            guard rest.count == 1, !rest[0].trimmingCharacters(in: .whitespaces).isEmpty else { usage() }
            let goal = rest[0]
            let (config, resolver, modelName) = try loadResolver()
            guard Permissions.accessibilityGranted(prompt: false) else {
                fail("Accessibility permission is not granted to this process (or its terminal). Enable it in System Settings > Privacy & Security > Accessibility, then rerun.")
            }
            print("task: \(sanitized(goal))  (model=\(modelName), max \(config.maxTaskSteps) steps, settle <= \(config.settleMs) ms)")
            let harness = await loadHarness(config)
            print("bring the target app to the front; starting in 3 s...")
            try await Task.sleep(for: .seconds(3))
            await runOverlay { overlay in
                let executor = ActionExecutor(input: synth, ax: AXQuery(), overlay: overlay, config: config, harness: harness)
                // Same observer as the app's task loop: a larger AX budget so web page content is reached.
                let observer = ScreenObserver(ax: AXQuery(budget: .milliseconds(1000), maxNodes: 6000),
                                              maxElements: config.observedElementCap, harness: harness,
                                              snapshotTimeoutMs: config.agentDesktopSnapshotMs)
                let runner = TaskRunner(config: config, resolver: resolver, executor: executor,
                                        observer: observer, overlay: overlay, harness: harness,
                                        screenshots: config.visionEnabled ? WindowScreenshotter(ax: AXQuery()) : nil)
                let t0 = ContinuousClock.now
                var last = t0
                runner.onStatus = { status in if status.isFinal { print("status: \(sanitized(status.text))") } }
                runner.onStep = { n, step, settle, failure in
                    let now = ContinuousClock.now
                    if n == 1 { print("harness: \(runner.harnessReport)") }
                    print("step \(n): \(sanitized(step.intent)) -> \(ActionSummary.kinds(step.actions)) (settle \(ms(settle)) ms, step \(ms(last.duration(to: now))) ms)")
                    print("        \(step.status.rawValue) \(step.actions)")
                    if let failure { print("        failed: \(failure)") }
                    last = now
                }
                // Ctrl-C stops the task like the spoken "stop" (so a held mouse button is released) instead of
                // killing it; a second Ctrl-C exits at once (status 130).
                signal(SIGINT, SIG_IGN)
                let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
                let ctrlC = InterruptState()
                interrupt.setEventHandler {
                    MainActor.assumeIsolated {
                        switch ctrlC.policy.interrupt() {
                        case .stopTask:
                            print("stopping... (Ctrl-C again to quit now)")
                            runner.cancel()
                        case .exitNow:
                            exit(InterruptPolicy.exitStatus)
                        }
                    }
                }
                interrupt.resume()
                defer { interrupt.cancel() }
                let outcome = await runner.run(goal: goal, mode: .command)
                print("outcome: \(outcome)  steps=\(runner.stepsRun) total=\(ms(t0.duration(to: .now))) ms")
                exitStatus = outcome.exitStatus
                try? await Task.sleep(for: .milliseconds(1800))   // let the outcome HUD show
            }
        case "scenarios":
            exitStatus = await runScenarios(rest)
        case "eval":
            guard let file = rest.first else { usage() }
            var runs = 1
            if rest.count == 3, rest[1] == "--runs", let n = Int(rest[2]), n >= 1 { runs = n }
            else if rest.count != 1 { usage() }
            let cases = try JSONDecoder().decode([EvalCase].self, from: try Data(contentsOf: URL(fileURLWithPath: file)))
            let (_, resolver, modelName) = try loadResolver()
            var passed = 0, total = 0
            var times: [Int] = []
            for c in cases {
                for _ in 1...runs {
                    let t0 = ContinuousClock.now
                    var got: [Action] = []
                    var status: StepStatus?
                    var errText: String?
                    do {
                        let step = try await resolver.resolve(StepRequest(oneShot: c.say, context: IntentEval.context(for: c)))
                        got = step.actions
                        status = step.status
                    } catch { errText = "\(error)" }
                    let ms = Int(t0.duration(to: .now) / .milliseconds(1))
                    times.append(ms)
                    total += 1
                    if errText == nil, let status, IntentEval.matches(got, status: status, anyOf: c.accept) {
                        passed += 1
                        print("PASS \(ms)ms  \(c.say)")
                    } else {
                        print("FAIL \(ms)ms  \(c.say)  got: \(errText.map { "error: \($0)" } ?? "\(status.map { "status=\($0.rawValue) " } ?? "")\(got)")")
                    }
                }
            }
            let warm = (times.count > 2 ? Array(times.dropFirst(2)) : times).sorted()
            print("accuracy=\(total == 0 ? 0 : passed * 100 / total)% median=\(warm.isEmpty ? 0 : warm[warm.count / 2])ms (excluding first 2 calls) model=\(modelName)")
        case "listen":
            try await listen()
        default:
            usage()
        }
    } catch {
        fail("error: \(error)")
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
Task { @MainActor in
    await runCommand()
    exit(exitStatus)
}
app.run()

/// Waits 3 s (so the user can focus an app), then labels the frontmost app's elements.
/// Never prompts: exits non-zero with a message if Accessibility is not granted.
func frontElements() async throws -> (app: String, labels: [Int: UIElementInfo]) {
    guard Permissions.accessibilityGranted(prompt: false) else {
        fail("Accessibility permission is not granted to this process (or its terminal). Enable it in System Settings > Privacy & Security > Accessibility, then rerun.")
    }
    try await Task.sleep(for: .seconds(3))
    let q = AXQuery()
    return (q.frontmostAppName() ?? "", LabelAssigner.assign(q.actionableElements()))
}

enum Log {
    static func err(_ m: String) { FileHandle.standardError.write(Data((m + "\n").utf8)) }
}

/// mic -> VAD -> assembler -> (bounded queue, newest 2) -> ASR. The VAD loop never waits on ASR.
func listen() async throws {
    let asr = try await ParakeetTranscriber(version: "v2")
    let vad = try await VoiceActivity()
    let config = try loadConfig()
    let mic = try MicrophoneCapture(echoCancellation: config.echoCancellation)
    mic.onEvent = { Log.err("[mic] \($0)") }
    let (chunks, chunkCont) = AsyncStream<[Float]>.makeStream(bufferingPolicy: .unbounded)
    // Keep at most 2 pending utterances; when full the OLDEST is dropped (reported via the yield result).
    let (utterances, uttCont) = AsyncStream<[Float]>.makeStream(bufferingPolicy: .bufferingNewest(2))
    try mic.start { chunkCont.yield($0) }
    Log.err("listening... Ctrl-C to quit")
    defer { mic.stop(); chunkCont.finish(); uttCont.finish() }

    let asrTask = Task {
        for await utterance in utterances {
            var trace = LatencyTrace()
            trace.speechEnd = .now
            do {
                let text = try await asr.transcribe(utterance)
                trace.asrDone = .now
                if !text.isEmpty { print("[\(trace.summary)] \(text)") }
            } catch {
                Log.err("asr error (utterance skipped): \(error)")
            }
        }
    }
    defer { asrTask.cancel() }

    var assembler = UtteranceAssembler()
    for await chunk in chunks {
        do {
            let ev = try await vad.process(chunk)
            if let utterance = assembler.push(chunk, event: ev) {
                if case .dropped = uttCont.yield(utterance) { Log.err("asr backlog: dropped oldest pending utterance") }
            }
        } catch {
            Log.err("vad error (state reset): \(error)")
            await vad.reset()
            assembler.reset()
        }
    }
}
