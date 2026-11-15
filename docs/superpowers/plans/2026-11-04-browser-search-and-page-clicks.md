# Browser Search and Page Clicks Implementation Plan

**Status:** Shipped
**Shipped:** NH-3 in PR #23; NH-17 in PR #20, with differences: [as-built](../as-built/2026-11-09-nh-17-browser-page-elements.md)

**Goal:** "Search for the Leafs game on YouTube" searches YouTube (not Google) wherever the user is, "search for X" uses the search box of the page or app in front, and voice clicks and number badges reach a web page's links, buttons and fields in a browser.

**Architecture:** Two tickets, two stacked branches. NH-3 lands the finished `feat/prompt-status-web-search` branch (the `search` action, `SiteSearch`, the prompt board) plus one diagnostic log line. NH-17 stacks on it: the fast-path accessibility walk in `AXQuery` becomes browser-aware (page web area first, larger budget) and `ActionExecutor` re-walks once after a Chromium page tree is first exposed.

**Spec:** no new spec; the tickets are the spec: [NH-3](https://github.com/noahstotland/nohands/issues/3), [NH-15](https://github.com/noahstotland/nohands/issues/15), [NH-17](https://github.com/noahstotland/nohands/issues/17), [NH-18](https://github.com/noahstotland/nohands/issues/18).

## Root cause

`CommandGrammar.parse` typed every `search for <words>` phrase into the address bar, so "on youtube" became part of the query. Now `search for X on <site>` opens the site's results page, and a bare `search for X` becomes `Action.search(X)`, resolved to the page's or app's own search box, else the current host's results URL, else the address bar.

## Constraints

- Grammar paths call no model. A log line may name a route, never the query.
- Every README voice-command phrase keeps working.

## Review focus

1. "Search for X" in an app with no search box types nowhere.
2. The address bar is never taken for the page's search box.
3. A thin first walk in Chrome must not make "click subscribe" fail silently.
4. Non-browser apps keep the 150 ms walk budget.
5. Unknown site names go to the model, never to a guessed URL.

## Task 1: land NH-3

Add one log line per search route, never the query. PR against `main` with `Closes #3`. NH-3's grammar covers NH-15's three rows; open-page preference for "on <site>" is the owner's product decision.

## Task 2: NH-17

- **`WalkPolicy`** (`NoHandsCore`): `app` is 150 ms, 2000 nodes; `browser` is 600 ms, 5000 nodes, page-first. `pick` uses `browser` settings in a browser without shrinking a larger caller budget (the task loop's 1 s / 6000).
- **`AXQuery.actionableElements`** picks a policy by `frontmostIsBrowser()`. Page-first visits the focused window's first `AXWebArea` right after the menu bar; the task loop's observer gets this too.
- **`ActionExecutor`** takes `exposureSettle` (default 600 ms). Show-labels and by-name clicks walk, and if `didJustExpose()` is true wait and walk again, keeping the first walk if cancelled.
- **README:** badges and `click <name>` cover page content in a browser; the first command after it comes forward can take about a second longer.
- **PR** targets the NH-3 branch until it merges, with `Closes #17`.

## Not planned: NH-18, the DOM bridge

Build it only if live checks show a page element Accessibility cannot find or click. Fixed shape: parameterized AppleScript JavaScript behind "Allow JavaScript from Apple Events", model output never executed as script.
