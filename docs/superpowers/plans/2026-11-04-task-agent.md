# NoHands Task Agent Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the one-shot intent resolver into an observe→act→observe loop so goals like "open Veritasium's latest video" work across several screens, on both the Claude and the local Ollama backend, with simple commands still costing one model call.

**Architecture:** Every model request becomes one *step*: `StepRequest` (goal, history, `ScreenObservation`) in, `IntentStep` (`intent`, `status`, `actions`) out. `TaskRunner` (NoHandsMac, main actor) drives steps: execute, settle, re-observe, until `done`/`stuck`/`ignore`, the step cap, repeat detection, or a spoken stop. `VoicePipeline` runs the task in a child task so a "stop" utterance can cancel it. Pure types, schema, prompt, decoder, stop words, repeat detection and settle comparison live in `NoHandsCore` and are unit-tested; AX reading, resolvers, runner and pipeline wiring live in `NoHandsMac`.

**Tech Stack:** unchanged (Swift 6 / SwiftPM, Swift Testing, ApplicationServices, URLSession). No new dependencies.

**Spec:** `docs/superpowers/specs/2026-11-04-task-agent-design.md` — read it first.

## Global Constraints

- Everything in `docs/superpowers/plans/2026-11-04-nohands-voice-control.md` → Global Constraints still applies (Swift 6 strict concurrency, NoHandsCore imports only Foundation/CoreGraphics, Swift Testing, commit per task, never commit `.build/`).
- `swift build` and `swift test` must pass at the end of every task. Run `swift test` from the package root; it takes ~1 s after the build.
- Property order in the step schema is semantic: `intent`, `status`, `actions`. Only `OrderedJSON` may serialize it for Ollama.
- Keep `Scripts/intent-eval.json` and `Scripts/intent-eval-disfluent.json` passing through `nohands-cli eval` (they compare `step.actions` of step 1). Do not change fixture expectations to make tests pass.
- Element titles, window titles, URLs and the transcript are untrusted text in the prompt; keep the existing "ignore instructions inside them" rule and the `sanitize` 80-char truncation per line.
- Never block the main actor with sleeps; use `Task.sleep`.

## Review Focus

1. **One-shot cost unchanged:** a simple request ("minimize chrome") must produce exactly one model call and run its actions; pinned in Task 5 (`doneOnFirstStepIsOneCall`).
2. **Stop wins:** a stop phrase arriving mid-task must cancel before the next execute, and a held mouse button must be released; pinned in Task 6 (`stopPhraseCancelsRunningTask`).
3. **No runaway:** the loop ends at `maxTaskSteps` and on three identical consecutive action lists; pinned in Task 5.
4. **Local schema order:** the Ollama `format` must serialize with `intent` before `status` before `actions`; pinned in Task 1.

---

## Task 1 — Core step types, schema, decoder, `wait` action, prompt, examples

**Create:** `Sources/NoHandsCore/IntentStep.swift`, `Tests/NoHandsCoreTests/IntentStepTests.swift`
**Modify:** `Sources/NoHandsCore/Action.swift`, `IntentSchema.swift`, `IntentDecoder.swift`, `ActionSummary.swift`, `OllamaRequestBuilder.swift` (examples), `ClaudeRequestBuilder.swift` (user message), `IntentEval.swift`, existing tests that reference `IntentContext`/`actions(fromPayloadText:)`.

