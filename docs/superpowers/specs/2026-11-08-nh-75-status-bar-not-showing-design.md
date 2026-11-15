# NH-75: Fix the always-on status bar not showing on screen — Design

**Date:** 2026-11-08  **Ticket:** [NH-75](https://github.com/noahstotland/nohands/issues/75)
**Status:** Shipped
**Shipped:** in PR #88, as specified

## Intent

The NH-66 status bar was reported as not appearing. Fix the two things that can make it missing.

## Findings

- **The bar works on `main`.** A throwaway harness ran the real `OverlayController` on a notched screen with an auto-hidden menu bar and read the window server back: the bar showed, moved, hid on Off and under the grid, and returned after `hide()`.
- **Likely cause: the app that was run predated NH-66.** Every `NoHands.app` on the machine did; the newest came from a checkout 79 commits behind `origin/main`.
- Ruled out: a stored `statusBarPosition`, and the notch. Several screens were not tested.
- **A real bug:** "Show numbers" with nothing to label sets `state` to `.labels([:])`. No badges draw, but the bar hides because it only checks `state == .none`, and stays gone until "hide".

## Changes

1. **The bar hides only when something is drawn:** while the grid panel or at least one badge panel exists. `state` keeps its meaning.
2. **`scripts/bundle.sh` warns about a stale checkout.** After a best-effort `git fetch --quiet origin main` (failure ignored), if `origin/main` is not an ancestor of `HEAD` it prints one line with the branch and commits behind. It never stops the build.
3. **README:** one sentence beside the build command.

No unit test: the change is AppKit panel state and a script. If the bar is still missing on a build that has it, stop with `BLOCKED:`; do not guess another fix.

## Leaves out

- New styling, the NH-70 corner panel (same check, left as is), following the pointer between screens, failing the build on a stale checkout.

## Calls I made

- A stale build is the main cause, so the fix is a build-script warning (about 8 lines the ticket did not list).
- The warning fetches first, or a stale checkout would stay quiet. It does not block: building an older branch is legitimate.
- The empty-badges case is fixed in the view layer so "click 3" keeps its behaviour.
