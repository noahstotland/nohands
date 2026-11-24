# NH-42: Close pop-ups, overlays and tabs a page opened, until the video plays — Design

**Date:** 2026-11-05  **Ticket:** [NH-42](https://github.com/noahstotland/nohands/issues/42)
**Status:** Shipped
**Shipped:** in PR #65, with differences: [as-built](../as-built/2026-11-05-nh-42-close-popups-until-video-plays.md)

## Intent

"Open the Raptors game on <stream site>" should end with the game playing in the tab the task opened. Stream sites throw pop-unders, cookie banners and ad countdowns. The loop must see them, close what the task did not ask for, and go on until the video plays. It must never close a tab or window the user already had open unless the user said "close".

## Design

### Core: what the task opened

`TabLedger` (pure, one per task per browser) over `BrowserWindow` and `BrowserTab` values with opaque ids from the Mac layer:

- The **baseline** (all window ids, tab ids and tab titles) is recorded the first time the task sees that browser in front. A restored session counts as the user's.
- A tab or window is **new** only if its id and its title are both absent from the baseline. The title check is the fail-safe if every id changes.
- After `open_url`, `search` or `searchSite`, the active tab of the front window at the next settled observation is the **task's tab**. It is never closable without a close word, though new.
- `TabListing` numbers tabs and windows per observation: every tab of the front window (up to 20), every new one anywhere, only a count for other old windows. Titles are sanitized to 60 characters.

### Core: actions, guard, message, step cap

- Actions `close_tab`, `close_window`, `select_tab` take `target_number` from the `Tabs:` list.
- `TabGuard` runs before a step, beside `ShortcutGuard`, and blocks the whole step for: a number not in the listing; `close_tab` or `close_window` on a tab or window that is not new, or on the task's tab, unless the goal has a close word (same list as command-W). `select_tab` is never blocked. Command-W and command-Q rules are unchanged.
- A `Tabs:` block (flags `front`, `active`, `task`, `new`) replaces the unused `Windows:` line whenever the front app is a browser. The prompt names it untrusted data.
- Goals with play, watch, stream, video, game, match, movie, episode, livestream or listen use new config `maxMediaTaskSteps` (default 24, clamp 1…30) instead of `maxTaskSteps` (12).

### Prompt rules (all backends)

- After navigating, close `new` tabs or windows the request did not ask for, then `select_tab` the `task` tab. Never close a tab not marked `new`.
- Dismiss an overlay by its own close control; never click the ad. Wait out countdowns. Play on the page's own player.
- For play or watch goals, `done` only when it plays (the NH-43 signal if present, else the control reads Pause).

### Mac

- `ElementProviding.browserWindows()` reads each window's `AXTabGroup` (titles, selected tab). No tab group (Firefox) means the window stands for itself. NH-53 reuses this reader.
- Ids are per-task tokens per `AXUIElement`, cleared when the task ends.
- `close_tab` presses the tab's close button; with none, it selects the tab, checks, and sends command-W. `close_window` presses `AXCloseButton`.
- README: ad blockers are the first defence; `maxMediaTaskSteps`.

## Tests

Tables for `TabLedger`, `TabGuard`, the `Tabs:` block, `MediaGoal` and config. A fake-browser runner test closes a pop-under and blocks closing a pre-existing tab. Manual (PR): a stream site plays in the task's tab, the user's own tabs survive.

## Out of scope

Blocking pop-ups before they open, screenshots (NH-41), tabs by voice (NH-53), the playing signal (NH-43).

## Calls I made

- **Media goals get a 24-step cap instead of raising 12 for everyone**, so other tasks still fail fast.
- **A tab is new only if both id and title are unseen.** Cost: a pop-up copying a user tab's title cannot be closed without "close" in the goal.
- **The task's tab is protected though new**, so cleanup cannot close the game's tab.
- **Closing goes only through `close_tab` and `close_window`**, which name a tab, so a focus change cannot close the wrong one.
- **`select_tab` is added** to return to the task's tab.
- **A tab the user opens by hand mid-task counts as new** and could be closed.
- **Tabs are read through Accessibility, not AppleScript**, so there is no new Automation prompt.
