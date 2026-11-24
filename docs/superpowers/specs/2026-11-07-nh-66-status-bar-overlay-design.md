# NH-66: Always-on status bar overlay — Design

**Date:** 2026-11-07  **Ticket:** [NH-66](https://github.com/noahstotland/nohands/issues/66)
**Status:** Shipped
**Shipped:** in PR #68, as specified

## Intent

The prompt board shows only while prompts are live, so "is it listening?" needs the menu. A one-line status bar stays on screen and says what NoHands is doing: listening, the running task and step, paused, asleep, loading, or the problem and its fix. On by default; a **Status Bar** submenu turns it off or moves it to the bottom.

## What the bar says

One pure function in `NoHandsCore`, `StatusBarText.line(menu:mode:rows:)`, returns text and tone. `rows` is the board's visible rows. First match wins:

1. Microphone denied, Needs Accessibility, or an error (with "choose Retry in the menu"): the fix text, tone bad.
2. Loading: `Loading speech model…` (waiting).
3. Paused: `Paused · Resume Listening in the menu` (muted).
4. A non-final row: `<prompt> · <status>` of the live row, picked running > heard > listening > held, newest first within a kind; the row's tone.
5. A final row still on the board: the most recently updated one.
6. Sleep: `Asleep · say wake up` (muted). Dictation: `Dictating · say stop dictating` (active).
7. Otherwise `Listening` (good).

- A finished task's final row shows for the board's 6 s linger, then `Listening`. No second timer.
- Problems and pause outrank a running row.

## Panel

- A separate non-activating, mouse-transparent `statusPanel` in `OverlayController`: dark capsule like the board, tone dot, one line of 13 pt text, 28 pt tall, 160 to 520 pt wide.
- Centred on the visible frame of the pointer's screen.
  - Top: 8 pt below the menu bar; the board starts below it.
  - Bottom: 8 pt above the Dock; the board stays put.
  - Off: panel hidden.
- Hidden while the grid or number badges show.
- Redrawn on every overlay change. It follows the pointer's screen only on redraw, so a display change can take up to 5 s.

## Setting

- `StatusBarPosition` (`off`, `top`, `bottom`); `stored(_:)` returns `.top` for nil or unknown.
- Stored in `UserDefaults` key `statusBarPosition`, not `config.json` (the app never writes it).
- Menu: **Status Bar** submenu `Off / Top / Bottom`, applied at once.
- No change to `VoicePipeline`, `TaskRunner` or `PromptBoard`.

## Tests

- One table over the priority rules (running beats held, a problem beats a running row, paused beats a stopped row, a final row beats idle) and the idle lines; one for `stored` defaults.
- Layout and the menu are manual checks listed in the PR.

## Leaves out

- Changing what the board shows or how long rows linger.
- Spoken status (NH-60), dragging, themes, per-display placement, a `config.json` key, a voice command.

## Calls I made

- It hides during grid and numbers: a top bar would cover toolbar badges.
- At the top it pushes the board down rather than defaulting to the bottom.
- Every row shows as `<prompt> · <status>`, a running task preferred over a held one.
