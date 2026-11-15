# NH-118 plan: thinking phase line, spinner, fades

Spec: [design](../specs/2026-11-15-nh-118-thinking-progress-design.md). Follow it exactly; this is only the task order.

## Task 1: Core data and text (NoHandsCore)
- `TaskPhase` enum; `TaskTrail.phase`; `TaskStepRecord.actions`; `TaskTrail.begin(number:intent:actions:)`.
- Payload-free acting verb per `Action` (next to `ActionSummary`); `TaskPanelText.phaseLine`; `TaskPanelContent.busy`; footer = phase line while busy; stopped rows never chosen for the panel.
- `PromptBoard` linger per status (done 1.5 s, failed/dropped 3 s, ignored 1.5 s, stopped 1.5 s).
- Table-driven tests only (phaseLine, content busy/footer/stopped, linger). Fix existing tests the changes break; never edit intent fixture expectations.
- Verify: `swift build && swift test`.

## Task 2: Runner reports phases (NoHandsMac)
- `TaskRunner.run` sets `trail.phase` and calls `onTrail` per the spec table; board row `.running(phaseLine)` before the first step. Resolvers unchanged. Add a runner phase-order test only if an existing test already captures `onTrail`.
- Verify: `swift build && swift test`.

## Task 3: Overlay drawing and fades (NoHandsMac)
- Spinner (CAShapeLayer, 270deg arc, 1 turn/s) on the phase line when `busy`; current-step mark becomes a static dot; bar 3 pt.
- `show`/`fadeOut`/hide-at-once helper with per-panel generation counter; apply to corner panel, board, status bar (fade-in only); stopped panel and grid/badge hides are immediate.
- Verify: `swift build && swift test`. Look/fade are manual checks, not tests.
