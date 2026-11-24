# NH-3: Land the prompt board and the search action — Design

**Date:** 2026-11-04  **Status:** Shipped  **Ticket:** [NH-3](https://github.com/noahstotland/nohands/issues/3)
**Shipped:** in PR #23, with differences: [as-built](../as-built/2026-11-04-nh-3-prompt-board-search.md)

## Intent

The prompt board and `search` action (commit a722a18) were never opened as a PR, and the one live try ("search for outdoor boys" on YouTube) did nothing and logged nothing. This lands them and makes a failed search diagnosable.

## What lands

- **Prompt board:** one row per spoken prompt at the top of the screen with its status. It replaces the bottom HUD pill; failures land on the row.
- **`search`:** "search for X" tries, in order: the frontmost window's own search box (never the address bar); a known site's results URL; the address bar on any other browser page. With none it fails with "nothing to search in <app>". "search for X on youtube" opens that site's results from anywhere.
- **Diagnosis:** `ActionExecutor.search` logs one `info` line per search naming the route taken (`searchField`, `siteURL`, `addressBar`, `none`). The query stays out of the public part.

## Live checks (left for the user, listed in the PR as not run)

Chrome on YouTube, Finder, an app with no search box (Calculator), and the board with "stop" mid-task.

## Non-goals

- Fixing the YouTube case beyond the log line; without a diagnosed cause any fix is a guess.
- Changing the board's look.

## Calls I made

- The route log line is unconditional, since the agent cannot run the live check that would decide it.
- Live checks need mic and Accessibility, so the user runs them. I added the "stop" check because the board touches the stop path.
- No CI, so green means local tests.
