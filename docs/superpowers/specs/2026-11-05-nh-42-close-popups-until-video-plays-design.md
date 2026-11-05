# NH-42: Close pop-ups, overlays and tabs a page opened, until the video plays — Design

**Date:** 2026-11-05  **Status:** Draft  **Ticket:** [NH-42](https://github.com/noahstotland/nohands/issues/42)

## Intent

"Open the Raptors game on <stream site>" should end with the game playing in the tab the task opened. Stream
sites throw pop-under tabs, new windows, cookie banners, "click to continue" layers and ad countdowns. The
task loop has to see those, close the ones the task did not ask for, and keep going until the video plays.
It must never close a tab or window the user already had open unless the user said "close".

## What `main` does today

Read from the code:

- `ShortcutGuard.blocked` blocks command-W unless the goal has a close word, and command-Q unless it has a
  quit word. "Open the game" has neither, so the model cannot close a pop-under at all. That stays as is.
- `ScreenObservation.windows` exists and `ClaudeRequestBuilder.userMessage` prints a `Windows:` line from
  it, but nothing fills it. The model never sees other windows, and never sees tabs.
- The system prompt has no rule for overlays, pop-ups or media.
- `maxTaskSteps` is 12 (config, clamped to 1…30). A page that throws three overlays and a pop-under uses
  most of that before the play button.
- Nothing says whether the video is playing. That is NH-43, which is being built in parallel.

## Design

### Core (`NoHandsCore`): what the task opened

New file `BrowserTabs.swift`, pure data and rules, no AppKit:

- **`BrowserTab`** `{ id: String, title: String, active: Bool }` and **`BrowserWindow`**
  `{ id: String, title: String, front: Bool, tabs: [BrowserTab] }`. `tabs` is empty when the browser does not
  expose its tab strip; the window then stands for itself. Ids are opaque tokens the Mac layer hands out;
  Core never looks inside them.
- **`TabLedger`** (one per task, per browser app):
  - `baseline(app:windows:)` records every window id, tab id and tab title the first time the task observes
    that browser in front. At task start that is the browser already in front; a browser that was in the
    background or not running gets its baseline at the first observation where it is in front (so a
    cold-launched browser's restored session counts as the user's).
  - A tab or window is **new** when its id was not in the baseline **and** its title was not one of the
    baseline titles. The title check is the fail-safe: if the browser ever rebuilds its accessibility
    elements and every id changes, the user's tabs still match by title and stay protected.
  - `markTaskTab(...)`: after a step that ran `open_url`, `search` or `searchSite`, the active tab of the
    front window at the next settled observation is the **task's tab**. It is never closable without a close
    word, even though it is new.
  - `listing(for windows:) -> TabListing`: numbers windows and tabs for one observation (tabs `1…N` across all
    windows, windows `1…M`), each with `new` and `task` flags, and maps numbers back to ids.
- **`TabListing` caps:** every tab of the front window up to 20, every new tab and window anywhere, and for
  the other old windows only a count (`+N other tabs`). Titles are sanitized and cut to 60 characters like
  other untrusted text.

### Core: new actions, schema and guard

- **New actions:** `Action.closeTab(Int)`, `Action.closeWindow(Int)`, `Action.selectTab(Int)`. The number is
  the tab or window number from the request's `Tabs:` list. Schema kinds `close_tab`, `close_window`,
  `select_tab` with `target_number`; they are native kinds (they work with or without agent-desktop). The
  decoder rejects a missing or non-positive number like other bad steps. `ActionSummary` logs them as
  `closeTab(3)` etc.; no titles.
- **`TabGuard.blocked(actions, listing:, goal:) -> String?`** next to `ShortcutGuard`, called by the task
  runner before executing a step (the step runs nothing when blocked, same as today's shortcut guard):
  - a number not in the listing → `"blocked: no tab N"` (or `window N`);
  - `close_tab` / `close_window` on a tab or window that is not new, or on the task's tab → blocked unless the
    goal has a close word (the same word list as `ShortcutGuard`'s command-W);
  - `select_tab` is never blocked.
  The command-W and command-Q rules in `ShortcutGuard` are unchanged: a pop-up is closed only through
  `close_tab` / `close_window`.
- **User message:** the unused `Windows:` line is replaced by a `Tabs:` block, printed whenever the front app
  is a browser with a reading (both harnesses):

  ```
  Tabs (Google Chrome):
    window 1 (front) "Raptors vs Celtics - StreamSite"
      tab 1 "Inbox (3) - Gmail"
      tab 2 "Raptors vs Celtics - StreamSite" (active, task)
      tab 3 "You won!" (new)
      +12 other tabs
    window 2 (new) "Casino"
  ```

  Rule 7 of the system prompt and the harness rules name the `Tabs:` block as untrusted data, like window
  titles.
- **Step cap for media goals:** `MediaGoal.matches(goal)` is true when the goal has a word like play, watch,
  stream, video, game, match, movie, episode, livestream or listen (exact words, like the shortcut guard).
  New config key `maxMediaTaskSteps`, default **24**, clamped to 1…30; the runner uses it instead of
  `maxTaskSteps` (still 12) for a media goal. The `Step n of max` line shows the cap in use.

### Core: prompt rules for media goals

Added to the base system prompt (so Claude and the local model get them, with or without agent-desktop):

- Use `close_tab`, `close_window` and `select_tab` from the `Tabs:` list. After navigating, close any tab or
  window marked `new` that the request did not ask for, then `select_tab` the tab marked `task` if it is not
  active. Never close a tab that is not marked `new`.
- Dismiss an overlay (cookie banner, "click to continue", sign-up box) by its own close control: Close, ×,
  Skip, No thanks, Reject or Accept for a cookie banner. Never click the ad itself or a link inside it.
- When a countdown is visible ("Skip in 5"), wait it out: `wait_for` with the harness, `wait` without.
- Press play on the page's own player, not an embedded ad.
- For a request to play or watch something, set `done` only when it is playing. If the observation carries a
  media-playing signal (NH-43), use it; otherwise the player's control reads Pause.

### Mac (`NoHandsMac`)

- **Reading tabs:** `ElementProviding` gets `browserWindows() -> [BrowserWindow]?` (nil when the front app is
  not a browser). It walks each window of the frontmost browser (bundle ids from `AXQuery`'s existing
  browser lists) to its `AXTabGroup`, and reads the tab buttons: title, and `AXValue` 1 for the selected one.
  When no tab group is found, the window has no tabs and stands for itself (Firefox and others that hide it).
  This reader is the one NH-53 reuses for tabs by voice.
- **Ids:** a per-task registry hands out a token for each `AXUIElement` window and tab, matched with
  `CFEqual`, so the same element gets the same token every observation. The registry is cleared when the
  task ends.
- **Executing:**
  - `close_tab`: find the tab by token in a fresh read. Press its close button (a child `AXButton` with the
    close subrole or named Close). With none, press the tab to select it, check it is now the selected tab,
    and send command-W to the browser. If the tab is gone, the step fails with `"tab already closed"`
    (not an error worth stopping for).
  - `close_window`: press the window's `AXCloseButton`; fail with `"can't close that window"` when it has none.
  - `select_tab`: press the tab; fail when it is gone.
- **Task runner:** builds the `TabLedger` at the first observation, adds a browser's baseline when one first
  comes to the front, marks the task's tab after a navigation step, attaches the `TabListing` to each
  observation, runs `TabGuard` next to `ShortcutGuard`, and picks the media step cap.
- **Observer:** `ScreenObserver` adds the browser windows to the observation; the runner turns them into the
  listing (the observer stays a collector).

### README

- Task section: one line that an ad blocker in the browser is the first line of defence against pop-ups, and
  NoHands closes what gets through, only tabs and windows the task opened.
- Configuration section: `maxMediaTaskSteps` (default 24).
- No new spoken phrase, so the voice command table does not change.

## Tests

- **`TabLedger` (one table):** a tab in the baseline is never new; one that appeared is new; one with a new id
  but a baseline title is not new; the task's tab is never closable; a browser first seen mid-task gets its
  own baseline; window rules the same way.
- **`TabGuard` (one table):** new tab or window → allowed; old tab, task tab or unknown number → blocked;
  old tab with "close" in the goal → allowed; `select_tab` → allowed.
- **User message (one test):** the `Tabs:` block with front, active, task, new flags, the cap and the
  `+N other tabs` line; titles sanitized; no block for a non-browser app.
- **Decoder:** `close_tab`, `close_window`, `select_tab` decode; a missing number is rejected.
- **`MediaGoal` and config:** media words pick the media cap, other goals keep 12; `maxMediaTaskSteps`
  default, decode and clamp.
- **Mac, task runner with fakes:** a fake browser with two tabs; the first step's `open_url` adds a task tab
  and a pop-under tab; the next request lists the pop-under as `new` and a `close_tab` on it reaches the fake
  provider; a `close_tab` on a pre-existing tab is recorded as a blocked failed step and nothing is closed.
- `scripts/intent-eval*.json` are not edited and must keep passing (run before the PR with the model on).

## Manual checks (in the PR)

1. On the user's stream site in Chrome: "open the Raptors game on <site>". The game ends up playing in the task's
   tab with the pop-ups gone, or the PR says exactly where it failed and why (step log attached).
2. Same with a pop-under that opens a new window: it is closed with `close_window`.
3. With several of the user's own tabs open, a goal without "close": none of them is closed. With "close the
   Gmail tab": it is closed.
4. Safari: tabs are read and a pop-up tab is closed. Firefox: windows only, a pop-up window is closed.

## Out of scope

- Blocking pop-ups before they open (the browser's or an ad blocker's job).
- The screenshot fallback (NH-41).
- Switching, closing and listing tabs by voice (NH-53); this ships only the reader and the loop's actions.
- The media-playing signal itself (NH-43).

## Calls I made

- **Media goals get their own step cap of 24 instead of raising 12 for everyone.** Other tasks keep failing fast
  and cheap; "media goal" is a fixed word list (play, watch, stream, video, game, match, movie, episode,
  livestream, listen). A goal that matches by accident only gets more steps.
- **A tab counts as new only if both its id and its title are unseen at baseline.** This protects the user's
  tabs if the browser rebuilds its accessibility elements. The cost: a pop-up that copies the title of one of
  the user's tabs can't be closed without "close" in the goal.
- **The tab the task navigated to is protected even though it is new**, so the model can't close the game's
  own tab while cleaning up.
- **A browser that was not in front at task start gets its baseline the first time the task sees it in
  front.** So a cold-launched browser's restored tabs count as the user's, and the task's tab from `open_url`
  is in that baseline. A pop-up that opens before that first observation would count as the user's (safe
  direction).
- **command-W and command-Q rules stay exactly as they are.** Closing goes only through `close_tab` and
  `close_window`, which name a specific tab, so a focus change between observing and acting can't close the
  wrong one.
- **Adds `select_tab` to the loop** (not by voice), because after closing a pop-under the browser may land on
  the wrong tab and the ticket asks the loop to return to the task's tab. NH-53 adds the spoken phrases.
- **A tab the user opens by hand while the task runs counts as new** and could be closed by the loop. Telling
  it apart from a pop-up isn't possible from the tab strip.
- **No media-playing signal here.** NH-43 is in progress; the prompt uses its signal when present and falls back
  to "the player shows Pause". Whichever PR lands second wires the two together (one prompt line).
- **Tabs are read through Accessibility, not AppleScript**, so no new Automation permission prompt.
