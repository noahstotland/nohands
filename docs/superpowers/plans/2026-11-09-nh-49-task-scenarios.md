# NH-49 Task Scenario Suite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `nohands-cli scenarios` runs scripted live task goals and scores each against an independent screen check.

**Architecture:** Pure decoding, validation, checks, verdicts and report formatting go in `NoHandsCore/TaskScenario.swift` with table tests. The command goes in a new `Sources/nohands-cli/Scenarios.swift` and reuses `TaskRunner`, `ScreenObserver` and `ActionExecutor` exactly as the `task` case does. `main.swift` gains only a `case` and a usage line.

**Tech Stack:** Swift 6 strict concurrency, swift-testing (`@Test`, `#expect`), Foundation `NSRegularExpression`.

**Spec:** `docs/superpowers/specs/2026-11-09-nh-49-task-scenarios-design.md`

## Global Constraints

- Swift 6 strict concurrency; no `@unchecked Sendable`, no `@preconcurrency`.
- `NoHandsCore` has no AppKit, CoreGraphics event or network dependencies.
- Tests need no screen, permission, Ollama or API key. Test lines must not exceed feature lines.
- `maxSteps` is 1 to 30. Start URLs are http or https only. Check observer element cap is 300.
- Timeouts: start state 20 s polled each 1 s, final check 3 s polled each 1 s, 2 s between scenarios, 3 s before the first.
- Exit status: 0 all `pass`, 2 otherwise, 1 usage or file error, 130 on a second Ctrl-C.
- Never edit `scripts/intent-eval*.json`. Do not touch the task loop, its prompt or the fixtures.
- Commits are conventional (`feat:`, `docs:`) and end with the Co-Authored-By line from the session reminder.

## Review Focus

- A `done` task whose screen checks fail scores `false-done`, never `pass` (Task 1 verdict table).
- `ignored` ends exit 0 in `TaskOutcome` but must never count as success (Task 1 `TaskEnd.ignored`).
- `elementAbsent` with no `elementVisible` beside it is rejected at load, so an unread page can't pass (Task 1 validation table).
- A hostile scenario file (a `file:` start URL, a bad regex, `maxSteps` 0 or 99, a duplicate name) fails at load before anything runs (Task 1).
- Report cells with `|`, newlines or control characters from the screen can't break the table (Task 1 report test).

---

### Task 1: Scenario model, checks, verdicts, report (core)

**Files:**
- Create: `Sources/NoHandsCore/TaskScenario.swift`
- Create: `Tests/NoHandsCoreTests/TaskScenarioTests.swift`

