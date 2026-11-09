# NH-75: Fix the always-on status bar not showing on screen — Design

**Date:** 2026-11-08  **Ticket:** [NH-75](https://github.com/noahstotland/nohands/issues/75)
**Status:** Draft

## Intent

The status bar from NH-66 was reported as not appearing when the app runs. The ticket did not know why. This spec
records what the investigation found and fixes the two things that can make the bar missing.

## What the investigation found

**The bar works on current `main`.** A throwaway harness ran the real `OverlayController` from `d525aab` in an
`.accessory` app, with no microphone or Accessibility, on this Mac's 1512×982 notched built-in screen with the
menu bar set to auto-hide. It read the app's on-screen windows back from the window server:

| Step | On screen |
|---|---|
| Launch, `.loading` | Bar at x=658, y=40, 195×28, 8 pt below the notch |
| `.listening` | Bar at x=676, y=40, 160×28 |
| Bottom | Bar at y=946 |
| Top | Bar at y=40 |
| Off | No window |
| Grid up | Only the full-screen grid |
| `hide()` | Bar back at y=40 |

**The likely cause is that the app that was run did not contain the bar.** No `NoHands.app` on this Mac has the
code:

| Bundle | Built | Has the bar |
|---|---|---|
| `~/.t3/projects/nohands-voice-control/build/` | Nov 8 21:24, two minutes after NH-70 merged | No. That checkout is on `feat/voice-control`, 79 commits behind `origin/main`, with no `StatusBar.swift` |
| `~/.t3/projects/nohands/build/` (root checkout) | Nov 4 | No. It predates NH-66 |
| Three worktree builds | Nov 4 | No. They predate NH-66 |

The `statusBarPosition` string is absent from the newest bundle and present in a fresh `swift build` of `main`.
The `dev.nohands.app` defaults domain does not exist, so Off was never stored.

The rest of the ticket's checklist:

- **Stored `statusBarPosition`:** ruled out, as above.
- **Notch or auto-hidden menu bar covering the bar:** ruled out. `visibleFrame` stops at the safe area, so the bar
  sits at y=40 and the notch ends at y=32.
- **Panel not ordered front:** ruled out on a single screen. Several screens were not tested.
- **`state` left at `.grid` or `.labels`:** one real case, below.

**A real bug, smaller than the report.** "Show numbers" with nothing to label sets `state` to `.labels([:])`. No
badges are drawn, and the bar still hides because `statusBarShown` only checks `state == .none`. The harness
confirmed it: no window on screen until `hide()`. The bar stays gone until "hide" or the next action that clears
the overlay.

**What could not be checked.** The unified log has no `NoHands` entries and the app was not running, so nothing
shows which bundle was launched when the bar was missing. The bundled app was not launched, because that raises
Microphone and Accessibility prompts and starts listening.

## Changes

### 1. The bar hides only when something is drawn (`OverlayController`)

`statusBarShown` hides the bar only while the grid panel or at least one badge panel exists:

```swift
private var overlayDrawn: Bool { gridPanel != nil || !labelsPanels.isEmpty }
private var statusBarShown: Bool { statusBarPosition != .off && !overlayDrawn }
```

`state` keeps its meaning, so target resolution and `hideStaleOverlay` do not change. Badges that are drawn still
hide the bar, and so does the grid.

### 2. `scripts/bundle.sh` warns about a stale checkout

Before building, the script does a best-effort `git fetch --quiet origin main`, ignoring failure so an offline
build still works. If `origin/main` is not an ancestor of `HEAD`, it prints one line naming the branch and how many
commits it is behind:

```
warning: building feat/voice-control, 79 commits behind origin/main. Features merged since then will be missing.
```

It never stops the build, because building a branch is normal. Outside a git repo it stays silent.

### 3. README

One sentence next to the build command in `README.md`: build from an up-to-date `main` to get the latest features,
and `bundle.sh` warns when the checkout is behind.

## Tests

No new unit test. The cause is not in `NoHandsCore`, as the ticket allows for, and the change is AppKit panel
state. `swift test` and `swift build` must stay green.

## Manual check (listed in the PR)

From this branch, `scripts/bundle.sh && open build/NoHands.app`, then:

1. On a fresh launch at the default setting, the bar is at the top and says "Loading speech model…", then
   "Listening".
2. Off hides it; Top and Bottom move it.
3. "Show grid" and "show numbers" hide it, and "hide" brings it back.
4. "Show numbers" in an app with nothing to label leaves the bar up.
5. In a checkout behind `main`, `bundle.sh` prints the warning and still builds.

If step 1 fails on a build that does contain the bar, the cause is something the harness could not see. The build
then stops with `BLOCKED:` and what was observed, without guessing at another fix.

## Leaves out

- New bar content or styling, and the NH-70 corner panel (ticket out of scope). The corner panel has the same
  `state == .none` check and is left as is.
- Making the bar follow the pointer between screens when nothing else redraws it.
- A build version or commit shown in the menu.
- Failing the build on a stale checkout.

## Calls I made

- **Treated the stale build as the main cause, and shipped a warning rather than only closing the ticket.** The
  ticket says to find the cause and fix it. The cause is outside the app code, so the fix that addresses it is in
  the build script.
- **Added a `bundle.sh` change the ticket did not list.** It is about 8 lines and does not touch the app.
- **The warning does a best-effort `git fetch`.** Without it, a checkout that has not fetched in days compares
  against an old `origin/main` and stays quiet, which is this exact case. It only updates the remote-tracking ref.
- **The warning does not block.** Building an older branch on purpose is legitimate.
- **Fixed the empty-badges case in the view layer**, leaving `state` as `.labels([:])` so that "click 3" keeps its
  current behaviour.
- **Did not launch the bundled app during investigation**, to avoid permission prompts and live listening. It is
  the PR's manual check.
