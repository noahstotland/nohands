# NH-118: Show what the model is thinking, with a progress indicator that fades out: Design

**Date:** 2026-11-15  **Ticket:** [NH-118](https://github.com/noahstotland/nohands/issues/118)
**Status:** Shipped
**Shipped:** in PR #123, as specified

## Intent

While a task runs, the corner panel says the same thing for the whole wait ("Working out the next step…"), its marks
and bar never move, and every panel vanishes with a hard cut 6 s after the result. This change adds a small phase
(reading the screen, thinking, acting) that the runner reports, one line on the panel that says it in plain words, one
quiet animated indicator while work is in flight, and fades instead of cuts.

## Goals, non-goals, anti-goals

Goals are the ticket's Scope and Acceptance.

Non-goals, from the ticket: streaming the model's reasoning, any change to the intent schema or a new field the model
fills in, the "of N" total and the bar's meaning (#110), moving the status bar (#92), menu-bar and HUD copy beyond the
phase line.

Anti-goals, which would make this a failure even if it works:

- A spoken "stop" that leaves the panel on screen, or a fade that runs after the stop.
- A panel that fades out and then pops back (a new report arriving mid-fade must cancel the fade, not race it).
- Typed text, URLs or search words shown in the phase line (the line is payload-free; see [Phase text](#phase-text)).
- A timer that redraws the panel many times a second. The animation runs on a Core Animation layer, not by redrawing.
- Anything in `NoHandsCore` that imports AppKit or Core Animation.

## What the code forces

- **The model's step is not about the model's next move.** `IntentStep.intent` restates the user's goal, and the
  schema can't change. So while the model is thinking there is no model text about what it's doing. The words after
  the dot come from the current step's *actions* while acting, and from a fixed line chosen by context while reading or
  thinking. "Deciding which button to click" can't be known before the model answers; the ticket allows the fixed line.
- **Every model-bound command in the app is already a task.** `VoicePipeline.process` turns `.resolveWithLLM` into a
  `PendingTask`, and `TaskRunner.run` calls `onTrail` before the first screen read. So the "one-shot command" case is
  the same path: the panel shows the phase line from the start. The bare "running…" the ticket mentions is the board
  row, which reads "heard" until the first step starts. That row follows the phase too (see [Board row](#board-row)).
- **Panels are redrawn by replacing `contentView`.** `renderTaskPanel` swaps in a new `TaskPanelView` whenever the
  content changes. The indicator's animation must survive that or restart cleanly; a layer animation that starts in
  the new view does this.
- **`orderOut(nil)` is called from three render paths** (`renderBoard`, `renderStatusBar`, `renderTaskPanel`), and
  `renderBoard` runs again on every report. Fading needs one helper that knows if a panel is mid-fade.

## Design

### Phase (NoHandsCore)

`TaskTrail` gets `public var phase: TaskPhase?`, with

```swift
public enum TaskPhase: Equatable, Sendable { case reading, planning, thinking, acting }
```

`TaskStepRecord` gets `actions: [Action]` (the step's actions after `TypedAddressGuard.rewrite`), so the acting line
can name what is being done. `TaskTrail.begin` takes them.

`TaskRunner.run` sets the phase and calls `onTrail` at each change. The runner is shared by `ClaudeIntentResolver` and
`OllamaIntentResolver`, so both backends get it with no resolver change:

| Moment in `run` | Phase |
|---|---|
| Start, before the first observation | `reading` |
| Before `askForPlan` | `planning` |
| Before each `resolveCancellable` (and the stuck-then-picture retry) | `thinking` |
| `trail.begin` for a step (model or plan) | `acting` |
| After a step ends, before `settle` | `reading` |
| `finish` | `nil` |

A plan step skips `thinking` (no model call). No new action type; the decoder and the guards are untouched.

### Phase text

A pure `TaskPanelText.phaseLine(_ trail: TaskTrail) -> String?` picks the words. nil when there's no phase.

| Phase | Condition | Line |
|---|---|---|
| reading | no steps yet | Reading · looking at the screen |
| reading | after a step | Reading · checking what changed |
| planning | | Thinking · planning the steps |
| thinking | no steps yet | Thinking · working out the first step |
| thinking | last step failed | Thinking · finding another way |
| thinking | otherwise | Thinking · picking the next step |
| acting | running step has actions | Acting · *verb of its first action that does something* |
| acting | no actions, or only `look`/`wait` | Acting · step *N* |

The acting verbs are payload-free, like `ActionSummary` (typed text, URLs and search words are private):
clicking, typing, pressing keys, scrolling, moving the pointer, opening an app, opening a page, searching, switching
tabs, closing a tab, picking from a menu, filling in a field, dragging, reading the screen, waiting. One function maps
each `Action` case to one of these; it lives next to `ActionSummary`.

### Panel content (NoHandsCore)

`TaskPanelContent` gets `busy: Bool`: true while the row is not final and the trail has a phase. While busy, the footer
is the phase line (tone active), replacing the fixed `thinking` string and the "nil while a step runs" rule. The
current step's line keeps its text and gets a plain mark (see below). Final rows keep today's footers.

A stopped row is never chosen for the panel: `TaskPanelText.content` skips rows whose status is `.stopped`. The panel
then hides *at once*, with no fade (see [Fades](#fades)).

### Indicator (NoHandsMac)

- One small spinner: a 10 pt open arc (about 270°), 1.5 pt stroke, active-tone colour, rotating once a second on a
  `CAShapeLayer` with a repeating `CABasicAnimation`. It sits in the mark column of the phase line and exists only when
  `busy` is true, so it stops when the task is done, failed or stopped.
- The current step's `▸` becomes a small filled dot in the active colour, static. Done, failed and stopped marks stay.
- The bar stays a static fill showing "step N of M" (its meaning belongs to #110). It is drawn slimmer (3 pt, rounded)
  so the spinner is the only thing that moves.

### Fades

One helper in `OverlayController`, `show(_ panel:)` / `fadeOut(_ panel:)`:

- Show: a hidden panel starts at alpha 0 and animates to 1 over 0.15 s. A panel that is mid-fade-out is set back to
  alpha 1 and its fade is cancelled (a per-panel generation counter: the fade's completion orders out only if no show
  came after it).
- Fade out: alpha to 0 over 0.35 s, then `orderOut`.
- Hide at once: `orderOut` and alpha reset, no animation. Used for the stopped task panel, for any hide while the grid
  or number badges are drawn (the status bar and panel must never sit over a badge), and by `hide()` paths that
  today cut on purpose.

Applied to the corner panel, the board, and the status bar when it hides for a reason other than the grid or badges.
The status bar doesn't hide when a task ends (its text changes), so in practice it only gets the fade-in.

### Linger

`PromptBoard` lingers by outcome instead of one 6 s `finalLinger`:

| Status | Linger |
|---|---|
| done | 1.5 s |
| failed, dropped | 3 s |
| ignored | 1.5 s |
| stopped | 1.5 s (the board row; the panel already skipped it) |

With the 0.35 s fade, a done task's panel is gone about 1.9 s after the result.

### Board row

Until the first step starts, `TaskRunner` reports the phase line as the row's `.running` detail (so the row reads
"Thinking · working out the first step", not "heard"). Once a step starts, the row keeps today's "step N · intent"
line. `TaskPanelText.phaseLine` is the one source for both.

## Testing

Table-driven, in `NoHandsCore` only:

- `phaseLine`: every row of the [Phase text](#phase-text) table, including no phase, no steps, a failed last step, a
  running step with no actions, a `look`-only step, and a typed-text step (the line must not contain the text).
- `TaskPanelText.content`: `busy` and the footer for running, done, failed and stopped rows; a stopped row is never
  chosen (another visible row is chosen, or nil).
- `PromptBoard` linger per status.

The runner's phase order is checked with the existing fake resolver in `TaskRunnerTests` if one of its tests already
captures `onTrail` (one table of expected phases per scenario: model step, plan step, cancel); otherwise skipped.

Not tested (manual, listed in the PR): the spinner, the fade timings and the look, with Claude and with the local
model, and "stop" mid-task clearing the panel at once.

## Calls I made

- **A stopped task's panel vanishes with no fade.** The ticket says stop "clears the panel at once"; I read that as no
  "stopped" panel at all, rather than a short linger. The board row still shows "stopped" for 1.5 s.
- **Failures linger 3 s, done 1.5 s.** Failure lines name what to do next (product rule) and need reading time;
  the ticket's "a second or two" fits done.
- **The bar stays.** The ticket says to replace "the `▸` mark and the static bar" with one indicator; I keep the bar
  (static, slimmer) because its label "step N of M" is the only place the step count shows and #110 owns its meaning.
  The spinner is the one moving thing.
- **No model text while thinking.** The words come from fixed per-context lines, because the schema can't change and
  `intent` restates the user's goal.
- **Acting words are verbs only,** no element names, typed text or URLs, so the line never shows private text.
- **Phase words:** "Reading", "Thinking", "Acting", joined to the detail by " · ".
- **Planning shows as "Thinking · planning the steps"**, a fourth phase in data so the text can differ.
- **The board row shows the phase only before the first step;** after that it keeps "step N · intent".
- **Timings:** fade in 0.15 s, fade out 0.35 s, spinner one turn per second.
- **The status bar only fades in;** it still hides at once for the grid and badges so it never covers one.
