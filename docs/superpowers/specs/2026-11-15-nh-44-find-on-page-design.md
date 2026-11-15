# NH-44: Find on page: Design

**Date:** 2026-11-15  **Ticket:** [NH-44](https://github.com/noahstotland/nohands/issues/44)
**Status:** Shipped
**Shipped:** in PR #126, with differences: [as-built](../as-built/2026-11-15-nh-44-find-on-page.md)

## Intent

On a long page (a channel's video list, a schedule, search results) what the user wants is often below the fold. The
model has to guess a scroll amount, look again and retry, and the voice grammar can't say "find the Raptors game".
This ticket adds one action, `find`, that walks the whole focused window for the words, scrolls the match into view
and hands it back: first in the model's next element list, or under the pointer when the user said it.

## Goals, non-goals, anti-goals

Goals are the ticket's Scope and Acceptance.

Non-goals: searching page prose (#50); loading more of a lazy page (infinite scroll) to find something that isn't in
the tree yet; "scroll to the top" or "scroll to the bottom"; find inside a menu, sheet or other overlay surface.

Anti-goals, which would make this a failure even if it works:

- Bare "find" stops being command-F.
- The walk runs on the grammar fast path for other commands, or makes any command slower.
- A find in the task loop moves the pointer onto an element, so a later bare click lands on something nobody checked
  (the irreversible guard does not see pointer clicks).
- A field's typed value or a password field is matched or sent to the model.
- A spoken "stop" during the walk lets the scroll run anyway.
- No match clicks or scrolls to a guess.

## What the code forces

- **The walker drops offscreen elements.** `AXQuery.Walker.visit` keeps an element only when its frame intersects a
  screen, and only for `actionableRoles`. Static text and headings are never collected. Find needs its own walk.
- **There is a model for a bigger walk.** `AXQuery.searchFieldFrame` walks the first web area first, then the rest of
  the window skipping web areas and menus, with its own 800 ms budget and 4000 nodes. Find copies that shape.
- **`scroll_to` already exists** as a harness kind on an element that is already listed, and needs agent-desktop.
  It stays as it is. `find` is a native kind: it works with either harness.
- **Bare "find" is an exact grammar phrase** (command-F). Exact phrases are matched before patterns, so "find" plus
  words can be a pattern without touching it.
- **"scroll to …" parses as nothing today:** `parseScroll` wants a direction, so it goes to the model.
- **Observations are numbered by the observer**, natively (`LabelAssigner.assign` then `menuBarLast`) or from the
  agent-desktop snapshot (`ScreenObserver.list`). Putting the match first is a renumbering after either.
- **Readings already flow from executor to observer** (`ActionExecutor.takeReadings()` →
  `observe(readings:)`), so the found element can travel the same way.

## Approaches

1. **One native walk that matches as it goes, then `AXScrollToVisible` on the match (chosen).** One walk, an early
   stop on an exact match, works with either harness and with no harness, and the fake element provider can test it.
   agent-desktop's `find` + `scroll-to` is the fallback when the native walk finds nothing.
2. **agent-desktop first** (`find`, then `scroll-to`). Semantic, but its `find` has no prefix tier, needs the
   harness, and the voice path usually has none.
3. **Scroll and re-observe in a loop** until the words show up. Handles lazy pages, but it is slow, guesses at
   amounts, and is what the model already does badly.

## How it works

### Action

`Action.findOnPage(String, movePointer: Bool)`. The grammar sets `movePointer: true`; the model's `find` sets
`false`. `carriesSpokenText` is true (the words may still be coming). `ActionSummary` gets an entry.

### Matching (`PageFind`, NoHandsCore, Foundation only)

- `PageFind.normalize(_ words:)`: trims, lower-cases, drops a leading "the" and trailing `.,!?`. Empty → no find.
- `PageFind.Matcher(words:)`: fed candidate texts in walk order with `offer(_ text:, element:) -> Bool`. Tiers, all
  case-insensitive on the trimmed text: exact, then prefix, then contains, like `AppNameMatcher`. Within a tier the
  first offered wins. `offer` returns true on an exact match so the walk can stop. `best` is the winner.
- `PageFind.failure(_ words:)` is `no match for <words> on this page` (the words as spoken). It does not start with
  `no element`, so `VisionTrigger` does not send a picture for it.
- `PageFind.pinFirst(_ labels: [Int: UIElementInfo], found: UIElementInfo, limit: Int) -> [Int: UIElementInfo]`:
  finds the element in the list (same ref; else same title, case-insensitive, preferring one whose frame intersects
  the found frame), makes it number 1 and shifts the rest down in order. When it is not in the list it is inserted as
  number 1, and the list's last element drops off if that passes `limit`.

### The walk (`AXQuery.findOnPage`, NoHandsMac)

- Focused window; in a browser the first web area first, then the rest of the window skipping web areas, like
  `searchFieldFrame`. Menu bar, menus and menu items are skipped.
- Own budget: 800 ms and 6000 nodes, constants beside `searchBudget`. It runs only for a find action, never on the
  grammar path for other commands.
- No visibility filter. Elements with a zero or non-finite frame are skipped.
- Texts offered per element: title, then description. `AXStaticText` and `AXHeading` also offer their value. No
  other role offers its value (fields hold the user's data), and secure fields offer nothing.
- A static-text or heading match inside a link or button within three levels up reports that link or button (its
  title, or the matched text when it has none), so the model sees something it can click.
- Returns the match as a `UIElementInfo` with an id the next call can act on, or nil.
- `scrollIntoView(id:) -> CGRect?`: `AXUIElementPerformAction(kAXScrollToVisibleAction)`, then re-reads the frame
  for up to 300 ms until it intersects a screen. nil when the action fails or the frame never comes on screen.

Both are new `ElementProviding` methods with defaults that return nil, so the fakes keep compiling.

### Executor

`ActionExecutor` runs `.findOnPage(words, movePointer)`:

1. Native walk (with the Chromium exposure re-walk `freshElements` already does). Check cancellation after it.
2. Match → `scrollIntoView`; check cancellation before acting. Failed scroll → `couldn't scroll to <words>`.
3. No native match and a harness present → `harness.find` then `harness.act(.scrollTo(ref:))`; the found element
   has the match's name and no frame.
4. Nothing → `PageFind.failure(words)`.
5. On success the executor keeps the found element for `takeFound()` (read and cleared like readings). With
   `movePointer`, the pointer moves to the element's `clickPoint(screens:)` when it has a frame.

Words over 200 characters fail with `text too long`. Words are logged with the private marker.

### Task loop

- `IntentSchema`: `find` joins the native kinds, with `target_name`. System prompt line: "find: scroll the page until
  an element or text with these words is visible, when what you need is not in the list. Fields: target_name (the
  words). The match is listed first, as number 1, in the next step."
- `IntentDecoder`: `find` with a non-blank `target_name` → `.findOnPage(name, movePointer: false)`; blank or missing
  is rejected like any malformed action.
- `TaskRunner` passes `executor.takeFound()` to the next `observe`, which runs `PageFind.pinFirst` on its labels
  (native or harness) and rebuilds the observation's element list from them.

### Grammar

- "find <words>" → `.findOnPage(words, movePointer: true)`. The words come from the raw transcript (casing kept,
  trailing ASR punctuation trimmed), like "search for".
- "scroll to <words>" → the same, except "scroll to (the) top" and "scroll to (the) bottom", which stay with the model.
- Bare "find", and "find the" with nothing after it, stay command-F.
- README voice command table: two rows, `find <words>` and `scroll to <words>`.

## Tests

- **Core, one table each:** the grammar rows (find with words, scroll to with words, bare find, find the, scroll to
  the top, scroll down unchanged); the decoder (`find` with a name, blank, missing); `PageFind.Matcher` (exact beats an
  earlier prefix, prefix beats an earlier contains, first wins in a tier, case and "the" ignored, empty words, the
  failure message); `PageFind.pinFirst` (found by ref, by title, inserted when absent, the cap).
- **Mac, fake provider:** an element whose frame is outside every screen is found, scrolled (the fake records the
  call and returns an on-screen frame) and is number 1 in the next observation; `movePointer` moves the pointer and
  the model's find does not; no match returns the failure message; a cancel during the walk scrolls nothing.
- **Manual, in the PR:** Chrome on a YouTube channel's Videos tab, "find <title of the tenth video>" scrolls to it
  and "click" opens it; the same goal as a task; `scripts/intent-eval.json` and `scripts/intent-eval-disfluent.json`
  pass with no expectation edited.

## Calls I made

- **The model's find never moves the pointer; the voice find does.** The ticket says "leaving the pointer on the
  match so click follows", which fits the voice path. In the task loop the model clicks the label it is given, and a
  pointer parked on a button would let a later bare click skip the irreversible guard.
- **No scroll-and-retry loop for lazy pages.** The ticket's scope is one walk of the whole window. Something not yet
  loaded fails with the no-match message, and the model can scroll and find again.
- **"scroll to the top / bottom" are not finds.** They would search the page for the word "top". They stay with the
  model as today.
- **A text match inside a link reports the link,** so the next step has something clickable with a real title.
- **Static text and headings offer their value; no other role does,** so field contents and passwords are never
  matched (they would show up in the next observation sent to the model).
- **agent-desktop is only the fallback,** used when the native walk finds nothing and a harness is present.
- **No picture after a no-match.** The failure text does not start with `no element`, so the vision trigger stays off.
  A find that misses is a missing text, not an invisible element.
- **Budget: 800 ms (the ticket's figure) and 6000 nodes** (more than search's 4000, since a long page is the point),
  with an early stop on an exact match.
- **Failure on a scroll that doesn't land:** `couldn't scroll to <words>`, after 300 ms of re-reading the frame.
- **The words are capped at 200 characters.**
- **The found element is pinned even when the observation comes from agent-desktop,** matched there by title because
  the native walk has no agent-desktop ref.
