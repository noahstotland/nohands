# NH-110: Stop showing the step limit as the total in the task panel progress: Design

**Date:** 2026-11-15  **Ticket:** [NH-110](https://github.com/noahstotland/nohands/issues/110)
**Status:** Draft

## Intent

The corner panel says "step 2 of 24" for a task that finishes in 2 steps, because the number after "of" is the step
limit (`maxTaskSteps` 12, `maxMediaTaskSteps` 24), not how many steps the task needs. NoHands decides one step at a
time, so nobody knows the real total. The panel should say only what is true: which step it is on.

## Goals, non-goals, anti-goals

Goals are the ticket's Scope and Acceptance: the progress line reads `step N` with no total, while a task runs and
when it ends; the bar that fills toward the limit goes; the `Hit the N-step limit · try a smaller request` footer stays
as it is.

Non-goals, from the ticket: changing `maxTaskSteps` or `maxMediaTaskSteps` or how many steps a task takes, estimating
the steps a task will need, changing the `(N steps)` count in the done line.

Anti-goals:

- Any label containing "of" after the step number, in any state.
- Losing the step-limit footer, or its tone.
- An empty gap in the panel where the bar used to be.

## Design

### Core (`Sources/NoHandsCore/TaskTrail.swift`)

- `TaskPanelContent.Progress` keeps only `label: String`; `fraction` is removed, since nothing draws a bar any more.
- `TaskPanelText.bar(_:of:)` is replaced by a `stepLabel(_ n: Int)` that returns `Progress(label: "step \(n)")`.
- While steps exist, the label is the last step's number, as today.
- On the step-limit failure the label is still the last step's number (no longer forced to `maxSteps of maxSteps`);
  the footer is unchanged and still names the limit from `trail.maxSteps`.
- `TaskTrail.maxSteps` stays: the limit footer uses it.

### Panel (`Sources/NoHandsMac/OverlayController.swift`)

- The progress row draws only the label, left-aligned, in the muted colour, at the same row height. The track, the fill
  and `trackHeight` (if nothing else uses it) are removed. `height(of:width:)` is unchanged: the row keeps one line.

### Docs

- `README.md` § Corner panel: the bar sentence becomes the step number (`step 3`) with no total, and why
  (NoHands decides one step at a time and cannot know how many remain).

## Tests

`Tests/NoHandsCoreTests/TaskPanelTests.swift`, existing table:

- Every `progress:` expectation becomes `step N` (for example `step 2`, `step 12` for the limit case).
- The table check adds that no progress label contains " of ".
- `taskPanelLines` drops the two `fraction` checks and checks the label is `step 11`, including when the trail's limit
  (5) is below the step count, which used to clamp the bar.
- The limit case keeps its `Hit the 12-step limit · try a smaller request` footer and `.bad` tone.

No new test file. `swift build` and `swift test` pass.

## Manual check (listed in the PR)

Run a two-step task in the app and see `step 1`, then `step 2`, no bar and no "of", and the panel's done line.

## Calls I made

- The bar is removed in every state, including the step-limit failure, where it used to show full. The ticket only
  says to drop it for a running task; a full bar at the end would be the only bar the user ever sees, so it reads as
  noise. The red footer already says the limit was hit.
- On the step-limit failure the label shows the last step's number rather than the limit. They are the same number in
  practice; using the step keeps one rule for every state.
- `Progress.fraction` is deleted rather than left unused, so no caller can bring back a bar toward the limit by accident.
- The label is left-aligned where the bar used to start, rather than right-aligned where it sat after the bar.
