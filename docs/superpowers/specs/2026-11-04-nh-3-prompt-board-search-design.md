# NH-3: Land the prompt board and the search action — Design

**Date:** 2026-11-04  **Status:** draft for approval  **Ticket:** [NH-3](https://github.com/noahstotland/nohands/issues/3)

## Intent

The prompt board and the `search` action are already written (commit a722a18 on the local branch
`feat/prompt-status-web-search`) but were never opened as a PR, and the one live try ("search for outdoor boys"
on YouTube in Chrome) did nothing and left nothing in the log. This ticket lands that work on `main` and makes
a failed search diagnosable. It adds no new feature.

## What lands (unchanged from a722a18)

- **Prompt board** (`NoHandsCore/PromptBoard.swift`, `NoHandsMac/OverlayController.swift`): one row per spoken
  prompt at the top of the screen with its status (listening, heard, step n, held, done, failed, stopped,
  dropped, ignored). The pipeline reports through `OverlayPresenting.report`; `TaskRunner` feeds it through
  `onStatus`. The bottom-of-screen HUD pill is gone; failures land on the prompt's row.
- **`search` action** (grammar, intent schema, decoder, `ActionExecutor`, `NoHandsCore/SiteSearch.swift`,
  `AXQuery.searchFieldFrame` / `frontmostIsBrowser`). "search for X" tries three routes in order:
  1. the frontmost window's own search box (a page's field in the web area, or a native search field; never
     the address bar): click, select all, type, Return;
  2. a known site's results URL (YouTube, Google, Amazon, Reddit, Wikipedia, …) typed into the address bar;
  3. the address bar on any other browser page.
  An app with none of these fails with "nothing to search in <app>". "search for X on youtube" and
  "search youtube for X" open that site's results page from anywhere.
- README voice command table: the `search for <words>` row the branch already carries.

## Plan

1. Branch `feat/nh-3-prompt-board-search` from `origin/main`; cherry-pick a722a18 (done: applies cleanly, the
   commit's base a1fe9b7 is already in `main`). `feat/prompt-status-web-search` itself is left untouched.
2. **Route log line.** In `ActionExecutor.search`, log one `PipelineLog.info` line per search naming the route
   taken and why the earlier routes were skipped, e.g.
   `search: route=searchField` / `search: route=siteURL host=youtube.com (no search field)` /
   `search: route=addressBar (no search field, no known site)` / `search: route=none (not a browser, no search field)`.
   The query text is not in the public part of the line; if logged at all it goes through the `.private` detail.
   A thrown input error is logged as a warning naming the route it failed in.
3. One table-driven test in `ActionExecutorTests` that the fake `ElementProviding` setups pick the expected
   route (the existing tests already cover the key presses per route; extend them only where a route is
   uncovered).
4. `swift test` and `swift build` green; `.build/debug/nohands-cli eval scripts/intent-eval.json` and
   `scripts/intent-eval-disfluent.json` unchanged (needs a running model, so it is a manual check if no model
   is available to the agent).
5. Open the PR against `main` with the ticket linked, the README row change in the summary, and the live-check
   list below.

## Live checks (manual, listed in the PR, not claimed as passed)

These need the microphone, Accessibility and real apps, so the agent cannot run them. The PR lists each with an
empty result for the user to fill in, plus the `log stream --predicate 'subsystem == "dev.nohands.app"'`
command to read the route line.

1. Chrome on youtube.com: "search for outdoor boys" → YouTube results for "outdoor boys" in the same tab.
   Route expected: `searchField`, else `siteURL`.
2. Finder window frontmost: "search for outdoor boys" → Finder's search field filled and searching.
   Route expected: `searchField`.
3. An app with no search box (e.g. Calculator): "search for outdoor boys" → the prompt row shows
   "nothing to search in Calculator" and nothing is typed. Route expected: `none`.
4. Prompt board: speak a plain command, a task, and "stop" during a task → each gets a row with the right
   status; "stop" halts the task and is its own row.

## Non-goals

- Fixing the YouTube case beyond the log line if it still fails live. Without a diagnosed cause any fix would be
  a guess; the log line exists so the next try says which route failed. A follow-up ticket gets filed with the
  log output.
- Changing the prompt board's look or copy, or adding sites to `SiteSearch`.

## Calls I made

- **The route log line is added unconditionally, not only "if YouTube still fails."** The ticket's acceptance
  needs a log line on a failed search, and the agent cannot run the live check that would decide the "if", so
  the line goes in up front. It is one `info` line per search, query kept private.
- **Live checks are left for the user.** The ticket asks for three live results in the PR; they need the mic and
  Accessibility, which an agent run doesn't have. The PR lists them as not run. I added a fourth (prompt board
  plus "stop") because the board replaces the HUD and touches the stop path.
- **No CI exists**, so "green" means `swift test` and `swift build` run locally in the worktree.
- **The cherry-picked commit keeps its original author and message**, as the task asked; my commits on top use
  the builder role.
