# NH-70 Corner panel with step trail and progress bar Implementation Plan

**Goal:** A click-through bottom-right panel shows the current prompt's phrase, its step trail and a "step N of M" progress bar.

**Architecture:** Step data (`TaskTrail`) lives in `NoHandsCore` and rides on `PromptRow`. A pure `TaskPanelText.content(rows:)` picks what the panel shows. `TaskRunner` emits it through `onTrail`, `VoicePipeline` forwards it to the board row, and `OverlayController` draws the panel from the rows the board already reads.

**Spec:** `docs/superpowers/specs/2026-11-08-nh-70-corner-overlay-design.md`

## Global Constraints

- `NoHandsCore` has no AppKit or network dependency.
- `.running("step N · <intent>")` strings stay exactly as they are (the board, status bar and CLI read them).
- The panel only reads state; "stop" is untouched.
- 340 pt wide, 16 pt inset, at most 8 step lines, the board's 6 s linger.
- No tests for layout or colours.

## Review Focus

- A step cancelled mid-flight stays `running`, so the panel shows it stopped, not failed.
- A media goal's longer cap shows as `M`.
- A late report after the row is final must not revive it.

## Task 1: Core: trail, board field, panel content

`TaskTrail.swift` (new), `PromptBoard.swift`, `TaskPanelTests.swift`.

- Add `TaskTrail`, `PromptRow.trail`, `PromptBoard.report(id:trail:now:)` (no effect for an unknown id or a final row), and `TaskPanelText.content(rows:)`, with row choice in the spec's order.
- Progress is `min(1, N / M)`. On a final row a running step becomes failed, done or stopped by the row's status; only a non-final row shows `current`.
- Tests: a content table over the spec's cases (11 steps give 8 lines and 3 earlier), row-choice precedence, trail and board transitions.

## Task 2: TaskRunner and pipeline emit the trail

`TaskRunner.swift`, `OverlayPresenting`, `VoicePipeline.runTask`, fakes, `TaskRunnerTests.swift`.

- `run` emits the empty trail, then `begin` beside `onStatus`, then `end` after each step unless the failure is `ActionExecutor.cancelled`. `finish` sets `ending` and emits before the final `onStatus`. `runTask` sets and clears `onTrail` with `onStatus`.
- Test `trailFollowsTheTask`: success, failed step, cancel mid-step, step cap, stuck, media cap; plus one pipeline assertion that the row gets a trail.

## Task 3: The corner panel

`OverlayController.swift`. No unit test.

- `renderTaskPanel()` runs from `renderBoard()` beside `renderStatusBar()`. Hidden when the grid or badges are up. If it meets the status bar it moves up by the bar height plus 6 pt.
- A private `TaskPanelView` with marks `✓ ✗ ▸ ■` and a 6 pt progress track.

## Task 4: Docs

README **Corner panel** paragraph after **Status bar** (hides when idle and while the grid or numbers are up, no setting); the `OverlayController` line in the architecture spec.
