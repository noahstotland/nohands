# Window placement and flexible close-tab phrasing — Design

**Date:** 2026-11-04  **Status:** builder's calls (user asked for the outcome; session ran unattended)

## Intent

"Close the current tab" must close the Chrome tab, and "make the window half width and snap to the left side of
the screen" must move the frontmost window. Phrasing is free-form, so both the fast grammar and the model path
have to understand them; today the grammar knows only the literal "close tab", and the model has no action that
moves a window (measured: qwen2.5:7b invents key chords or a fake drag).

## Goals / non-goals

- **Goals:** common phrasings of close tab / close window hit the grammar (instant, no model); a `move_window`
  action both backends can emit; grammar fast paths for terse placements ("left half", "snap left", "maximize");
  the model maps rich phrasings to `move_window`; the executor moves the window through Accessibility.
- **Non-goals:** arbitrary pixel geometry or percentages ("make it 63% wide"); moving windows of apps that are
  not frontmost; multi-display targeting ("move it to the other screen").

## Approaches

1. **Prompt only** — teach the model to press macOS tiling shortcuts. Rejected: the shortcuts vary by macOS
   version and third-party tiling apps, and do nothing for the grammar path.
2. **Pixel geometry action** (`x, y, width, height`). Rejected for now: small models get numbers wrong and the
   request space the user named is the named halves/quarters/thirds.
3. **Named placement action** (`move_window` with a `placement` enum, applied to the focused window's screen
   visible frame via AX position/size). Chosen: deterministic, trivial for the model to emit, testable in core.

## Design

- Core: `WindowPlacement` (left/right/top/bottom half, four quarters, thirds, two-thirds, maximize, center) with
  a pure `frame(in:current:)`; `Action.moveWindow`; schema kind `move_window` with field `placement`; a few-shot
  example; decoder, summary, eval cases.
- Grammar: exact lookup retries with determiners/fillers stripped ("the", "this", "current", "to", …), so
  "close the current tab" becomes "close tab"; placement entries such as "left half", "snap left", "maximize".
- Mac: `ElementProviding` gains focused-window frame get/set and visible screen rects; AXQuery implements them;
  executor computes the target on the screen holding the window and sets position+size (+position again, since
  some apps clamp size before position).
- Left to the builder: exact word lists and README rows.
