# NH-33: A full-colour app icon: Design

**Date:** 2026-11-09  **Ticket:** [NH-33](https://github.com/noahstotland/nohands/issues/33)
**Status:** Proposed

## Intent

`NoHands.app` has no icon, so macOS shows the generic app icon wherever it draws the app. NH-32 gave NoHands a face, a
green winking disc with its tongue out. This ticket makes that face the app's icon, in the macOS icon shape and in every
standard size.

This is a small change: two pieces of art, one dev script, one plist key and one copy in `scripts/bundle.sh`.

## What the code forces

**NoHands never appears in the Dock or the Cmd-Tab switcher while it runs.** `Resources/Info.plist` sets `LSUIElement`
to true and `Sources/NoHands/main.swift` sets the `.accessory` activation policy. That is what makes it a menu-bar app,
and `README.md` says so ("no Dock icon"). The ticket's acceptance asks for the icon in the Dock and in Cmd-Tab, and an
icon alone can't deliver that.

This spec keeps NoHands a menu-bar app. Turning it into a Dock app would add a Dock tile and a Cmd-Tab entry to every
session, which is a product change the ticket doesn't ask for. See [Calls I made](#calls-i-made). The icon will show:

- in Finder (every view) and Get Info,
- in Launchpad, once the app is in `/Applications`,
- in the Dock, only as a tile the user pins by dragging the app there,
- in the app's own alerts, such as the Claude API key prompt from NH-94,
- in System Settings' privacy lists.

## The icon

![Chosen icon at 420, 128, 64, 32 and 16 pt on light and dark, then the 16 and 32 px renders enlarged, then the 16 px icon at 2x and at actual size](2026-11-09-nh-33-app-icon-preview.png)

The preview is a working draft, rendered through AppKit from the SVGs below and built into a test `.icns`. The lower row
shows the 16 px render and the 32 px render enlarged so the pixels are visible.

The NH-32 disc, unchanged in colour and features, sits on an off-white (`#F5F5F4`) rounded-square tile. The tile follows
Apple's macOS icon grid: an 824 px body centred on a 1024 px canvas, about 185 px corner radius, and a soft drop shadow
(28 px blur, 12 px down, 30% black, scaled with the size).

Two pieces of art, same face:

- **Main art** (`assets/app-icon.svg`, 1024 by 1024): used for every size except 16 px. Draft:

```svg
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <rect x="100" y="100" width="824" height="824" rx="185" fill="#F5F5F4"/>
  <g transform="translate(512 512) scale(12.2) translate(-32 -32)">
    <circle cx="32" cy="32" r="29" fill="#059669"/>
    <circle cx="21" cy="24" r="5.5" fill="#fff"/>
    <path d="M37 24.5 Q43.5 16.5 50 24.5" fill="none" stroke="#fff" stroke-width="5" stroke-linecap="round"/>
    <path d="M15 36 H49 Q48 53 32 53 Q16 53 15 36 Z" fill="#fff"/>
    <path d="M33 42 H45 V52 A6 6 0 0 1 33 52 Z" fill="#FB7185"/>
  </g>
</svg>
```

- **16 px cut** (`assets/app-icon-small.svg`, 16 by 16): used only for the 16 px image, the Finder list view at 1x. A
  straight scale-down smears the wink, as the NH-32 menu-bar glyph also found. This cut drops the grid margin and the
  shadow, and thickens the eye, wink, mouth and tongue. Draft:

```svg
<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">
  <rect x="0.5" y="0.5" width="15" height="15" rx="3.4" fill="#F5F5F4"/>
  <circle cx="8" cy="8" r="7" fill="#059669"/>
  <rect x="4" y="4.25" width="2.5" height="2.5" rx="1.25" fill="#fff"/>
  <path d="M9.25 6.5 Q10.75 3.9 12.25 6.5" fill="none" stroke="#fff" stroke-width="1.5" stroke-linecap="round"/>
  <path d="M3 8.5 H13 C13 11.6 11 13.5 8 13.5 C5 13.5 3 11.6 3 8.5 Z" fill="#fff"/>
  <rect x="8.5" y="10" width="3" height="4" rx="1.5" fill="#FB7185"/>
</svg>
```

## Goals, non-goals, anti-goals

Goals are the ticket's Scope and Acceptance, with the Dock and Cmd-Tab limits above.

Non-goals, from the ticket: designing or changing the logo, the README or the menu-bar icon; a dark or tinted variant or
an Icon Composer `.icon` file; signing, notarisation or a release pipeline. Also not here: any change to `LSUIElement`
or the activation policy.

Anti-goals, which would make this a failure even if the build passes:

- The tile or the face drawn differently enough that it stops looking like the NH-32 logo.
- A smudge in Finder list view.
- `scripts/bundle.sh` gaining a dependency or a slow step, or failing on a machine without design tools.
- The icon copied after `codesign`, which would break the signature that Accessibility trust is tied to.

## Approaches

Rendered and compared in a spike, all three at 1024, 64, 32 and 16 px:

1. **The disc on an off-white tile (chosen).** The only option that keeps the logo's round silhouette and its contrast.
   It reads on light and dark backgrounds, and matches the README and the menu bar.
2. **The face directly on a green tile.** The boldest at small sizes, but the disc is gone and the logo becomes a
   square-headed face, so it fails "recognisably the NH-32 logo".
3. **The disc on a deep green tile (`#064E3B`).** Keeps the disc, but the two greens merge at 16 and 32 px and the face
   looks muddy.

For delivery, two options: commit the `.icns` and regenerate it by hand, or build it in `scripts/bundle.sh`. Committing
follows what NH-32 did for the menu-bar PNGs, and the build gains no step.

## What changes

- `assets/app-icon.svg`, `assets/app-icon-small.svg`: new, the source art above.
- `scripts/render-app-icon.swift`: new, a dev script in the style of `scripts/render-menubar-icon.swift`, run by hand
  when the art changes. It draws the SVGs through AppKit into a temporary `.iconset` (10 files, 16 to 512 pt at 1x and
  2x), adds the shadow to every size but 16 px, runs `/usr/bin/iconutil` and writes `Resources/AppIcon.icns`. It needs no
  new tools.
- `Resources/AppIcon.icns`: new, committed output of that script.
- `Resources/Info.plist`: `CFBundleIconFile` set to `AppIcon`.
- `scripts/bundle.sh`: copies `Resources/AppIcon.icns` into `Contents/Resources` with the other resources, before the
  `codesign` step.

## Testing

No unit tests. `AGENTS.md` § Testing excludes layout and framework behaviour, and this change has no logic.

- `swift build` and `swift test` pass.
- After `scripts/bundle.sh`: `Contents/Resources/AppIcon.icns` exists, the bundled plist has `CFBundleIconFile`,
  `codesign --verify --deep --strict` passes, and the `.icns` expands back into all 10 sizes.
- Manual, listed in the PR: the icon shows in Finder list and icon views, Get Info and a pinned Dock tile, and the face
  reads by eye at list-view size.

## Left to the builder

Pixel nudges to the art that keep the concept, the script's arguments, and any step needed to get past a stale icon in
Finder's cache when checking by eye.

## Calls I made

- **NoHands stays a menu-bar app, so the running app gets no Dock tile and no Cmd-Tab entry.** This narrows the ticket's
  acceptance. The icon can only reach those two places if `LSUIElement` and the `.accessory` policy go, which changes how
  the app behaves every day and contradicts the README. If you do want NoHands in the Dock and Cmd-Tab, say so and it
  becomes part of this spec or a new ticket.
- **The tile is off-white, with the green disc on it,** rather than a green tile. The ticket left the adaptation open.
- **A separate, thicker drawing is used at 16 px**, the same answer NH-32 reached for the menu bar. Editing the logo now
  means editing two icon files, plus the NH-32 art.
- **The `.icns` is committed** and regenerated by a hand-run script, as NH-32 did with its PNGs.
- **Corners are a plain 185 px rounded rectangle**, not Apple's continuous curve. The difference is small and SVG `rx` is
  the simple way to draw it.
- **A preview image is committed next to this spec**, as NH-32 did, so the icon can be judged from GitHub.
- **Checked only on macOS 14.** macOS 26 can redraw older-style icons inside its own tile. The ticket rules out an Icon
  Composer file, so that look is left as it falls.