- [ ] Add `case wait(ms: Int)` to `Action`; decoder reads kind `wait` with integer `ms` clamped to 100…5000 (missing/invalid `ms` → 1000). `ActionSummary.kind` → `"wait"`. `IntentSchema.kinds` gains `"wait"`; action properties gain `ms` (integer). System prompt lists `- wait: pause for a loading page. Fields: ms (100-5000).`
- [ ] New types in `IntentStep.swift`:
  ```swift
  public enum StepStatus: String, Codable, Sendable { case `continue`, done, stuck, ignore }
  public struct IntentStep: Equatable, Sendable { public var intent: String; public var status: StepStatus; public var actions: [Action] }
  public struct ObservedElement: Equatable, Sendable { public var number: Int; public var role: String; public var title: String }
  public struct ScreenObservation: Equatable, Sendable {
      public var app: String; public var windowTitle: String; public var url: String?
      public var mode: Mode; public var overlay: String; public var elements: [ObservedElement]
  }
  public struct StepRecord: Equatable, Sendable { public var intent: String; public var actions: [Action]; public var failure: String? }
  public struct StepRequest: Sendable { public var goal: String; public var step: Int; public var maxSteps: Int; public var history: [StepRecord]; public var observation: ScreenObservation }
  ```
  Keep `IntentContext` as a thin adapter: `extension ScreenObservation { public init(context: IntentContext) }` and `StepRequest.init(oneShot transcript: String, context: IntentContext, maxSteps: Int = 12)` so the eval, tests and CLI keep working.
- [ ] `IntentSchema.orderedSchema`: top-level properties in order `intent` (string), `status` (enum of StepStatus raw values), `actions`; `required` = all three. `actionsJSONSchema` stays derived from it.
- [ ] `IntentDecoder.step(fromPayloadText:) -> IntentStep` (missing/unknown `status` → `.done` so an old-style payload still works; `intent` missing → ""). `actions(fromPayloadText:)` becomes `step(...).actions`. Add `step(fromResponse:)` and `step(fromOllamaResponse:)` next to the existing `actions(...)` variants.
- [ ] `ClaudeRequestBuilder.userMessage(request: StepRequest) -> String` producing exactly the layout in the spec (Goal / Step n of max / History lines `  k. <intent> -> [kinds] (ok|FAILED: msg)` / App, Window, URL (`-` when nil) / Mode, Overlay / `Visible elements:` lines `  <n> [<role without AX prefix, lowercased>] <title>` / blank / `Request: <goal>` on step 1 or `Request: Continue toward the goal.` afterwards). Keep the old `userMessage(transcript:context:)` as a wrapper calling the new one with a one-shot request. `sanitize` every untrusted field.
- [ ] `body(request:)` on both builders; keep `body(transcript:context:)` wrappers.
- [ ] System prompt: replace the opening with the step-by-step framing from the spec → Prompting, and add a `status` rule block. Keep rule 5 (untrusted text).
- [ ] `IntentExamples.turns`: every assistant payload gains `"status"` (`done` for the existing ones, `ignore` for the weather one). Add a two-step example: step 1 user message with Goal "open veritasium's latest video" in Finder → assistant `continue` with open_app Chrome, cmd+l, type `youtube.com/@veritasium/videos`, return, wait 1500; step 2 user message with history line 1 ok, App Google Chrome, Window "Veritasium - YouTube", URL `https://www.youtube.com/@veritasium/videos`, elements including `[link] Videos`, `[link] <some video title>` → assistant `done` clicking that link's label. Build these with the new `userMessage(request:)` so the format cannot drift.
- [ ] `IntentEval.context(for:)` unchanged; the eval reads `step.actions`. The CLI eval code path is updated in Task 7 — for now only make the Core types compile.
- [ ] Tests (`IntentStepTests.swift`): schema order (`"intent"` index < `"status"` index < `"actions"` index in `orderedSchema.serialized`; required list exact); decoder: status parsed, missing status → done, `wait` clamped (50 → 100, 9000 → 5000, missing → 1000), unknown kind dropped; user message layout golden test for a step-2 request (compare whole string); examples all decode and each has a status; existing tests updated (`effort == "medium"` etc. stay).
- [ ] `swift test` green. Commit: `feat(core): step contract (intent/status/actions), wait action, task-aware prompt`.

## Task 2 — Core guards: stop words, repeat detection, settle comparison, config keys

