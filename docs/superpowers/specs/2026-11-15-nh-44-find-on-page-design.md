# NH-44: Find on page: Design

**Date:** 2026-11-15  **Ticket:** [NH-44](https://github.com/noahstotland/nohands/issues/44)
**Status:** Shipped
**Shipped:** in PR #126, with differences: [as-built](../as-built/2026-11-15-nh-44-find-on-page.md)

## Intent

On a long page the wanted item is often below the fold, and the grammar can't say "find the Raptors game". This adds one action, `find`: it walks the whole focused window for the words, scrolls the match into view and hands it back, in the model's next element list or under the pointer when the user said it.

Non-goals: searching page prose (#50); loading more of a lazy page; "scroll to the top/bottom"; find inside a menu, sheet or overlay.

Anti-goals: bare "find" ceasing to be command-F; the walk running on the grammar fast path; a task-loop find moving the pointer (a later bare click would skip the irreversible guard); a field's value or password being matched; scrolling after "stop" or to a guess.

## Decision

One native walk that matches as it goes, then `AXScrollToVisible` on the match. It stops early on an exact match and needs no harness. agent-desktop `find` plus `scroll-to` is the fallback when the native walk finds nothing. Rejected: agent-desktop first (no prefix tier, needs the harness) and a scroll-and-re-observe loop (slow, guesses amounts).

## How it works

- `Action.findOnPage(String, movePointer: Bool)`. The grammar sets `movePointer: true`; the model's `find` sets `false`.
- `PageFind` (Core) matches case-insensitively on trimmed text, dropping a leading "the" and trailing `.,!?`. Tiers: exact, prefix, contains; first offered wins within a tier.
- Failure text `no match for <words> on this page` does not start with `no element`, so no picture is sent.
- `pinFirst` makes the found element number 1 in the next observation (by ref, else title, else inserted and the last element dropped past the limit).

### The walk (`AXQuery.findOnPage`)

- Focused window; in a browser the first web area first, then the rest, skipping web areas, the menu bar and menus.
- Budget 800 ms and 6000 nodes, only for a find action. No visibility filter.
- Each element offers its title, then description. Only static text and headings also offer their value; fields and secure fields never do.
- A text match inside a link or button within three levels up reports that link or button, so it is clickable.
- `scrollIntoView` performs `kAXScrollToVisibleAction`, then re-reads the frame for up to 300 ms. Failure is `couldn't scroll to <words>`.

### Executor

1. Native walk, then scroll. Cancellation is checked after the walk and before acting.
2. No native match and a harness present: `harness.find` then `scrollTo`.
3. Words over 200 characters fail with `text too long`.
4. On success the found element goes to the next `observe` (pinned first even from an agent-desktop observation, matched by title). With `movePointer`, the pointer moves to its click point.

### Task loop and grammar

- `find` is a native kind with `target_name`.
- "find <words>" and "scroll to <words>" give `.findOnPage(words, movePointer: true)`. "scroll to (the) top/bottom" stays with the model; bare "find" and "find the" stay command-F.
- README voice table gets both rows.

## Calls I made

- The model's find never moves the pointer; the voice find does.
- No scroll-and-retry for lazy pages.
- "scroll to the top/bottom" are not finds; they would search for the word "top".
- Budget 800 ms (the ticket's figure) and 6000 nodes (search uses 4000). Words capped at 200 characters.
