# NH-53: Browser tabs by name and number: Design

**Date:** 2026-11-15  **Ticket:** [NH-53](https://github.com/noahstotland/nohands/issues/53)
**Status:** Shipped
**Shipped:** in PR #133, with differences: [as-built](../as-built/2026-11-15-nh-53-browser-tabs.md)

## Intent

Browsing by voice stops at "next tab" and "previous tab". The user should be able to say "tab 3", "switch to the
YouTube tab", "close the other tabs" and "list tabs" and have them run from the grammar: on-device, with no model and
no network, in the browser in front.

## Goals, non-goals, anti-goals

Goals are the ticket's Scope and Acceptance, less the parts NH-42 already shipped (below).

Non-goals: tabs in other windows or Spaces (ticket); ordinals other than first and last ("the second tab"); closing a
tab by name or number by voice ("close tab 3"); tab groups, pinning, moving tabs; tab names without the word "tab"
("switch to YouTube" stays with the model, which already has `select_tab`).

Anti-goals, which would make this a failure even if it works:

- "tab 3" in a non-browser app presses command-3 (Finder's column view, Xcode's navigator, Terminal's third window).
- "go to the YouTube tab" or "open the YouTube tab" types into the address bar or opens an app, as both do today.
- "close the other tabs" closes tabs one by one, or presses a menu item that is merely close to that title
  ("Close Other Windows").
- A tab read blocks the main thread for its whole budget, or a spoken "stop" during the read lets the press go out.
- A tab title (page-controlled) reaches anything but the board.
- Any phrase in the README table changes meaning: bare "tab" is still the Tab key, "new tab", "close tab",
  "close this tab", "next tab", "previous tab" are unchanged.

## What the code forces

- **NH-42 shipped the tab strip read.** `AXQuery.browserWindows()` (`BrowserTabReader.swift`) returns the front
  browser's windows, each with its tabs (`BrowserTab`: opaque id, title, active) in strip order, with a 500 ms
  per-window and 1.5 s total budget; `selectBrowserTab(id:)` presses a tab. Firefox hides its strip: its windows come
  back with no tabs. The ticket's `AXQuery.tabs()` is this function; no new reader.
- **The task loop already has its `Tabs:` block** (`TabLedger`, `TabListing.rendered`, `select_tab` / `close_tab` /
  `close_window` actions, `TabGuard`). The ticket's "observation gets a `Tabs:` line" is done; this ticket does not
  touch the task loop.
- **The existing `.selectTab(Int)` and `.closeTab(Int)` take numbers from the model's listing** and resolve only
  against the batch's `tabSnapshot`. A spoken number means a position in the strip, a different thing, so the voice
  commands get their own actions rather than overloading those.
- **The grammar order** is: pack phrase, exact table, pack without a lead, `open` + exact, `menu …`, patterns,
  filler-stripped exact. "go to the youtube tab" hits the `go` pattern (address bar) and "open the youtube tab" hits
  the `open` pattern (`openApp`), so the tab rule must run before `parsePattern`. "close this tab" already works
  through the filler table.
- **`pressMenuItem(_:exactOnly:)`** presses a menu item natively by title with no harness; `exactOnly: true` refuses a
  near title.
- **The board shows one notice line, at most 80 characters** (`showHUD(_:duration:)`), and a product rule keeps HUD
  text to one line.
- **`frontmostIsBrowser()`** knows the browser bundle ids (Chromium family, Safari, Firefox, Opera, Kagi, Zen).

## Approaches

1. **Grammar-only actions run by the executor (chosen).** Core parses the phrases into three new actions; the Mac
   executor checks the browser, reads the strip off the main actor when it needs titles or a position past 8, and
   presses a chord, a tab or a menu item. Pure parsing and matching are testable in Core; the executor is testable
   with the fake element provider.
2. **Parse to plain chords in Core** (`.pressKey(command-3)`). Simplest, but Core can't know whether the front app is
   a browser, so "tab 3" would press command-3 anywhere (anti-goal), and names and positions past 8 still need the
   executor.
3. **Send tab phrases to the model with the `Tabs:` block.** Already possible today and slow (seconds, network or a
   local model); the ticket asks for the grammar.

## How it works

### Phrases (Core, `CommandGrammar`)

A new `parseTab(tokens)` runs after the `menu` rule and before `parsePattern`. Leads: none, "switch to", "go to",
"open", each optionally followed by "the". Then:

| Spoken | Action |
|---|---|
| `tab <n>`, `tab number <n>`, `switch to tab <n>`, `go to tab <n>`, `open tab <n>` | `.goToTab(.number(n))` |
| `first tab` (with any lead) | `.goToTab(.number(1))` |
| `last tab` (with any lead) | `.goToTab(.last)` |
| `switch to the <words> tab`, `go to the <words> tab`, `open the <words> tab` | `.goToTab(.named(words))` |
| `close the other tabs`, `close other tabs`, `close all other tabs` | `.closeOtherTabs` |
| `list tabs`, `list the tabs`, `list my tabs` | `.listTabs` |

- `<n>` is `NumberWords.parse`, 1 to 99; anything else is not a tab phrase (falls through as today).
- `<words>` keeps the speaker's words (`rawWords`) and needs a lead: bare "youtube tab" is not a command. Names that
  are other tab phrases go there instead: `new` (new tab, command-T), `next`, `previous`, `first`, `last`, `other`.
  So "go to the next tab" is control-tab and "open the new tab" stays command-T.
- "close this tab" keeps the existing filler route (command-W); no change.

### Actions (Core, `Action`)

```swift
public enum TabTarget: Equatable, Codable, Sendable { case number(Int), last, named(String) }
case goToTab(TabTarget)
case closeOtherTabs
case listTabs
```

Grammar only, like `.checkMedia`: the decoder has no kind for them, so model output can never produce them. They join
the exhaustive switches (`ActionSummary`, `SettlePolicy`, `SpokenFreeText`) as non-typing, settle-after actions.

### Title matcher and listing (Core, `BrowserTabs.swift`)

`TabMatch.best(_ words: String, in tabs: [BrowserTab]) -> Int?` returns the index of the tab to select, on
`CommandGrammar.normalize`d titles and words (so case and punctuation don't matter):

1. A title equal to the words, else a title that starts with them, else a title that holds every word as a whole word.
   A word also matches its plural or singular with a trailing "s" ("doc" finds "Docs").
2. Within the best tier, a tab that is not active wins over the active one (saying "the YouTube tab" from one YouTube
   tab goes to the other); then the leftmost.
3. No tier matches: nil. No fuzzy guess.

`TabMatch.listLine(_ tabs: [BrowserTab]) -> String` builds the one board line: `1 YouTube · 2 Inbox · 3 GitHub`,
the active tab marked with `*` (`2* Inbox`). Each title is the first 3 words, cut to 16 characters, through
`TabListing.clean` (one line, no quotes). It fills up to 80 characters and ends `+N more` when tabs remain.

`TabMatch.chord(for target:) -> KeyChord?`: command-1 to command-8 for numbers 1 to 8, command-9 for `.last`, nil
otherwise (the executor then clicks the tab).

### Executor (Mac, `ActionExecutor`)

Every tab action first checks `ax.frontmostIsBrowser()`; when it is not, the row fails with `no browser in front`.

- `.goToTab` with a chord: press it. No tab read, so it is as fast as "next tab" and works in Firefox.
- `.goToTab(.number(n))` for n ≥ 9, and `.goToTab(.named)`: read `browserWindows()` in a detached task (as
  `TaskRunner` does), take the front window's tabs, check `Task.isCancelled`, then `selectBrowserTab(id:)`.
  Failures: `can't read the tabs in <app>` (front window has no tabs: Firefox, or the read found none);
  `only <k> tabs` (n past the end); `no tab called <words>` (no match). The words come from the user, never a title.
- `.closeOtherTabs`: `pressMenuItem("Close Other Tabs", exactOnly: true)`. Safari has it in File. Where the menu has
  no such item: `no Close Other Tabs menu item in <app>`; disabled (one tab): `menu item Close Other Tabs is disabled`.
- `.listTabs`: read as above, show `TabMatch.listLine` with `showHUD(_:duration: .seconds(6))`; the prompt's row goes
  to done. Failures as above.

Tab titles go only to the board, never into a log line without the private marker.

### README

New rows in the voice command table for each phrase, with the browser-only note and the Close Other Tabs caveat.

## Tests

Per `AGENTS.md` § Testing, one table-driven test per rule:

- Core grammar table: every phrase above to its action, plus the must-not-change rows (`tab`, `new tab`, `open a new
  tab`, `close this tab`, `next tab`, `go to the next tab`, `go to youtube`, `open safari`, `tab 0`, `tab 100`,
  `youtube tab`).
- Core `TabMatch.best` table: tiers, plural, case, prefer-not-active, leftmost tie, no match.
- Core `TabMatch.chord` and `listLine` table (the n-to-chord rule; the 80-character cap and `+N more`).
- Mac executor with the fake provider: "switch to the youtube tab" selects the right tab id; not a browser fails
  with no press; n past the end fails; a chord number presses command-n without reading tabs.

Manual (in the PR): Safari and Chrome, tab 3, tab 12, last tab, switch to the <name> tab, list tabs, close the other
tabs; Firefox tab 3 and switch to a named tab; "tab 3" in Finder does nothing.

## Calls I made

- **"close the other tabs" uses the menu item only, and fails where there is none.** Chrome may have no "Close Other
  Tabs" in its menu bar (it is in the tab's right-click menu); then the row says so instead of closing tabs one at a
  time, which would be a burst of destructive presses. The manual check records what Chrome does; a follow-up ticket
  can add a fallback.
- **"tab <n>" does nothing outside a browser** (`no browser in front`), rather than pressing command-n anywhere.
- **The task loop's `Tabs:` line is not touched**: NH-42 already added it with a richer listing.
- **"list tabs" is one board line for 6 seconds** (the board holds one 80-character notice), so titles are cut to a
  few words and a long strip ends `+N more`. Only the front window's tabs are listed.
- **A named switch prefers a tab that is not already active**, then the leftmost. No fuzzy matching: a mishearing
  says `no tab called …`.
- **Ordinals other than first and last are left out** ("the second tab" is a model fixture about page elements
  today). Numbers cover the need.
- **New actions instead of reusing `.selectTab(Int)`**: that one takes the model's listing numbers, and keeping it
  separate means a spoken number can't be confused with a listing number.
- **Names need a lead word and the trailing "tab"**, so "youtube tab" alone is not a command.
- **Numbers 1 to 99 only**; "tab 0" and "tab 100" fall through to today's behavior.