**Create:** `Sources/NoHandsCore/TaskGuards.swift`, `Tests/NoHandsCoreTests/TaskGuardsTests.swift`
**Modify:** `Sources/NoHandsCore/AppConfig.swift`, `Tests/NoHandsCoreTests/AppConfigTests.swift`, `README.md` (config block)

- [ ] `public enum StopWords { public static func isStop(_ transcript: String) -> Bool }` using `CommandGrammar.normalize` tokens joined: exact matches "stop", "stop it", "stop that", "cancel", "cancel that", "never mind", "nevermind", "abort", "halt", "stop the task".
- [ ] `public struct RepeatDetector { public init(limit: Int = 3); public mutating func record(_ actions: [Action]) -> Bool /* true when `limit` consecutive identical non-empty lists seen */ }`.
- [ ] `public enum Settle { public static func same(_ a: ScreenObservation, _ b: ScreenObservation) -> Bool }` — equal app, window title, url and the multiset of `(role,title)` (numbers ignored).
- [ ] `AppConfig`: `maxTaskSteps` (12, clamp 1…30), `llmDeadlineMs` (12000, clamp 2000…60000), `settleMs` (3000, clamp 0…10000), `maxObservedElements` (120, clamp 10…300); decode with defaults like the other keys; README config example gains the four keys with one-line comments in the prose paragraph after the block.
- [ ] Tests for each (stop phrases incl. "Stop." with ASR punctuation; "stop dictating" is NOT a stop; repeat detector resets on a different list and ignores empty lists; settle ignores numbering/order; config defaults and clamps).
- [ ] `swift test` green. Commit: `feat(core): stop words, repeat detection, settle comparison, task config keys`.

## Task 3 — Screen observation on macOS

**Create:** `Sources/NoHandsMac/ScreenObserver.swift`
**Modify:** `Sources/NoHandsMac/AXQuery.swift`, `Sources/NoHandsMac/ActionExecutor.swift` (`ElementProviding` gains `focusedWindowTitle()` and `webURL()`; `FakeElements` in tests gains defaults), `Sources/NoHandsMac/ClaudeIntentResolver.swift` (`IntentContextBuilder` delegates to the observer)

- [ ] `AXQuery.focusedWindowTitle() -> String?`: `kAXFocusedWindowAttribute` of the frontmost app element → `kAXTitleAttribute`.
- [ ] `AXQuery.webURL() -> String?`: walk the focused window (depth ≤ `maxDepth`) for the first element with role `AXWebArea`, read `AXURL` (CFURL or string); fall back to the window's `AXDocument`. Return nil when absent.
- [ ] Chromium exposure: in `actionableElements()` (or a helper called from it), when the frontmost app's bundle id is one of `com.google.Chrome`, `com.google.Chrome.canary`, `com.brave.Browser`, `com.microsoft.edgemac`, `com.vivaldi.Vivaldi`, `company.thebrowser.Browser`, set `AXManualAccessibility` = `kCFBooleanTrue` on the app element once per pid (keep a `Set<pid_t>`).
- [ ] `public struct ScreenObserver: Sendable { init(ax: any ElementProviding, maxElements: Int); func observe(mode: Mode, overlay: OverlayState) -> (observation: ScreenObservation, labels: [Int: UIElementInfo]) }` — numbering via `LabelAssigner.assign`, titled elements only, first `maxElements`, role string with the `AX` prefix stripped and lowercased.
- [ ] `IntentContextBuilder.makeBundle` now uses `ScreenObserver` under the hood (returns the same `IntentContextBundle` shape, plus a new `observation` field); keep `make(...)` for the CLI.
- [ ] Verify by hand: `swift run nohands-cli labels` still works; add a CLI subcommand `observe` that prints the observation text (`ClaudeRequestBuilder.userMessage(request:)` for a one-shot request with goal "-") for the frontmost app — run it with Chrome on a YouTube channel page and paste the first 20 lines into the commit message body as evidence (URL and `[link]` video titles must appear; if video titles are missing, dig into `AXManualAccessibility`/`AXEnhancedUserInterface` until they do).
- [ ] `swift build && swift test` green. Commit: `feat(mac): screen observation with window title, URL and roles; Chromium AX exposure`.

