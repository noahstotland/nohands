# NH-59: Grammar for pointer and page control: Design

**Date:** 2026-11-16  **Ticket:** [NH-59](https://github.com/noahstotland/nohands/issues/59)
**Status:** Draft

## Intent

Dragging a file onto a folder, jumping to the top of a long page, making a page bigger and parking the pointer in the
middle of the screen are short, everyday asks. Today each one either goes to the model (slow, and impossible with the
model off) or takes several commands (`hold click`, `move to 12`, `release click`). This adds the missing phrases to
the on-device grammar.

## Goals, non-goals, anti-goals

Goals: the ticket's Scope and Acceptance, with the changes listed under Calls I made.

Non-goals: media and system phrases (#51, #52: `mission control`, `show desktop`, screenshots, spaces); tabs (#53);
text editing (#54); dragging by element name (`drag the report to the trash` stays with the model); macOS's own
accessibility zoom (option-command-equals); new model action kinds.

Anti-goals, which would make this a failure even if it works:

- A spoken `stop` (or `cancel`) leaves a mouse button held down, or no longer halts the running task.
- A drag that fails half way leaves the button down.
- `zoom 35` (the grid) changes meaning, or `zoom in` is read as a grid zoom.
- `go to the top of the document` and the other caret moves from NH-54 change meaning, or `scroll to <words>` stops
  finding words on the page.
- A phrase an app pack owns (Terminal's `scroll to top` and `scroll to bottom`) changes meaning inside that app.
- Any phrase in `docs/voice-commands.md` changes meaning or leaves the table.
- A new phrase touches the network or the model.

## What the code forces

- **The exact table wins after pack phrases** (`CommandGrammar.parse`), so the fixed phrases go there. `zoom in`
  today reaches the `zoom <n>` rule, fails `NumberWords.parse` and falls to the model; an exact entry catches it first
  and leaves `zoom <n>` alone.
- **`scroll to <words>` already knows the page edges.** `parseFind` declines `top`, `bottom`, `top of the page` and
  the rest of `scrollEdges` so they go to the model. Returning a chord there for the top and bottom forms covers every
  wording without new exact rows; the directions (`scroll to the left`) keep going to the model.
- **Packs are checked first**, so Terminal's `scroll to top` (Home) still wins inside Terminal. No other built-in pack
  (Mail, Messages, VS Code, Terminal) and no NH-52 phrase uses `drag`, `zoom in`, `zoom out`, `actual size`,
  `reset zoom`, `top of page`, `bottom of page` or `move to center`.
- **`Action.drag(from:to:)` already exists** for the model, with a harness path and a native path in
  `ActionExecutor+Harness.swift`. The native path posts move, down, move, up with no time between and no steps; Finder
  and most apps ignore a drag that arrives in one jump. It calls `input.mouseDown` directly, so a throw before the up
  leaves the button held (the executor only releases buttons it put in `pressed`).
- **A held button lives in `CGEventInputSynthesizer`** (`MouseButtonState`) across commands. Only `release click`, a
  task that ends badly, a pause or quit release it. A spoken `stop` with no task running is routed to
  `.ignore(reason: "stop")` and touches nothing, so after `hold click` a `stop` leaves the button down today.
- **`MoveTarget` has no screen-relative case.** The grammar can't know screen sizes; `TargetResolver.resolveMove`
  gets the screen rects and the cursor, so the centre is worked out there, in Core, and unit tested.
- **`parseClick` takes the count from the prefix**, so `double click 12` and `right click 12` already work. The
  ticket asks to verify and document it.

## Approaches

1. **Grammar entries plus one new move target (chosen).** Fixed phrases are exact entries; `drag <n> to <m>`,
   `click <n> and hold` and `move to center` are small additions to the existing click and move rules; the screen
   centre is a new `MoveTarget.screenCenter` resolved in `TargetResolver`. Stop releases a held button in the
   pipeline.
2. **Leave drags and the centre to the model.** No grammar work, but slow, needs a backend, and the model has no
   reliable way to name the screen centre.
3. **Expand `drag <n> to <m>` to `hold click` steps in the grammar** (move, press, move, release). Reuses existing
   actions, but a stop between the steps leaves the button held and the steps get no pacing.

## How it works

### Phrases (Core, `CommandGrammar`)

| Spoken | Action |
|---|---|
| `drag <n> to <m>`, `drag from <n> to <m>` | `.drag(from: .numbered(n), to: .numbered(m))`; both are numbers (label or grid cell, as `click 12`) |
| `click <n> and hold` | `.moveCursor(.numbered(n))`, `.pressMouse(.left)` |
| `top of page`, `top of the page` | command-up |
| `bottom of page`, `bottom of the page` | command-down |
| `scroll to top`, `scroll to the top`, `scroll to the top of the page` (every top form in `scrollEdges`) | command-up |
| `scroll to bottom`, `scroll to the bottom`, `scroll to the bottom of the page` | command-down |
| `zoom in` | command-equals (the key under `+`; browsers, Preview, VS Code and Terminal take it as zoom in) |
| `zoom out` | command-minus |
| `actual size`, `reset zoom` | command-0 |
| `move to center`, `move to centre`, `move to the center`, `move to the center of the screen` (and `centre`) | `.moveCursor(.screenCenter)` |
| `double click 12`, `right click 12` (existing) | Verified by a test row and listed in the table |

Rules:

- `drag` needs both numbers, split at the first `to` (`drag two to three` is 2 to 3). Anything else after `drag`
  (`drag the file to the trash`, `drag to 12`) returns nil and goes to the model as today.
- `click <n> and hold` takes a number only, left button only. `click save and hold` keeps today's meaning (clicks the
  element named "save and hold", which usually fails with `no element named …`); names are not added because the
  ordinal lookup that `click` does is not in `moveCursor`.
- `move to <n>` is unchanged; `center` and `centre` are not number words, so the new words can't shadow a number.
- `zoom in` and `zoom out` are browser zoom whether or not the grid is up. `zoom <n>` stays the grid.

### Screen centre (Core, `TargetResolver`)

`MoveTarget.screenCenter` resolves to the midpoint of the screen rect that contains the cursor, else the first screen,
else a failure `no screen` (never seen in practice; it keeps the resolver total). `IntentDecoder` does not produce it,
so the model can't ask for it. Other `MoveTarget` switches use `if case`, so only `TargetResolver` and any exhaustive
switch the build finds change.

### Drag (Mac, `ActionExecutor+Harness`)

The numbered endpoints resolve like `move to <n>`: against the shown labels or grid. With the harness the drag goes
through agent-desktop as the model's drag does. The native path changes for both the grammar and the model:

- move to the start, press, wait about 100 ms, move to the end in 10 steps about 15 ms apart (dragged events, from
  `MouseButtonState`), wait about 50 ms, release. The whole drag takes about a third of a second.
- any throw after the press releases the button before the failure is returned.
- a spoken stop during the drag: the drag is one action, so it runs to its release (a third of a second) and the
  task then stops. A drag never stops with the button down.
- the overlay is hidden after a drag that used it, as `click 12` does: the labels are stale once something moved.

### Stop releases a held button (Mac, `VoicePipeline`)

Any stop phrase (`StopWords.isStop`) now also releases a held mouse button, whether or not a task is running:
`executor.releaseHeldButton()` calls `input.releaseAll()` without hiding the overlay (so after `click 12 and hold`, a
`stop` releases and the grid stays up for the next try; `cancel` still hides it as today). The stop still halts the
task exactly as before, is still never merged, and still never starts a task. Releasing with nothing held does
nothing.

### What is reversible

- `click <n> and hold` holds a state, so it has spoken releases: `release click`, and now any stop phrase. Between
  them the user can say `move to 30`, `move down 100` or `move to center` and the moves are drags.
- To abandon a held drag without dropping it, say `escape` first (Finder and most apps cancel a drag on escape),
  then `release click` or `stop`.
- A drag that finished has moved something; `undo` takes it back where the app supports it (Finder's Undo Move,
  text editors, most canvas apps). NoHands can't undo it on its own, and the table says so.
- Zoom has its own reverse (`zoom out`, `actual size`); page top and bottom and the pointer moves change nothing.

### Docs

`docs/voice-commands.md` gets rows for every new phrase: a `drag 5 to 12` row, `click 12 and hold` added to the
`hold click` row with the stop release, the scroll and page edge phrases, the zoom phrases next to `zoom 35` with the
"grid vs page" note, `move to center` in the move row, and `double click 12`, `right click 12` in the `click 42` row.
The `scroll to <words>` row loses its "goes to the model" note. A line under the Terminal pack notes that `top of
page` presses command-up there (Terminal's own `scroll to top` still wins).

## Testing

Per `AGENTS.md` § Testing, table-driven, Core only:

- `CommandGrammarTests`: one table of every new phrase to its actions, plus rows that must not change (`zoom 35`,
  `move to 12`, `scroll to the left` is nil, `scroll to the budget` is a find, `go to the top of the document` is a
  caret move, `drag the file to the trash` is nil, `click save and hold` is the element, `double click 12`, Terminal's
  `scroll to top` still Home with the Terminal bundle id).
- `TargetResolverTests`: one table for `.screenCenter` (cursor on the second screen, cursor off every screen, no
  screens).
- Intent fixtures unchanged; `swift test` and the two fixture evals stay green.

Manual (listed in the PR, need Accessibility): `drag` a Finder file onto a folder with labels and with the grid,
`click 12 and hold` then `move to 30` then `stop`, `zoom in` and `actual size` in Safari, `top of page` on a long page,
`move to center` with two displays.

## Calls I made

- **`stop` now releases a held mouse button even with no task running.** The ticket did not ask for it; the task brief
  and the Product rules (a held state needs a spoken release, stop always works) do. It changes what `stop` does after
  `hold click` (today nothing) and keeps the overlay up.
- **The native drag gets pacing and steps**, which also changes the model's drags. Without it `drag 5 to 12` does
  nothing in Finder. The model's harness drag is unchanged.
- **New `MoveTarget.screenCenter`** rather than a pixel point in the grammar; grammar only, the model can't emit it.
- **`scroll to the top` and `scroll to the bottom` stop going to the model** and press command-up and command-down.
  The other `scroll to` edges (`left`, `right`, `up`, `down`) still go to the model.
- **Numbers only for `drag` and `click … and hold`**; names stay with the model.
- **`zoom in` is command-equals** (not shift-command-equals): it is what browsers bind and what the `+` key sends
  unshifted.
- **`top of page` in a focused text field moves the caret to the start** (command-up's meaning there). Not special
  cased.
- **Left out `drag to <m>` from the pointer** and `let go` as a release alias, to keep the table small.
- **`go to the top of the page` is not added.** Today it goes to the address bar via `go to <words>`; that is
  existing behaviour and out of this ticket's scope.
