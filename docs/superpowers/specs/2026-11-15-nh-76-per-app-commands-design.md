# NH-76: Per-app voice commands: Design

**Date:** 2026-11-15  **Ticket:** [NH-76](https://github.com/noahstotland/nohands/issues/76)
**Status:** Shipped
**Shipped:** in PR #129, with differences: [as-built](../as-built/2026-11-15-nh-76-per-app-commands.md)

## Intent

The grammar had one global phrase table, and menu commands needed agent-desktop. This adds two mechanisms every app ticket (#74 and its links) builds on:

- A **pack**: a phrase table for bundle IDs, checked before the global table.
- **Menu items by name** ("menu bookmark this tab"), pressed natively through Accessibility.

It ships no app packs. Non-goals: a user-editable pack file; offering `menu_item` to the model in the native task loop.

Anti-goals: a pack changing anything in another app; "menu <words>" pressing something not named (a fuzzy guess, the Apple menu); the walk opening a menu on screen or slowing the grammar fast path; a pack matching "stop".

## Decision

Packs are Core tables passed into `CommandGrammar`, keyed by bundle ID (names are localized; IDs aren't). Menu items through agent-desktop only was rejected: the voice path usually lacks the harness, and its click opens the menu on screen.

## How it works

`AppPack` has a name, bundle IDs, and phrases (normalized phrase to actions). `AppPacks.all` ships empty; a test rejects stop words in it.

### Lookup order in `parse(_:frontmost:)`

1. Global exact table, unless the frontmost app's pack has the same phrase (then the pack wins).
2. Pack lookup on the normalized phrase. Normalization drops one leading "open" or "go to", then "the", "a" or "an".
3. "menu <words>" becomes `.menuItem(words)` in any app. Bare "menu" is no match.
4. Global exact table on the normalized phrase, only when the lead was "open" and more than one word is left: "open a new tab" is command-T everywhere. "go to <x>" keeps meaning a site or the address bar unless a pack has `<x>`.
5. Patterns, then filler-stripped exact match. Unknown "open <x>" is still `.openApp(x)`.

With no bundle ID (CLI default, tests) this is the old behaviour plus steps 3 and 4.

### Menu title matcher

Fold titles and words (lowercase, "…" removed, punctuation dropped, spaces collapsed). Tiers: exact; titles starting with the words, then titles containing every word (shortest wins, then menu bar order); else no match. No edit distance. A spoken path ("file > save as") limits the search to that top menu.

### Native menu path

- `AXMenuReader` walks the frontmost app's menu bar and submenus and **skips the Apple menu**. Budget 200 ms and 1500 items, only when a `menuItem` executes.
- `.menuItem` runs native first: disabled reports "menu item <title> is disabled"; enabled gets `AXPress` (the menu does not open); no match falls back to agent-desktop when present, else "no menu item called <words>".
- `VoicePipeline` passes the frontmost bundle ID to routing and keeps it for the merge buffer, so pack phrases close the merge window early.
- First build task: check `AXPress` on a closed-menu item in Chrome, Safari, Finder and Mail on macOS 14. An app that ignores it gets chords in its pack.

### CLI and README

- `nohands-cli parse "<text>" [--app <bundle id>]` dry-runs with that app in front.
- `nohands-cli menu "<words>"` prints the match and presses it after 2 s; `menu --list` prints the tree.
- README gets a `menu <words>` row and a "Per-app commands" table.

## Calls I made

- The native path runs every `.menuItem`, including the model's; the irreversible guard already checks `menuItem` names.
- A misheard word fails with "no menu item called …" instead of pressing a neighbour.
- "open" plus a multi-word global phrase runs it everywhere; a single word stays an app name ("open home").
- Stop words stay out of packs by test, not code.

## Follow-ups

- `ShortcutGuard` does not check `menuItem` titles ("Close Window", "Quit …") from the model. Needs a ticket before the native task loop is offered `menu_item`.
