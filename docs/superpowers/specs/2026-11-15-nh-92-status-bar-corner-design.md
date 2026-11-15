# NH-92: Move the status bar to the bottom-right corner and remove the always-on Listening line: Design

**Date:** 2026-11-15  **Ticket:** [NH-92](https://github.com/noahstotland/nohands/issues/92)
**Status:** Shipped
**Shipped:** in PR #127, as specified

## Intent

The status bar sits centred at the top of the screen (or bottom) and is never empty: when nothing is going on it
reads "Listening". This change moves it to the bottom-right corner, next to the corner task panel, and lets it go
away when there is nothing to say. Every other line it shows today stays.

## Goals, non-goals, anti-goals

Goals are the ticket's Scope and Acceptance.

Non-goals, from the ticket: a new logo or menu-bar image (#32), any change to the menu-bar item (mic image and
`CMD`/`DICT`/`ZZZ` text), new wording or colours for the other status lines.

Anti-goals, which would make this a failure even if it works:

- A user upgrading with a stored `top` or `bottom` who finds the bar turned off.
- The bar and the corner panel drawn over each other.
- The bar covering a grid number or a badge (it still hides at once for them).
- "Dictating", "Asleep", "Paused", loading, or a permission or error line that no longer shows.

## What the code forces

- `StatusBarText.line` returns a non-optional `StatusLine`; the idle case needs it to return `nil`, so the one caller
  (`OverlayController.renderStatusBar`) gains a hide branch.
- `renderTaskPanel` already steps up by `statusBarHeight + 6` when its frame meets `shownStatusFrame`. A bar in the
  corner always meets it, so the step-up keeps the two apart with no new layout code, as long as `shownStatusFrame`
  is nil while the bar is hidden (otherwise the panel would float above an empty gap).
- `setAppState` only calls `renderStatusBar` when the state didn't change, and `renderBoard` (which also redraws the
  panel) when it did. The bar appears or goes away only on a state change or a board change, both of which reach
  `renderBoard`, so the panel is repositioned after the bar in the same pass.
- `visibleBoundsCG` already excludes the Dock and the menu bar, so 16 pt inside it is clear of the Dock on any side.

## Design

### Position (NoHandsCore)

```swift
public enum StatusBarPosition: String, CaseIterable, Sendable {
    case off, corner
    /// "off" means off; anything else (nil, "top", "bottom", unknown) means the corner.
    public static func stored(_ raw: String?) -> StatusBarPosition
}
```

`stored` maps only `"off"` to `.off`. A missing value, the old `"top"` and `"bottom"`, and any unknown value map to
`.corner`, so the default stays on and no upgrade turns the bar off. The app keeps the `statusBarPosition` user
default key and writes `"corner"` or `"off"`.

### Line (NoHandsCore)

`StatusBarText.line(menu:mode:rows:) -> StatusLine?`. Unchanged except the last case: `.listening` + `.command` with
no live or final row returns `nil`. Problems, loading, paused, prompt rows, "Asleep · say wake up" and
"Dictating · say stop dictating" return what they return today.

### Drawing (NoHandsMac)

`renderStatusBar()`:

- Off, or the grid or badges drawn: hide at once (as today), clear `shownStatus` and `shownStatusFrame`.
- `line` is nil: `fadeOut` the panel (the NH-118 helper; this is an ordinary hide, not one for the grid), clear
  `shownStatus` and `shownStatusFrame`.
- Otherwise: same width rule as today, origin
  `x = screenCG.maxX - 16 - width`, `y = screenCG.maxY - 16 - height` on the pointer's screen
  (`taskPanelInset`, so the bar's right edge lines up with the corner panel's).

`renderBoard()` drops the top-bar offset: the board always sits 8 pt below the menu bar, where it sits today with the
bar off. The corner panel keeps its step-up, which now always puts it directly above a shown bar with a 6 pt gap.

### Menu (NoHands)

The Status Bar submenu has two items, **Off** and **Bottom Right**, built from `StatusBarPosition.allCases` with a
title per case. The checkmark and the saved value work as today.

### Docs

- `README.md` § Status bar: no `Listening` line; it shows only when there is something to say; bottom-right of the
  pointer's screen, below the corner panel; the menu chooses Off or Bottom Right; a stored Top or Bottom becomes
  Bottom Right.
- `docs/superpowers/specs/2026-11-04-nohands-design.md`: the Status Bar menu line reads Off / Bottom Right and drops
  "always-on".

## Testing

Table-driven, in `NoHandsCore`:

- `statusBarLine`: idle command mode gives `nil`; every other existing case keeps its expected text (sleep,
  dictation, loading, running, held, heard, final rows, problems, paused, tone).
- `statusBarPositionStored`: `nil`, `""`, `"top"`, `"bottom"`, `"middle"`, `"corner"` give `.corner`; `"off"` gives
  `.off`.

Not tested (manual, listed in the PR): the bar's place on screen, on a second display, with the Dock on the right,
next to the corner panel, and hiding for the grid and badges; the menu-bar item unchanged; the submenu.

## Calls I made

- **The bar fades out when it goes idle** (0.35 s, the NH-118 helper) instead of cutting. It still hides at once for
  the grid and badges. NH-118 said the bar "only fades in" because it never went idle; now it does.
- **Menu label "Bottom Right"**, stored as `"corner"`. Off stays.
- **Every stored value except `"off"` means on**, including unknown ones, so a corrupt default never hides the bar.
- **16 pt from the right and bottom of the visible area** (inside the Dock and menu bar), the corner panel's inset,
  so the two right edges line up.
- **The bar may repeat the running prompt the corner panel also shows.** The ticket keeps every line as is; trimming
  that overlap would change the line texts, which it puts out of scope.
- **The board stays at the top centre**, 8 pt below the menu bar, where it already sits with the bar off.
