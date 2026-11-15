# NH-110: Stop showing the step limit as the total in the task panel progress: Design

**Date:** 2026-11-15  **Ticket:** [NH-110](https://github.com/noahstotland/nohands/issues/110)
**Status:** Shipped
**Shipped:** in PR #125, as specified

## Intent

The corner panel says "step 2 of 24" for a task that finishes in 2 steps, because the number after "of" is the step limit (`maxTaskSteps` 12, `maxMediaTaskSteps` 24). NoHands decides one step at a time, so the real total is unknown. The panel should say only which step it is on.

## Goals and limits

- The progress line reads `step N` with no total, while a task runs and when it ends. The bar that fills toward the limit goes.
- The `Hit the N-step limit · try a smaller request` footer stays as it is.
- Non-goals: changing the step limits, estimating steps, the `(N steps)` count in the done line.
- No "of" in any state, no lost footer, no empty gap where the bar was.

## Design

- **Core** (`TaskTrail.swift`): `TaskPanelContent.Progress` keeps only `label`; `fraction` is removed. A `stepLabel(_:)` replaces `TaskPanelText.bar(_:of:)` and returns `step N`. On the step-limit failure the label is the last step's number, and the footer still names the limit from `trail.maxSteps`.
- **Panel** (`OverlayController.swift`): the progress row draws only the label, left-aligned, muted, at the same row height. The track and fill are removed.
- **README** § Corner panel: the step number with no total, and why.

## Tests

In `TaskPanelTests`: every `progress:` expectation becomes `step N` and none contains " of "; the label is `step 11` even when the trail's limit (5) is below it; the limit case keeps its footer and `.bad` tone.

## Calls I made

- The bar goes in every state, including the step-limit failure where it showed full. A lone full bar reads as noise, and the red footer already says the limit was hit.
- On the limit failure the label shows the last step's number, one rule for every state.
- `Progress.fraction` is deleted, so no caller can bring a bar back by accident.