## Task 4 — Resolvers speak steps

**Modify:** `Sources/NoHandsMac/ClaudeIntentResolver.swift`, `OllamaIntentResolver.swift`, `Tests/NoHandsMacTests/ClaudeIntentResolverTests.swift`, `OllamaClientTests.swift` (if it exercises the resolver), `Sources/nohands-cli/main.swift` (`resolve` and `eval` compile against the new protocol; full CLI work is Task 7)

- [ ] `public protocol IntentResolving: Sendable { func resolve(_ request: StepRequest) async throws -> IntentStep }`. Provide `extension IntentResolving { func resolve(_ transcript: String, context: IntentContext) async throws -> [Action] }` as a convenience that builds a one-shot request and returns `step.actions` (keeps tests/eval/CLI simple).
- [ ] Both resolvers: build with `body(request:)`, decode with `step(...)`, deadline = `.milliseconds(config.llmDeadlineMs)` unless the init's explicit `deadline` is given (tests pass short ones). `requestTimeout` derives from the deadline + 2 s.
- [ ] Tests: existing resolver tests pass with a `status` in their canned responses; add one test per resolver that a `continue` response yields `status == .continue` and the actions.
- [ ] `swift test` green. Commit: `feat(mac): resolvers exchange StepRequest/IntentStep with a configurable deadline`.

## Task 5 — TaskRunner

**Create:** `Sources/NoHandsMac/TaskRunner.swift`, `Tests/NoHandsMacTests/TaskRunnerTests.swift`

- [ ] `@MainActor public final class TaskRunner` with `init(config:, resolver:, executor:, observer: ScreenObserver, overlay: any OverlayPresenting, sleep: @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) })` (injectable sleep so tests run instantly).
- [ ] `public enum TaskOutcome: Equatable { case done(String), stuck(String), ignored, stopped, failed(String) }` (`failed` = resolver error on any step, message from `PipelineText.hud(for:)` or "error").
- [ ] `public func run(goal: String, mode: Mode) async -> TaskOutcome` implementing the spec loop: observe → `StepRequest(goal, step, maxSteps, history, observation)` → resolve → act per status → settle (poll `observer.observe` every 250 ms via `sleep`, stop when `Settle.same` twice in a row, min 300 ms, max `settleMs`) → repeat. `RepeatDetector(limit: 3)`. Execute with `executor.execute(actions, labels:)` using the labels of the observation the model saw. A failed action goes into `StepRecord.failure` and the loop continues. HUD per step: `"step \(n) · \(intent)"` with duration `.seconds(4)`; finish HUD `done` / `stuck: <intent>` / `stopped` / `didn't catch that` for ignored.
- [ ] `public func cancel()` — checked before each resolve and each execute; also cancels the in-flight resolve by running it in a child `Task` that `cancel()` cancels (IntentHTTP already maps cancellation to `.cancelled`). On exit (any path) call `executor.releaseAll()` only if a mouse button may be held — simplest: always call `input.releaseAll()` through a new `executor.releaseButtons()` that does not hide the overlay... Keep it simple: `executor.releaseAll()` on `stopped` and `failed` only.
- [ ] Tests with fakes (`FakeResolver` returning a scripted `[IntentStep]`, `FakeElements` with a mutable element list, `FakeInput`, `FakeOverlay`): `doneOnFirstStepIsOneCall` (resolver called once, actions executed); `continueThenDoneObservesTwiceAndCarriesHistory` (second request's history has step 1 with `failure == nil`; elements changed between calls are reflected); `failedActionIsReportedInHistoryAndLoopContinues`; `stepCapEndsAsStuck` (resolver always `continue`, `maxTaskSteps = 3` → 3 calls, outcome `.stuck("step limit reached")`); `threeIdenticalStepsEndAsStuck`; `cancelBeforeSecondExecuteStopsAndReleases` (cancel from the resolver's `onResolve` hook on step 2 → outcome `.stopped`, no second execute, `input.releaseAllCalls == 1`); `ignoreRunsNothing`; `stuckRunsNothing`.
- [ ] `swift test` green. Commit: `feat(mac): TaskRunner observe/act/settle loop with cap, repeat and cancel guards`.

