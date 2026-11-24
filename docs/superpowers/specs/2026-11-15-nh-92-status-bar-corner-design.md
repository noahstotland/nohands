# NH-92: Move the status bar to the bottom-right corner and remove the always-on Listening line: Design

**Date:** 2026-11-15  **Ticket:** [NH-92](https://github.com/noahstotland/nohands/issues/92)
**Status:** Shipped
**Shipped:** in PR #127, as specified

## Intent

The status bar sat at the top or bottom and always showed something (idle: "Listening"). It moves to the bottom-right corner, by the corner task panel, and goes away when idle. Every other line stays.

Anti-goals: a stored `top` or `bottom` turning the bar off on upgrade; the bar overlapping the panel, a grid number or a badge; other status lines disappearing.

## Design

- **Position.** `StatusBarPosition` has `off` and `corner`. `stored(_:)` maps only `"off"` to `.off`; nil, old `"top"` and `"bottom"`, and unknown values map to `.corner`, so a corrupt default never hides the bar.
- **Line.** `StatusBarText.line` returns `StatusLine?`: `.listening` in `.command` with no live or final row is `nil`.
- **Drawing.** Off, or grid or badges drawn: hide at once and clear `shownStatusFrame`. `nil` line: `fadeOut` (the NH-118 helper, 0.35 s) and clear it. Otherwise the bar sits 16 pt (`taskPanelInset`) from the right and bottom of the pointer's screen, lined up with the panel.
- **Panel.** The corner panel already steps up by `statusBarHeight + 6` when it meets `shownStatusFrame`, so no new layout is needed as long as that frame is nil while the bar is hidden. The board drops its top-bar offset and sits 8 pt below the menu bar.
- **Menu.** The Status Bar submenu has Off and Bottom Right.

## Testing

Table-driven in `NoHandsCore`: idle command mode gives `nil` and other lines keep their text; `stored` maps everything but `"off"` to `.corner`. Placement is a manual check.

## Calls I made

- **The bar fades out when idle**, but hides at once for the grid and badges.
- **Menu label "Bottom Right"**, stored as `"corner"`.
- **The bar may repeat the running prompt the panel shows**; trimming it would change line texts, out of scope.
