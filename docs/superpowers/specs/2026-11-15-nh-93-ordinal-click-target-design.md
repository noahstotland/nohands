# NH-93: Resolve an ordinal click target like "first video": Design

**Date:** 2026-11-15  **Ticket:** [NH-93](https://github.com/noahstotland/nohands/issues/93)
**Status:** Shipped
**Shipped:** in PR #121, with differences: [as-built](../as-built/2026-11-15-nh-93-ordinal-click-target.md)

## Intent

Goal "Click the first video." made the model send `target_name "first video"`, which failed with `no element named 'first video'`. A title works; a position does not. Two layers: the prompt tells the model to send a label number for a position (rule 3), and the resolver resolves an ordinal sent as a name instead of failing.

## Scope

Non-goals: ordinals in actions other than `click` and `move_cursor`; "top result", "second to last".

Anti-goals: a real element titled with the spoken words losing to the ordinal reading; an ordinal clicking the toolbar, a tab, the menu bar or the "Videos" chip; an unresolvable ordinal clicking a guess; changing the `no element named` prefix (`VisionTrigger` keys on it).

## Design

`UIElementInfo` has no "page content" flag, and adding one means changing the walker and parser. So the rule uses role: browser chrome has no links, page results are links.

Chosen: map the ordinal to a label number over the list the model saw, then click that label (the semantic harness path). Rejected: a fresh walk, whose count can differ.

### Parse (`OrdinalTarget`, NoHandsCore)

An ordinal (`first` to `tenth`, a suffixed number such as `11th`, or `last`), then an optional one- or two-word noun (`video`, `result`, `link`, `search result`), case-insensitive, leading "the" dropped. Anything else is nil.

### Candidates

Taken from the shown list in label order; the nth (or last) wins.
- **Role noun** (`link`, `button`, `checkbox`, `tab`, `field`, `menu item`): elements of that role.
- **Any other noun or none**: "results", meaning links with a title of three or more words, dropping a repeat of the previous title.

Why: chrome has no links; navigation links are short ("Home", "Shorts"); a result is often two links (thumbnail and title); the noun never matches titles, since "video" would match the "Videos" chip. Fewer than n candidates returns nil.

### Wiring

- `TargetResolver.element` (`resolveClick`, `resolveMove`): `find(named:)` first. On a miss, an ordinal mapping to label n returns that label's point. Otherwise it fails with `no element named '<name>'; say its label number from the list` for an ordinal, the plain message otherwise.
- `ActionExecutor` click: on such a miss, click `.label(n)` (harness ref if any, else the point).
- Prompt rule 3: for a position use target_kind "label"; never put an ordinal in target_name.

## Tests

One table test on `resolveClick` over a fixed list (chrome, nav links, results): ordinals resolve right, a real "First video" title wins, chrome and nav links are never picked, and too-large ordinals or no links fail with the prefix and hint. Manual: "Click the first video." on YouTube results.

## Calls I made

- **The noun never matches titles**, only role nouns narrow.
- **"Results" means links with at least three words, repeats dropped**: no new element data; shorter titles stay reachable by title or number.
- **No links on screen means the ordinal fails** with the hint, even in a native app with rows; a guess could click the wrong row.
- **Ordinals** are words to "tenth", suffixed numbers and "last" only.
