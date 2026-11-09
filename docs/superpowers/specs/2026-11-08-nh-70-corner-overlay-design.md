# NH-70: Corner panel with the phrase, step trail and progress bar — Design

**Date:** 2026-11-08  **Ticket:** [NH-70](https://github.com/noahstotland/nohands/issues/70)
**Status:** Draft

## Intent

A hands-free user can't tell how a multi-step task is going. The one-line status bar (NH-66) and the prompt board
show one step at a time, as a string, and nothing shows how far the task has got. The user called this very
important. A corner panel shows what was just said, the steps done so far, the current step, and a progress bar.

## What the user sees

Bottom right of the screen the pointer is on, 340 pt wide:

```
┌────────────────────────────────────────┐
│ open YouTube and search for cats       │
│ ✓ open YouTube                         │
│ ✓ click the search box                 │
│ ✗ press return · no focused field      │
│ ▸ type the search                      │  (highlighted)
│ ████████░░░░░░░░░░░░░░░░  step 4 of 12 │
└────────────────────────────────────────┘
```

When the task ends, the running line resolves and the outcome goes under the bar for the board's 6 s linger:

```
│ ████████████░░░░░░░░░░░░  step 6 of 12 │
│ done · search for cats (6 steps)       │
```

## Goals and non-goals

Goals are the ticket's Scope and Acceptance. Non-goals are its Out of scope: planning or showing future steps,
spoken status, dragging, themes, per-display placement, and changing how the bar or the board behave.

Anti-goals: the panel must never take focus or a click, and must never cover the badges, the grid, the board or the
status bar. The bar must never suggest how many steps remain.

## Approaches

1. **A new panel, with the step data on the board's row (chosen).** `PromptRow` gains an optional `trail`. The
   panel reads the same rows as the board and the bar, so it gets their linger, pruning and "a final row is never
   reopened" rule for free. This is the ticket's Scope.
2. **Grow the NH-66 one-line bar into the panel.** One indicator instead of two, but the ticket puts changing the
   bar out of scope, and the bar's job (always one short line, also for problems and pause) would go.
3. **Put the structure inside `PromptStatus.running`.** Avoids a new field, but changes every `.running` site, the
   CLI and `status.text`, which the board and the bar rely on.

## Core: the step data

New file `Sources/NoHandsCore/TaskTrail.swift`:

```swift
public struct TaskStepRecord: Equatable, Sendable {
    public enum State: Equatable, Sendable { case running, done, failed(String) }
    public let number: Int
    public let intent: String
    public var state: State
}

public struct TaskTrail: Equatable, Sendable {
    public enum Ending: Equatable, Sendable { case stepCap, stuck }
    public let maxSteps: Int
    public private(set) var steps: [TaskStepRecord] = []
    public var ending: Ending?
    public init(maxSteps: Int)
    public mutating func begin(number: Int, intent: String)   // appends a running step
    public mutating func end(number: Int, failure: String?)   // running → done, or failed(failure); no-op on an unknown number
}
```

`PromptRow` gains `public var trail: TaskTrail?` (init parameter defaulting to `nil`). `PromptBoard` gains
`report(id:trail:now:)`, which sets the row's trail and `updatedAt`, and does nothing for an unknown id or a final
row. The existing `report(id:text:status:now:)` keeps a row's trail.

## Core: what the panel shows

New pure function, in `TaskTrail.swift` or a sibling file:

```swift
public struct TaskPanelContent: Equatable, Sendable {
    public enum Mark: Equatable, Sendable { case done, current, failed, stopped }
    public struct Line: Equatable, Sendable { public let text: String; public let mark: Mark }
    public struct Progress: Equatable, Sendable { public let label: String; public let fraction: Double }
    public let phrase: String
    public let earlierSteps: Int        // older steps not listed ("+ 4 earlier steps")
    public let lines: [Line]            // at most the 8 newest steps
    public let progress: Progress?
    public let footer: StatusLine?
}

public enum TaskPanelText {
    /// nil when no row should show: the panel hides.
    public static func content(rows: [PromptRow]) -> TaskPanelContent?
}
```

**Which row.** `rows` is the board's visible rows.

First match wins, and within a kind the newest row wins. "Outcome row" means the newest final row whose status is
`done`, `failed` or `stopped`.

1. A `running` row, then a `heard` row. So a phrase spoken during a task does not displace the task; the board
   still shows it. A held prompt that starts running does replace the last task's outcome.
2. The outcome row, if it has a trail. A task's outcome holds through its linger against words that are only being
   spoken or waiting, so a failure and its hint can't vanish the moment the user starts talking.
3. A `listening` row, then a `held` row.
4. The outcome row.
5. Any other final row (`ignored`, `dropped`). Rule 4 before rule 5 is what keeps `stopped` on screen when a held
   job's `dropped` row lands just after it.
6. No rows: `nil`.

Make `StatusBarText.liveRow` internal if reusing it on a filtered list helps; the order above is what counts.

**What it shows for that row.** `phrase` is `row.text`. Step text goes through `OverlayMath.hudText(_, maxChars: 80)`,
and a blank intent shows as `step N`.

| Row and trail | Step lines | Progress | Footer (text, tone) |
|---|---|---|---|
| `listening`, `heard`, `held`, no trail | none | none | `status.text`, the status's tone |
| live, trail has no steps yet | none | none | `Working out the next step…`, active |
| `running`, a step is running | done `✓`, failed `✗`, running is `current` | `step N of M` | none |
| `running`, last step already ended (the model is thinking) | as above, no `current` | `step N of M` | `Working out the next step…`, active |
| a step failed, task goes on | that line is `failed`, text `<intent> · <failure>` | `step N of M` | as the two rows above |
| `done` | all done | `step N of M` | `status.text`, good |
| `failed`, `ending == .stepCap` | as they ended | `step M of M` | `Hit the M-step limit · try a smaller request`, bad |
| `failed`, `ending == .stuck` | as they ended | `step N of M` | `<status.text> · say it another way`, bad |
| `failed`, other (resolver error) with a trail | as they ended | `step N of M`, or none with no steps | `<status.text> · try again`, bad |
| `failed` with no trail (a grammar command) | none | none | `status.text`, bad |
| `stopped` | a step still running shows `stopped`, the rest as they ended | `step N of M` | `status.text`, muted |
| `ignored`, `dropped` | as they ended, if any | as above, if any | `status.text`, the status's tone |

- `N` is the newest step's number and `M` is the trail's `maxSteps`. `fraction` is `N / M`, clamped to 1. A finished
  task's bar stays where it stopped. It does not jump to full.
- A step still `running` on a final `done` row shows as done, and on a final `failed` row shows as failed. A step on
  a final row is never `current`.
- More than 8 steps: `lines` is the newest 8 and `earlierSteps` is how many were cut.

`.stuck` is set for `TaskOutcome.stuck`, and `.stepCap` when the reason is `TaskRunner.stepLimit`. Ending is carried
as data so the panel never parses `status.text`. The not-playing and repeating endings are `.stuck`.

## TaskRunner and pipeline

- `TaskRunner` gains `public var onTrail: ((TaskTrail) -> Void)?`, next to `onStatus`. It keeps one `TaskTrail`
  per `run`, built with the run's real `maxSteps` (so a media goal shows its longer cap).
- Emit points, each followed by `onTrail?(trail)`:
  - at the start of `run`, the empty trail;
  - beside `onStatus?(.running("step n · …"))`: `begin(number: n, intent: step.intent)`;
  - after `stepsRun = n`: `end(number: n, failure:)`, including a failure from a guard. **Skip this when `failure ==
    ActionExecutor.cancelled`,** so a stopped step stays running and the panel shows it as stopped;
  - in `finish`, before the final `onStatus`: set `trail.ending` for a `.stuck` outcome and emit.
- `.running("step N · …")` stays exactly as it is, so the board and the bar don't change.
- `VoicePipeline.runTask` sets `runner.onTrail` to report on the prompt's row and clears it afterwards, like
  `onStatus`. Stop handling is untouched: the panel only reads.
- `OverlayPresenting` gains `func report(_ id: Int, trail: TaskTrail)`. `FakeOverlay` records it. The CLI leaves
  `onTrail` nil.

## Panel (`OverlayController`)

- `taskPanel`, from the existing `makePanel()`: non-activating, ignores the mouse, can't become key or main, same
  level and Spaces behaviour as the others.
- `renderTaskPanel()` runs from `renderBoard()` next to `renderStatusBar()`, before the empty-board guard. It reads
  `board.visibleRows(now:)`, so every report and the board's own expiry redraw it, and the panel needs no timer. It
  replaces the content view only when the content or size changed, as the bar does.
- Hidden when `TaskPanelText.content` is nil, and whenever `state != .none` (grid or number badges up). It comes back
  when they hide. The full-screen badges and grid can't otherwise be kept clear.
- Placed at the bottom right of the visible frame (menu bar and Dock excluded) of the pointer's screen, 16 pt from
  the right and bottom edges. Width `min(340, screen width − 32)`. Height fits the content.
- **Keeping clear of the bar:** at the bottom position on a narrow screen the bar (up to 520 pt, centred) can reach
  the corner. If the frames intersect, the panel moves up by the bar height plus 6 pt.
- **Keeping clear of the board:** at most about 300 pt tall (8 steps, the earlier-steps line, two-line phrase and
  footer, the bar) against a board at most about 210 pt from the top, so they can't meet on any supported screen.
- View: the board's dark rounded fill and `BoardView.color(_:)` tones. Phrase at 14 pt medium, up to two lines. Step
  lines at 12 pt, one line each, truncated at the tail, with `✓` good, `✗` bad, `▸` plus a brighter weight for
  current, and `■` muted for stopped. Progress track with the label on its right. Footer at 12 pt, up to two lines,
  so a hint at the end of a long failure still shows.
- The bar is drawn only when `progress` is non-nil.

## Tests

Per `AGENTS.md`, one table per rule.

- `TaskPanelTests.swift` (Core): one table over the content table above, including done, running, failed step,
  held, stopped with a step still running, and step cap reached; a blank intent; more than 8 steps.
- Same file, row choice: a running row beats a held and a listening one; a task's outcome beats a newer listening
  and held row but not a heard one; a listening row beats a grammar command's outcome; `stopped` beats a newer
  `dropped`; a newer `done` grammar row beats an older task's row; no rows gives nil.
- `TaskTrail` and board: `begin`/`end` transitions, `end` on an unknown number, a trail report never changes a final
  row, a text and status report keeps the trail.
- `TaskRunnerTests` (Mac, existing fakes): the sequence of trails for a success, a failed step, a cancel mid-step
  (the step stays running), and the step cap (`ending == .stepCap`).
- Not tested: panel layout, colours, placement.

## Docs

- `README.md`: a **Corner panel** paragraph after **Status bar**.
- `docs/superpowers/specs/2026-11-04-nohands-design.md`: add the panel to the `OverlayController` line.
- No voice command, config key or menu item, so those tables don't change.

## Manual checks (listed in the PR, not claimed as passed)

1. "open YouTube and search for cats": the phrase appears, each step is listed as it runs with earlier ones ticked,
   the bar advances, and the outcome lingers about 6 s, then the panel hides.
2. A failed step is marked on its line. "stop" mid-task shows the step as stopped and the outcome `stopped`.
3. A request that reaches the cap (set `maxTaskSteps` to 2) shows `step 2 of 2` and the limit message.
4. "show numbers" and "grid" hide the panel, and "hide" brings it back. Status Bar ▸ Bottom on a narrow window size:
   the panel sits above the bar.
5. Clicks pass through and focus never moves. Two displays: the panel follows the pointer's screen on its next update.

## Calls I made

- **The panel hides when idle.** The ticket opens with "at all times" and also lets the implementer choose. The NH-66
  bar is already on screen at all times, so a second `Listening` would only repeat it. Say so at approval if you want
  the corner to show the bar's line when idle; it is a small change.
- **"worktrtee" in your request is read as the step trail** (the steps done so far). This is a reading of a typo, not
  confirmed.
- **A new corner panel next to the NH-66 bar, not a bigger bar.** The ticket's Scope says so, and it is not confirmed
  that this is what you meant. The other reading is growing the existing bar into this panel.
- **No off switch.** The ticket doesn't ask for one, and the Status Bar menu's Off doesn't affect the panel.
- **A prompt spoken during a task doesn't take over the panel.** The running task stays, and the board shows the held
  prompt.
- **A task's outcome holds for its 6 s against new words still being spoken, but not against a new prompt that has
  started.** So while an outcome lingers, the phrase you're starting to say shows on the board and the bar, and
  reaches the corner once it is heard.
- **"Updating while it is still being spoken" means the existing merge-window updates,** phrase by phrase as speech
  segments arrive, not word by word. There is no new partial transcription.
- **The bar counts the newest step that started,** so step 3 fills 3/12 while it runs, and it doesn't jump to full on
  done.
- **The panel hides while the grid or number badges are up,** even mid-task, because they cover the whole screen.
- **Grammar commands show too** (the phrase and outcome, with no steps or bar), since the panel is about the current
  prompt.
- **`Working out the next step…` shows between steps,** because the resolve is the slow part (5 to 20 s on a local
  model) and the panel would otherwise look stalled.
- **At most 8 steps are listed,** with `+ N earlier steps`, since the cap can be 30.
- **Failure hints:** `Hit the M-step limit · try a smaller request`, `· say it another way` for stuck, `· try again`
  for resolver errors. The existing failure text comes first, so a fix it already names stays.
- **Linger is the board's 6 s**, with no second timer.
- **Corner and size:** bottom right as the ticket defaults, 340 pt wide, 16 pt inset.
- **The ticket's check on PR #19:** the board is already on main, so this builds on main and PR #19 doesn't matter.
