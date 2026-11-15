# NH-53: Browser tabs by name and number: Design

**Date:** 2026-11-15  **Ticket:** [NH-53](https://github.com/noahstotland/nohands/issues/53)
**Status:** Shipped
**Shipped:** in PR #133, with differences: [as-built](../as-built/2026-11-15-nh-53-browser-tabs.md)

## Intent

Browsing by voice stops at "next tab". The user can say "tab 3", "switch to the YouTube tab", "close the other tabs" and "list tabs", run from the grammar: on-device, no model, in the browser in front.

## Non-goals and anti-goals

- Out of scope: other windows or Spaces, ordinals other than first and last, closing a tab by name or number, tab groups, names without the word "tab" ("switch to YouTube" stays with the model).
- "tab 3" in a non-browser app must not press command-3.
- "close the other tabs" must not close tabs one by one or press a near-title item.
- A tab read must not block the main thread, and "stop" during it must stop the press.
- A tab title (page-controlled) reaches only the board.
- Existing phrases keep their meaning ("tab", "new tab", "next tab").

## What the code forces

- NH-42 already shipped the strip read (`AXQuery.browserWindows()`, `selectBrowserTab(id:)`; 500 ms per window, 1.5 s total) and the task loop's `Tabs:` block. Firefox hides its strip. No new reader.
- Existing `.selectTab(Int)` takes the model's listing numbers, so spoken positions get their own actions.
- The `go` and `open` patterns would catch "go to the youtube tab", so the tab rule runs before `parsePattern`.
- The board shows one notice line of at most 80 characters.

## Approach

Core parses phrases into three grammar-only actions (`goToTab`, `closeOtherTabs`, `listTabs`); the model can't produce them. Rejected: plain chords from Core, which can't know the front app is a browser.

## How it works

**Phrases.** Optional lead ("switch to", "go to", "open"), optional "the".
- `tab <n>`, `first tab`, `last tab` (n is 1 to 99, else it falls through as today).
- Lead plus `<words> tab`: a named tab. The lead is required. `new`, `next`, `previous`, `first`, `last`, `other` belong to other tab phrases.
- `close (all) (the) other tabs`; `list (the|my) tabs`.

**Matching.** `TabMatch.best` compares normalized titles in tiers: equal, prefix, every word as a whole word (a trailing "s" forgiven). Within a tier a non-active tab wins, then leftmost. No fuzzy guess. `listLine` is one board line like `1 YouTube · 2* Inbox`, active starred, titles cut to 3 words and 16 characters, ending `+N more` at 80 characters. Numbers 1 to 8 map to command-1 to command-8 and last to command-9.

**Executor.** Every tab action first requires a browser in front, else `no browser in front`.
- A chord target presses with no tab read: fast, and works in Firefox.
- Number 9 or more and named targets read the front window's tabs in a detached task, check cancellation, then select by id. Failures: `can't read the tabs in <app>`, `only <k> tabs`, `no tab called <words>`.
- Close-others presses the "Close Other Tabs" menu item (`exactOnly`); a missing or disabled item says so.
- List shows the line for 6 s.

## Tests

- Core tables: every phrase plus the must-not-change rows, matching tiers, chord and list caps.
- Executor with the fake provider: right tab, non-browser presses nothing, n past the end fails.

## Calls I made

- Close-others uses the menu item only and fails where there is none (Chrome may lack it), rather than a burst of destructive presses. A follow-up can add a fallback.
- "list tabs" is one line for 6 s, front window only.
- A named switch prefers a non-active tab, then leftmost; a mishearing says `no tab called …`.