**Interfaces:**
- Produces:
  - `public enum ScenarioStart: Equatable, Sendable { case app(String), url(URL) }`
  - `public enum ScenarioCheck: Equatable, Sendable { case windowTitleContains(String), urlMatches(String), elementVisible(String), elementAbsent(String), mediaPlaying }` with `public func holds(in o: ScreenObservation) -> Bool` and `public var label: String` (for failure lines, e.g. `urlMatches youtube\.com/watch`).
  - `public struct TaskScenario: Equatable, Sendable { name, goal: String; start: ScenarioStart; ready, success: [ScenarioCheck]; maxSteps: Int }`
  - `public enum ScenarioFile { public static func load(_ data: Data, run: Int) throws -> [TaskScenario] }` throws `ScenarioFileError` (`LocalizedError`, message names the scenario). `run` is the Unix-seconds value substituted for `{run}` in `goal` and every check string.
  - `public static func startHolds(_ s: ScenarioStart, in o: ScreenObservation) -> Bool` on `TaskScenario`.
  - `public enum TaskEnd: Equatable, Sendable { case done, stuck, failed, ignored, stopped }`
  - `public enum ScenarioVerdict: String, Sendable { case pass, falseDone = "false-done", unclaimed, fail, stopped, startFailed = "start-failed", notRun = "not-run" }` and `public static func verdict(end: TaskEnd, checksHold: Bool) -> ScenarioVerdict` (the spec's table; `stopped` ignores `checksHold`).
  - `public struct ScenarioResult: Sendable { name: String; verdict: ScenarioVerdict; steps: Int; seconds: Double }` and `public enum ScenarioReport { static func table(_ r: [ScenarioResult]) -> String; static func summary(_ r: [ScenarioResult]) -> String }`.

- [ ] **Step 1: Write the failing tests** in `TaskScenarioTests.swift`. One table per rule, with the spec's exact values:
  - `scenarioFileRejections`: each of these throws, and the error text contains the scenario name or the reason: bad JSON, missing `goal`, duplicate name, a check with zero keys, a check with two keys, an unknown check key, `urlMatches` `"("`, `start` with both `app` and `url`, neither, `url` `file:///etc/hosts`, `maxSteps` 0 and 31, empty `success`, `elementAbsent` with no `elementVisible` in the same list, `mediaPlaying` `false`. One valid file with all five check kinds, an `app` start and `{run}` in the goal decodes, with `{run}` replaced.
  - `checksHoldOnObservation`: build `ScreenObservation` values (see `IntentStep.swift:28`) and table `(check, observation, want)`: title contains ignoring case; `urlMatches` with no URL is false, matches case-insensitively; `elementVisible` substring ignoring case; `elementAbsent` is false on an empty element list and false when present, true when the list is non-empty without it; `mediaPlaying` is true only for `.playing`.
  - `startStateComparesHostAndPath`: `url` start `https://www.youtube.com/` holds for `https://youtube.com` and `https://www.youtube.com/`, not for `https://www.youtube.com/watch?v=x` or `https://example.com/`; nil URL fails; `app` start holds for a front app containing the name (case-insensitive) with a non-empty window title, not with an empty title.
  - `verdictTable`: the spec's seven rows, plus `ignored` + checks hold = `unclaimed`.
  - `reportEscapesCells`: a result named `a|b\nc` renders one table row with `\|` and no newline or control character; the summary counts each verdict.
- [ ] **Step 2: Run** `swift test --filter TaskScenarioTests`. Expected: FAIL, symbols not defined.
- [ ] **Step 3: Implement** the interfaces above in `TaskScenario.swift`. Decode with a private `Decodable` mirror and a custom check decoder that reads the keyed container and requires exactly one key. `urlMatches` is compiled with `NSRegularExpression` (`.caseInsensitive`) at load to validate, and again (or cached) in `holds`. `startHolds` for `url` compares host (lowercased, leading `www.` dropped) and path (trailing `/` dropped, empty = `/`).
- [ ] **Step 4: Run** `swift test --filter TaskScenarioTests`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(core): task scenario model, checks and verdicts (NH-49)`.

### Task 2: The `scenarios` command (cli)

**Files:**
- Create: `Sources/nohands-cli/Scenarios.swift`
- Modify: `Sources/nohands-cli/main.swift` (a `case "scenarios":` calling `await runScenarios(rest)`, plus a usage line)

**Interfaces:**
- Consumes: Task 1 types; from `main.swift`: `loadResolver()`, `loadHarness(_:)`, `runOverlay(_:)`, `sanitized(_:)`, `ms(_:)`, `fail(_:)`, `synth`, `InterruptState`. These are file-scope in `main.swift`; if the compiler rejects use from another file because they sit after top-level statements, make `Scenarios.swift` hold only `@MainActor func runScenarios(_ args: [String]) async -> Int32` and pass the helpers it needs as parameters.
- Produces: `@MainActor func runScenarios(_ args: [String]) async -> Int32` returning the exit status; `main.swift` assigns it to `exitStatus`.

No unit tests: the command needs the screen and a model (a manual check, listed in the PR).

- [ ] **Step 1: Parse args** `[file] [--only name]`; default file `scripts/task-scenarios.json`. Load with `ScenarioFile.load(data, run: Int(Date().timeIntervalSince1970))`. A file or validation error is `fail(...)` (exit 1). `--only` naming no scenario is exit 1.
- [ ] **Step 2: Header.** Load the resolver and harness as `task` does, require Accessibility, print model, backend, `sysctl hw.model` and the harness status line, print "close tabs left by an earlier run", sleep 3 s.
- [ ] **Step 3: Observers.** The task loop's observer is built as in the `task` case. The check observer is a second `ScreenObserver` with `maxElements: 300` and `audio:` a private `struct NoAudio: AudioOutputProbing { func isPlaying() -> Bool { false } }`, using the same harness. A helper `freshObservation()` walks once, sleeps 1 s (Chromium tree), then observes with `harnessKind` from `probe()`, returning `(ScreenObservation, labels)`.
- [ ] **Step 4: Per scenario.** Start: `AXQuery().activate(appNamed:)` or `.open(url:appNamed: nil)`. Poll `freshObservation()` each 1 s for 20 s until `startHolds` and every `ready` check hold, else verdict `.startFailed`. Run a `TaskRunner` built as in `task` (same wiring, same `onStep` printing) from `config` copied with `maxTaskSteps` and `maxMediaTaskSteps` both set to `maxSteps`. Map `TaskOutcome` to `TaskEnd` (`.done`→done, `.stuck`→stuck, `.failed`→failed, `.ignored`→ignored, `.stopped`→stopped). Unless stopped, poll `freshObservation()` each 1 s for up to 3 s until all `success` hold; on failure print each failing `label` with the window title and URL seen. Print `verdict steps time`.
- [ ] **Step 5: Stop playback.** If the scenario had `.mediaPlaying` and the final observation lists an element where `MediaSignal.control(role:name:value:) == .pause`, run `executor.execute([.click(.label(n), button: .left, count: 1)], labels: labels)`; if none is listed print `still playing`.
- [ ] **Step 6: Ctrl-C.** SIGINT handling as in `task` using `InterruptPolicy`: first calls `runner.cancel()` (or flags the start wait to abort), marks that scenario `.stopped` and the rest `.notRun`, then prints the summary and returns 2; second exits 130.
- [ ] **Step 7: Finish.** Sleep 2 s between scenarios; at the end print `ScenarioReport.summary` and `ScenarioReport.table`. Return 0 only when every scenario that ran is `.pass`.
- [ ] **Step 8: Verify** `swift build` is clean under Swift 6, and `.build/debug/nohands-cli scenarios nonexistent.json` exits 1 with a message; `scenarios scripts/task-scenarios.json --only nope` (after Task 3) exits 1.
- [ ] **Step 9: Commit** `feat(cli): scenarios command (NH-49)`.

### Task 3: Scenario file, README, usage

**Files:**
- Create: `scripts/task-scenarios.json`
- Modify: `README.md` (CLI table row for `scenarios`), `Sources/nohands-cli/main.swift` usage text (if not done in Task 2)
- Test: add to `TaskScenarioTests.swift` one test, `shippedScenarioFileLoads`, that loads `scripts/task-scenarios.json` (path resolved from `#filePath` up to the repo root) and expects six scenarios, so the file can't rot unnoticed.

- [ ] **Step 1: Write the failing test**, then run it (FAIL: file missing).
- [ ] **Step 2: Write the six scenarios** exactly as the spec's table (names, goals, starts, `maxSteps`). `cookie-banner`: pick one real site that shows a US consent banner, check it in the browser now, and give it `ready: [elementVisible "<accept button title>"]`, `success: [urlMatches <site host>, elementVisible <stable link>, elementAbsent "<accept button title>"]`. `textedit-save` uses `nohands-scenario-{run}`.
- [ ] **Step 3: Run** the test. Expected: PASS.
- [ ] **Step 4: README.** Add a `scenarios [file] [--only name]` row to the CLI table beside `task`: what it does, the verdicts, exit 0 / 2, that it takes over the screen, and the close-old-tabs reminder.
- [ ] **Step 5: Commit** `feat: shipped task scenarios and README row (NH-49)`.

### Task 4: First live run and as-built note

**Files:**
- Create: `docs/superpowers/as-built/2026-11-09-task-scenarios.md`

- [ ] **Step 1: Check the backend.** `effectiveBackend` is Claude only with a key in `~/.config/nohands/config.json` or `ANTHROPIC_API_KEY`. Without one the run uses the local model; say so in the note and list the Claude run under Not proven in the PR. Never write a key anywhere.
- [ ] **Step 2: Run** `swift build && .build/debug/nohands-cli scenarios` once, with browsers' old tabs closed. It takes over the screen for several minutes. Save stdout outside the repo (scratchpad).
- [ ] **Step 3: Write the as-built note.** Header lines per `docs/superpowers/README.md` (`**Shipped:** in PR #N`, ticket, spec), then: hardware (M1 Pro, `MacBookPro18,3`), backend and model, harness, date, the verdict table (names, verdicts, steps, times only; no titles or URLs), the cookie-banner site, anything that differs from the spec (timeouts changed, scenarios `start-failed`), and the "rerun is `start-failed` until cookies clear" note.
- [ ] **Step 4: Verify** `swift test` passes with no permissions and no Ollama; the intent fixtures are untouched (`git diff --stat origin/main -- scripts/intent-eval*.json` is empty).
- [ ] **Step 5: Commit** `docs: first task scenario run (NH-49)`.
