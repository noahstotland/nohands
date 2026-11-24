# NH-32: A fun logo for the README and the menu bar — Design

**Date:** 2026-11-08  **Ticket:** [NH-32](https://github.com/noahstotland/nohands/issues/32)
**Status:** Shipped
**Shipped:** in PR #100, as specified

## Intent

NoHands gets a cheeky face to replace its placeholder logo and the `mic` menu-bar icon, because the name is a joke: look, no hands. The same logo goes in the README and the menu bar, and NH-33 builds the app icon from it.

## The logo

A round green winking face with a big open grin and its tongue out. No hands are drawn.

![Draft logo and menu-bar glyph](2026-11-08-nh-32-logo-preview.png)

- **Colour logo** (`assets/icon.svg`, 64 by 64): a disc in the placeholder's `#059669`, white eye, wink and grin, pink tongue (`#FB7185`). Plain shapes only, no fonts.
- **Menu-bar glyph** (`assets/menubar-icon.svg`, 18 by 18): one colour, with the eye, wink and mouth as holes in a solid disc. Details are thicker than a straight scale-down so they hold at 18 px.

Non-goals: the `.icns` app icon (NH-33), menu text and HUD copy, icon states.

Anti-goals: mocking missing hands or disability; a smudge at 1x or a shape that vanishes on a dark menu bar; the mode text moving; an empty menu item when the image is missing.

## Decision

A winking, tongue-out face: three features on a disc survive at 18 px. Rejected: a face on a microphone (the capsule is about 8 px wide, too small for an expression), and a hand with a cross or short arms (a prohibition sign reads as a warning). The menu-bar asset is committed PNGs at 1x and 2x, not a run-time SVG, so the 18 px version can be checked pixel by pixel.

## What changes

- `scripts/render-menubar-icon.swift` draws the glyph SVG through AppKit into `Resources/MenuBarIcon.png` (18 by 18) and `MenuBarIcon@2x.png` (36 by 36), keeping alpha. Run by hand; the PNGs are committed.
- `scripts/bundle.sh` copies both PNGs into `Contents/Resources` before signing.
- `AppDelegate.buildMenu()` loads `MenuBarIcon` as a template image at 18 by 18 with the accessibility description "NoHands", and falls back to `mic` when the image is missing (unbundled `swift run`).
- README line 1: `alt="NoHands logo"`.

## Testing

None (menu-bar layout is excluded by `AGENTS.md`). Manual: crisp at 1x and 2x, light and dark.

## Calls I made

- No hands or arms are drawn: arm or stump jokes would land on the people this app may help most.
- The glyph is 18 pt, the top of the ticket's 16 to 18 pt range, to give the wink room.
