# NH-70: Corner panel with the phrase, step trail and progress bar — Design

**Date:** 2026-11-08  **Ticket:** [NH-70](https://github.com/noahstotland/nohands/issues/70)
**Status:** Shipped
**Shipped:** in PR #73, as specified

## Intent

A hands-free user can't tell how a multi-step task is going: the status bar (NH-66) and prompt board show one step as a string. A corner panel shows the phrase just said, the steps done, the current step and a progress bar.

Bottom right of the screen the pointer is on, 340 pt wide: the phrase, one line per step (`✓` done, `✗` failed with `· reason`, `▸` current), then a bar labelled `step 4 of 12`. When the task ends the outcome shows under the bar for the board's 6 s linger.

Non-goals: future steps, spoken status, dragging, themes, changing the bar or board. Anti-goals: the panel never takes focus or a click, never covers the badges, grid, board or status bar, and the bar never suggests how many steps remain.

## Approach

Chosen: a new panel, with step data on the board's row (`PromptRow` gains an optional `trail`), so it inherits the board's linger, pruning and "a final row is never reopened" rule. Rejected: growing the NH-66 bar (must stay one short line).

## Core

- `TaskTrail` (in `TaskTrail.swift`): `maxSteps`, step records (number, intent, running, done or failed with reason) and `ending` (`.stepCap` or `.stuck`).
- `PromptRow.trail` defaults nil. `PromptBoard.report(id:trail:now:)` ignores an unknown id or a final row; a text and status report keeps the trail.
- `TaskPanelText.content(rows:)` returns the phrase, step lines, progress and footer, or nil to hide the panel.

**Which row** (board's visible rows; first match wins, newest within a kind; the outcome row is the newest final `done`, `failed` or `stopped` row):
1. A `running` row, then `heard`.
2. The outcome row, if it has a trail, so a failure and its hint don't vanish when the user starts talking.
3. A `listening` row, then `held`.
4. The outcome row, then any other final row. This keeps `stopped` on screen when a held job's `dropped` lands after it.
5. No rows: nil.

**What it shows.**
- `phrase` is `row.text`. Step text is cut to 80 chars; a blank intent shows `step N`.
- Rows with no trail (`listening`, `heard`, `held`, grammar commands) show the phrase and `status.text` in the status's tone, no steps or bar.
- A live task shows done, failed (`<intent> · <failure>`) and `current` lines, with `step N of M` (N the newest step started, M `maxSteps`; a finished task's bar stays where it stopped). Before the first step and between steps the footer reads `Working out the next step…` (local resolves take 5 to 20 s).
- A step still running on a final row shows done, failed or `stopped` by the row's status; a final row never has a `current` step.
- Footers: `done` uses `status.text`; step cap says `Hit the M-step limit · try a smaller request`; stuck adds `· say it another way`; a resolver error adds `· try again`; `stopped` is muted. `ending` is data, so the panel never parses `status.text`.
- More than 8 steps: the newest 8 plus `+ N earlier steps`.

## TaskRunner and pipeline

- `TaskRunner.onTrail` beside `onStatus`: one trail per `run`, with the run's real `maxSteps`. Emitted at the start, on each step begin and end (not for `ActionExecutor.cancelled`, so a stopped step stays running), and in `finish` after setting `ending`. `.running("step N · …")` and stop handling are unchanged.
- `VoicePipeline.runTask` reports the trail on the prompt's row; the CLI leaves it nil.

## Panel (`OverlayController`)

- Non-activating, ignores the mouse, never key or main.
- Redrawn from `renderBoard()` from `board.visibleRows(now:)` (no timer). Hidden when content is nil and whenever the grid or badges are up.
- Bottom right of the pointer's screen visible frame, 16 pt inset, width `min(340, screen width - 32)`. If it meets the status bar on a narrow screen it moves up by the bar height plus 6 pt. It is at most about 300 pt tall, so it can't meet the board.
- Style: the board's dark fill and tones.

## Tests

One table over the content rules, one over row choice, board trail reports (a final row never changes), and `TaskRunnerTests` trail sequences. Layout and colours are untested. Docs: README **Corner panel** paragraph. Manual checks go in the PR.

## Calls I made

- **The panel hides when idle.** The ticket says "at all times" but leaves it open; the always-on NH-66 bar would repeat `Listening`.
- **"worktrtee" in the request is read as the step trail;** unconfirmed. **A new panel, not a bigger bar,** per the ticket's Scope.
- **No off switch;** the Status Bar menu's Off doesn't affect the panel.
- **A prompt spoken during a task doesn't take over the panel.** An outcome holds its 6 s against words still being spoken, not against a new prompt that has started.
- **The bar counts the newest step started,** not remaining steps.
- **Hidden while the grid or badges are up,** even mid-task. **Grammar commands show too.**
- **At most 8 steps listed** (the cap can be 30). **Linger is the board's 6 s;** no second timer.
