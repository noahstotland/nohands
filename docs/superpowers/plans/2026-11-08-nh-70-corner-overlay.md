# NH-70 Corner panel with step trail and progress bar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A click-through bottom-right panel shows the current prompt's phrase, its step trail and a "step N of M" progress bar.

**Architecture:** Structured step data (`TaskTrail`) lives in `NoHandsCore` and rides on the existing `PromptRow`. A pure function `TaskPanelText.content(rows:)` picks what the panel shows. `TaskRunner` emits the trail through a new `onTrail` hook, `VoicePipeline` forwards it to the board row, and `OverlayController` draws a third panel from the same rows the board and status bar read.

**Tech Stack:** Swift 6 strict concurrency, SwiftPM, AppKit, swift-testing (`@Test`, `#expect`).

**Spec:** `docs/superpowers/specs/2026-11-08-nh-70-corner-overlay-design.md`

## Global Constraints

- `NoHandsCore` has no AppKit, CoreGraphics event or network dependency; no `@unchecked Sendable`, no `@preconcurrency`.
- `.running("step N · <intent>")` strings stay exactly as they are (the board, the status bar and `nohands-cli` read them).
- A spoken "stop" is never merged and always halts the task; the panel only reads state.
- Panel: 340 pt wide (`min(340, screen width − 32)`), 16 pt from the right and bottom edges of the pointer's screen's visible frame, at most 8 step lines, 6 s linger (the board's `finalLinger`, no new timer).
- Texts: `Working out the next step…`, `Hit the M-step limit · try a smaller request`, `<status.text> · say it another way`, `<status.text> · try again`.
- Tests per `AGENTS.md`: one table-driven test per rule; none for layout, colours or placement. `swift test` needs no permissions or Ollama.
- Commits are conventional (`feat(core):`, `feat(mac):`, `docs:`) and end with the attribution line from the session.

## Review Focus

- A step cancelled mid-flight (stop) must stay `running` in the trail so the panel shows it as stopped, not failed. Pinned in Task 2.
- A media goal's longer cap (`maxMediaTaskSteps`) must show as `M`, not `maxTaskSteps`. Pinned in Task 2.
- A late `.running` report or trail after the row is final must not revive it. Pinned in Task 1.
- A blank intent or a very long intent or failure must not break the line. Pinned in Task 1.
- More than 8 steps must show the newest 8 and a count of the earlier ones. Pinned in Task 1.

---

### Task 1: Core: trail, board field, panel content

**Files:**
- Create: `Sources/NoHandsCore/TaskTrail.swift`
- Modify: `Sources/NoHandsCore/PromptBoard.swift` (`PromptRow`, `PromptBoard`)
- Test: `Tests/NoHandsCoreTests/TaskPanelTests.swift`

**Interfaces:**
- Produces (all `public`, `Equatable`, `Sendable`): `TaskStepRecord(number:intent:state:)` with `State { running, done, failed(String) }`; `TaskTrail(maxSteps:)` with `steps`, `ending: Ending?` (`.stepCap`, `.stuck`), `mutating begin(number:intent:)`, `mutating end(number:failure:)`; `PromptRow.trail: TaskTrail?`; `PromptBoard.report(id:trail:now:)`; `TaskPanelContent` (`phrase`, `earlierSteps`, `lines: [Line]`, `progress: Progress?`, `footer: StatusLine?`, `Mark { done, current, failed, stopped }`, `Progress(label:fraction:)`); `TaskPanelText.content(rows:) -> TaskPanelContent?`.
- Consumes: `StatusLine`, `PromptStatus`, `OverlayMath.hudText(_:maxChars:)`.

- [ ] **Step 1: Write the failing tests in `TaskPanelTests.swift`.** Use a `row(id, text, status, trail?, at:)` helper like `StatusBarTests`. Tests:
  - `taskPanelContent`: a table over the spec's content table. Assertions on `lines.map(\.mark)`, `progress?.label`, `footer?.text` and `footer?.tone` for: running with a current step (`step 2 of 12`, no footer); running between steps (footer `Working out the next step…`); a failed step while the task goes on (`✗` line text `<intent> · <failure>`); `done` (all done, `step 3 of 12`, tone good); `failed` with `.stepCap` (`step 12 of 12`, `Hit the 12-step limit · try a smaller request`); `failed` with `.stuck` (suffix `say it another way`); `failed` with a trail and no ending (suffix `try again`); `failed` with no trail (footer is `status.text`, no lines, no progress); `stopped` with a step still running (that line is `.stopped`, muted footer); `held`, `listening` and `heard` with no trail (footer is `status.text`, no lines); a live row with an empty trail (footer `Working out the next step…`); a blank intent shows `step 3`; a 90-character intent is cut to 80 with `…`.
  - `taskPanelLines`: 11 steps give 8 lines, `earlierSteps == 3`, and the newest step last. `fraction == 11/12`; with `N > M` it clamps to 1.
  - `taskPanelRowChoice`: running beats held and listening; heard beats an outcome; an outcome with a trail beats a newer listening and held row; a `listening` row beats a grammar command's `done` (no trail); `stopped` beats a newer `dropped`; with no `listening` or `held` row, a newer `done` with no trail beats an older task's `done`; no rows gives `nil`.
  - `taskTrailTransitions`: `begin` appends running; `end(number:failure: nil)` gives done; with a string gives `failed`; `end` on an unknown number changes nothing. On `PromptBoard`: `report(id:trail:now:)` on a final row changes nothing, on an unknown id changes nothing, and a later `report(id:text:status:now:)` keeps the trail.

- [ ] **Step 2: Run `swift test --filter TaskPanel` and `--filter taskTrail`.** Expected: build FAIL, types undefined.

- [ ] **Step 3: Implement `TaskTrail.swift` and the board changes.** `PromptRow.init` gains `trail: TaskTrail? = nil`. `PromptBoard.report(id:trail:now:)` returns without effect for an unknown id or a final row, else sets `trail` and `updatedAt`.

- [ ] **Step 4: Implement `TaskPanelText.content(rows:)`.** Row choice, first match wins, newest `updatedAt` (then larger `id`) within a kind: a `running` row; a `heard` row; the outcome row (newest final of `done`, `failed`, `stopped`) when its `trail != nil`; a `listening` row; a `held` row; the outcome row; the newest other final row; else `nil`. Then build the content from the spec's table: `progress.fraction = min(1, N / M)` with label `step N of M` (`N` = newest step number; the stepCap case uses `M`); on a final row a step still `running` becomes `.failed` for `failed` rows, `.done` for `done` rows, `.stopped` for `stopped` rows and `.failed` otherwise; only a non-final row can show `.current`. Text goes through `OverlayMath.hudText(_, maxChars: 80)`; a failed line is `<intent> · <failure>`.

- [ ] **Step 5: Run `swift test --filter TaskPanel` and `--filter taskTrail`.** Expected: PASS.

- [ ] **Step 6: Commit** `feat(core): task trail and corner panel content (NH-70)`.

### Task 2: TaskRunner and pipeline emit the trail

**Files:**
- Modify: `Sources/NoHandsMac/TaskRunner.swift`, `Sources/NoHandsMac/ActionExecutor.swift` (`OverlayPresenting`), `Sources/NoHandsMac/VoicePipeline.swift` (`runTask`), `Sources/NoHandsMac/OverlayController.swift` (`report(_:trail:)` only), `Tests/NoHandsMacTests/Fakes.swift`
- Test: `Tests/NoHandsMacTests/TaskRunnerTests.swift`

**Interfaces:**
- Consumes: `TaskTrail` from Task 1.
- Produces: `TaskRunner.onTrail: ((TaskTrail) -> Void)?`; `OverlayPresenting.report(_ id: Int, trail: TaskTrail)`; `FakeOverlay.trails: [(id: Int, trail: TaskTrail)]`.

- [ ] **Step 1: Write the failing test `trailFollowsTheTask`** in `TaskRunnerTests.swift`. `rig` gets `runner.onTrail = { log.trails.append($0) }` (add `trails: [TaskTrail]` to `StatusLog`; also in `harnessRig`). Table-style assertions on `log.trails.last` and the sequence of `steps.map(\.state)`:
  - success, `[continue "open", done "type"]`: states end `[.done, .done]`, `ending == nil`, `maxSteps == 12`.
  - a step whose `.focusApp` fails (use the existing fake that makes `execute` fail; mirror the existing failed-step test): that step is `.failed(<failure>)` and the next step starts.
  - cancel mid-step: call `runner.cancel()` from inside the fake executor action as the existing stop tests do; the last trail has the step `.running` and the final status is stopped.
  - the step cap (`rig(..., maxSteps: 3)` with continuing steps): last trail `ending == .stepCap`, `steps.count == 3`.
  - `.stuck("hmm")` from the model: `ending == .stuck`.
  - a media goal ("watch cats on youtube") with default config: `maxSteps == config.maxMediaTaskSteps`.
  The first emission of each run is the empty trail.

- [ ] **Step 2: Run `swift test --filter trailFollowsTheTask`.** Expected: build FAIL (`onTrail`).

- [ ] **Step 3: Implement in `TaskRunner`.** `public var onTrail`. In `run`, `var trail = TaskTrail(maxSteps: maxSteps)` and emit it after the setup; beside `onStatus?(.running("step \(n) · …"))` call `trail.begin` and emit; after `stepsRun = n`, unless `failure == ActionExecutor.cancelled`, call `trail.end(number: n, failure: failure)` and emit. `finish` needs the trail: make it an instance property `private var trail` reset in `run`, and in `finish` set `ending` (`.stepCap` when the outcome is `.stuck(Self.stepLimit)`, `.stuck` for any other `.stuck`) and emit before the final `onStatus`.

- [ ] **Step 4: Implement the plumbing.** `OverlayPresenting.report(_:trail:)`; `FakeOverlay` records it; `OverlayController.report(_ id:trail:)` calls `board.report(id:trail:now:)` then `renderBoard()`. `VoicePipeline.runTask` sets `runner.onTrail = { [weak self] t in self?.overlay.report(id, trail: t) }` and clears it with `onStatus`.

- [ ] **Step 5: Add one assertion to a `VoicePipelineTests` task test** that `overlay.trails` for the task's id is non-empty and the last is the finished trail. Run `swift test --filter TaskRunner` and `--filter VoicePipeline`. Expected: PASS, including the existing status-text assertions unchanged.

- [ ] **Step 6: Commit** `feat(mac): TaskRunner emits a structured step trail (NH-70)`.

### Task 3: The corner panel

**Files:**
- Modify: `Sources/NoHandsMac/OverlayController.swift`

**Interfaces:**
- Consumes: `TaskPanelText.content(rows:)`, `BoardView.color(_:)`, `OverlayMath.hudText`.
- Produces: `taskPanel`, `renderTaskPanel()` called from `renderBoard()` beside `renderStatusBar()` (before the empty-board guard); private `TaskPanelView`.

No unit test (layout and drawing). 

- [ ] **Step 1: Implement `renderTaskPanel()`.** Hide (`orderOut`) when `state != .none` or `content` is `nil`. Otherwise size: width `min(340, screen width − 32)`, height from content (phrase up to 2 lines, an optional `+ N earlier steps` line, one line per step, a progress row if present, a footer up to 2 lines, padding 10). Origin: right edge − 16, bottom edge − 16 of `visibleBoundsCG(containing: pointerCG())`. If the frame intersects the status bar's frame (track it as `shownStatusFrame` set in `renderStatusBar`, nil when hidden), move up by the bar height + 6. Replace `contentView` only when the content or size changed (keep `shownTask: (TaskPanelContent, CGSize)?`).

- [ ] **Step 2: Implement `TaskPanelView`** (flipped, like the other views): board fill, phrase 14 pt medium white, step lines 12 pt with marks `✓` (good), `✗` (bad), `▸` (active, medium weight), `■` (muted), progress track (6 pt tall, rounded) with the label on its right, footer 12 pt in its tone colour. Truncate tails.

- [ ] **Step 3: Run `swift build`.** Expected: clean, no concurrency warnings. Then `scripts/bundle.sh` if time allows to confirm the app links (not launched).

- [ ] **Step 4: Commit** `feat(mac): corner panel for the phrase, steps and progress (NH-70)`.

### Task 4: Docs and verification

**Files:**
- Modify: `README.md` (a **Corner panel** paragraph after **Status bar**), `docs/superpowers/specs/2026-11-04-nohands-design.md` (the `OverlayController` line)

- [ ] **Step 1: Write the README paragraph.** What it shows, bottom right, hides when idle and while the grid or numbers are up, lingers 6 s, no setting.
- [ ] **Step 2: Update the architecture spec line.**
- [ ] **Step 3: Run `swift build` and `swift test`.** Expected: clean build; all tests PASS. Run `.build/debug/nohands-cli eval scripts/intent-eval.json` is not needed (no grammar or prompt change).
- [ ] **Step 4: Commit** `docs: describe the corner panel (NH-70)`.