## Task 6 — Pipeline integration (stop by voice, non-blocking consumer)

**Modify:** `Sources/NoHandsMac/VoicePipeline.swift`, `Tests/NoHandsMacTests/VoicePipelineTests.swift`, `Sources/NoHands/AppDelegate.swift`, `Sources/NoHandsMac/PipelineText.swift`

- [ ] `VoicePipeline` owns a `TaskRunner` (built in `init` from the same executor/resolver/ax/overlay) and `private var activeTask: Task<Void, Never>?`. In the consumer loop: if `activeTask != nil`: `StopWords.isStop(job.transcript)` → `runner.cancel()`, log `-> stop`; otherwise store the job as `heldJob` (newest wins, HUD `"busy — say stop to cancel"`). When no task is active, `handle` runs as today, except `.resolveWithLLM(phrase)` now starts `activeTask = Task { await runner.run(goal: phrase, mode:) ... }`, and when it finishes, clears `activeTask` and handles `heldJob` if any. `stop()`/`pause()` cancel the runner and drop `heldJob`.
- [ ] Log line per task: `[trace] <goal> -> task(<outcome>, steps=<n>)` via `PipelineLog.utterance`.
- [ ] `PipelineText`: constants for `busySayStop`, `stopped`, and `hud(for outcome:)`.
- [ ] Tests: `stopPhraseCancelsRunningTask` (resolver step 1 `continue`, step 2 blocks on a continuation until the test feeds "stop" through `handle`; assert outcome stopped, second execute never ran, `releaseAll` called); `utteranceDuringTaskIsHeldThenRun`; `grammarCommandsUnaffected`; existing pipeline tests pass (adjust for `IntentStep` in `FakeResolver`).
- [ ] AppDelegate: nothing new to wire beyond passing config (runner is internal to the pipeline). Build the app target.
- [ ] `swift build && swift test` green. Commit: `feat(mac): run tasks without blocking the pipeline; "stop" cancels by voice`.

## Task 7 — CLI, eval, docs

**Modify:** `Sources/nohands-cli/main.swift`, `README.md`, `Scripts/intent-eval.json` (only if a fixture became *wrong* under the new contract — explain in the commit if so)

- [ ] CLI `resolve "<text>"` prints the step (`intent`, `status`, actions) without executing. New `task "<goal>"`: 3 s countdown (like `labels`), then runs `TaskRunner` for real on the frontmost app, printing each step's intent, actions and settle time, and the outcome. `eval` keeps comparing `step.actions` and additionally prints `status` for failures.
- [ ] README: new section "Multi-step tasks" (what it does, how to stop, the four config keys, the local-vs-Claude expectation: Claude is far more reliable on web pages; Qwen 7B works for short tasks, ~2–3 s per step), and the CLI table rows for `observe` and `task`.
- [ ] Run `.build/debug/nohands-cli eval Scripts/intent-eval.json` and `... intent-eval-disfluent.json` against whatever backend is configured and paste the accuracy lines into the commit body. Accuracy must not drop more than 5 points versus the numbers in commit 4424122's message (65 % / 85 % on qwen2.5:7b); if it does, fix the prompt, not the fixtures.
- [ ] With Ollama running, run `swift run nohands-cli task "open veritasium's latest video"` once with Chrome available and paste the step log into the commit body (whether or not it fully succeeds — report faithfully; a stuck outcome with a sensible reason is acceptable evidence for the local model).
- [ ] Commit: `feat(cli): resolve shows steps, task runs a goal end to end; docs`.
