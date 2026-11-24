# NH-118: Show what the model is thinking, with a progress indicator that fades out: Design

**Date:** 2026-11-15  **Ticket:** [NH-118](https://github.com/noahstotland/nohands/issues/118)
**Status:** Shipped
**Shipped:** in PR #123, as specified

## Intent

The corner panel said the same thing for the whole wait, its marks and bar never moved, and every panel vanished with a hard cut 6 s after the result. This adds a phase (reading, planning, thinking, acting) that the runner reports, one plain-words line on the panel, one quiet animated indicator while work is in flight, and fades instead of cuts.

Non-goals: streaming the model's reasoning; any schema change; the bar's meaning (#110); moving the status bar (#92).

Anti-goals: a panel left on screen after "stop"; a panel that fades out and pops back (a new report mid-fade cancels the fade); typed text, URLs or search words in the phase line; a timer redrawing the panel.

## Constraints

- `IntentStep.intent` restates the user's goal and the schema can't change, so there is no model text about its next move. The line comes from the step's actions while acting and a fixed line by context otherwise.

## Design

### Phase (NoHandsCore)

`TaskTrail.phase` is `reading`, `planning`, `thinking`, `acting` or nil. `TaskStepRecord` keeps the step's actions. `TaskRunner` (shared by both resolvers) sets it: `reading` at the start and after each step, `planning` before `askForPlan`, `thinking` before each model call (a plan step skips it), `acting` when a step begins, nil at `finish`.

### Phase text

`TaskPanelText.phaseLine` returns `<Phase> · <detail>`:

- Reading: "looking at the screen", or "checking what changed" after a step.
- Planning: "planning the steps".
- Thinking: "working out the first step", "finding another way" after a failed step, else "picking the next step".
- Acting: a payload-free verb for the running step's first action that does something ("clicking", "typing", "searching"), else "step N".

The board row shows the phase line before the first step; after that it keeps "step N · intent".

### Panel content

- `TaskPanelContent.busy` is true while the row is not final and the trail has a phase. While busy the footer is the phase line.
- A `.stopped` row is never chosen for the panel. A spoken stop marks every row it leaves `.stopped`. The panel hides at once with no fade.

### Indicator (NoHandsMac)

- A 10 pt open arc (about 270°), 1.5 pt stroke, active colour, rotating once a second on a `CAShapeLayer`, only while `busy`.
- The current step's mark is a static filled dot. The bar stays a static "step N of M" fill, slimmer (3 pt), so the spinner is the only moving thing.

### Fades and linger

- `OverlayController` fades in over 0.15 s and out over 0.35 s. A panel mid-fade-out snaps back to full alpha, and a per-panel generation counter stops the old fade from ordering it out.
- Hide at once for the stopped panel and whenever the grid or number badges are drawn.
- `PromptBoard` lingers by outcome instead of 6 s: done, ignored and stopped 1.5 s; failed and dropped 3 s.

## Testing

Table-driven in `NoHandsCore` (phase text, panel choice, linger). Spinner and fade look are manual.

## Calls I made

- A stopped task's panel vanishes with no fade (the ticket says "at once"); the board row still shows "stopped" for 1.5 s.
- Failures linger 3 s because their lines say what to do next.
- The bar stays (static, slimmer) though the ticket says to replace it: its "step N of M" label is the only place the count shows.
