# NH-93: Resolve an ordinal click target like "first video": Design

**Date:** 2026-11-15  **Ticket:** [NH-93](https://github.com/noahstotland/nohands/issues/93)
**Status:** Shipped
**Shipped:** in PR #121, as specified

## Intent

In a live task on a YouTube results page, goal "Click the first video.", the model answered `click` with
`target_kind element` and `target_name "first video"`, and the step failed with `no element named 'first video'`.
The user wants any video to be clickable by voice: the first, the second, or one by its title. A title already works
(`LabelAssigner.find` matches titles). A position does not. This ticket makes a position work, and tells the model to
send a label number for it in the first place.

Two layers, because either alone falls short:

1. **Prompt:** the model sees the numbered element list, so it can pick the right number itself. That is the best fix
   when it follows the rule.
2. **Resolver fallback:** when the model still sends an ordinal as a name, the app resolves it instead of failing.

## Goals, non-goals, anti-goals

Goals are the ticket's Scope and Acceptance, with the narrowing rule below.

Non-goals, from the ticket: moving the status bar (#92), menu-bar and repeat guards (#90), the YouTube latest-video
route (#91), getting page content into the element list (#17). Also not here: ordinals in the other element actions
(`set_value`, `type_into`, `check` and the rest go through `ActionExecutor.resolve(_ ElementTarget)`), and phrases like
"top result", "second to last" or "the video below that".

Anti-goals, which would make this a failure even if it works:

- A real element whose title is the spoken words loses to the ordinal reading.
- An ordinal clicks the browser's toolbar, a tab or the menu bar.
- "first video" on YouTube clicks the "Videos" filter chip because its title contains "video".
- An ordinal that can't be resolved clicks something anyway (the closest guess) instead of failing.
- The `no element named` prefix changes: `VisionTrigger` keys on it to send a picture with the next step.

## What the code forces

- **The click path today.** `click` with `.element(name)` walks fresh native elements (`ActionExecutor.freshElements`)
  and calls `TargetResolver.resolveClick`, which calls `LabelAssigner.find(named:)` (exact, prefix, contains) and fails
  with `no element named '<name>'`. The resolver already receives `labels`, the snapshot the model was shown this step
  (harness or native, already numbered `menuBarLast`).
- **No "page content" flag.** `UIElementInfo` has a role and a frame but nothing that says an element sits in the web
  page rather than the toolbar or tab strip. Adding one means changing the native walker and the agent-desktop parser,
  and agent-desktop's tree shape for a web area is not something this repo pins down. So the rule below uses the role
  instead: browser chrome (toolbar buttons, the address field, tab buttons, menu-bar items) has no links, and page
  results are links.
- **Harness clicks are semantic for labels only.** A `.label(n)` with a ref goes through `harness.act(.click(ref:))`;
  a point click is the fallback. An ordinal should land on the same path, so it is turned into a label number, not a
  point.

## Approaches

1. **Map the ordinal to a label number from the shown list, then click that label (chosen).** The count runs over
   exactly what the model saw, in the numbering it saw, and the click reuses the label path (semantic with a harness ref,
   a point otherwise). A pure core function does the mapping.
2. **Resolve the ordinal over the fresh native walk.** Simpler wiring, but the count can differ from the list the model
   saw, and it loses the harness's semantic click.
3. **Prompt only.** Cheapest, but the ticket's failure is the model ignoring the label number; one more prompt line
   does not guarantee it.

## How it works

### Parse (`OrdinalTarget`, NoHandsCore, Foundation only)

`OrdinalTarget.parse(_ name: String) -> OrdinalTarget?` reads, case-insensitively, after trimming and dropping a
leading "the":

- an ordinal: `first` … `tenth`, a number with an ordinal suffix (`1st`, `2nd`, `3rd`, `11th`, any n ≥ 1), or `last`;
- then an optional noun of one or two words (`video`, `result`, `link`, `one`, `search result`), singular or plural.

Anything else (a plain title, an ordinal with three or more words after it, "first" inside a longer title) is nil.

### Candidates and count

`OrdinalTarget.label(in labels: [Int: UIElementInfo]) -> Int?` picks the candidates from the shown list in label
order, then takes the nth (or the last). The narrowing rule:

| Noun | Candidates |
|------|------------|
| A role noun: `link`, `button`, `checkbox`, `tab`, `field` / `text field` / `box`, `menu item` | Elements of that role (AX prefix and case dropped; `field` covers textfield, textarea, searchfield, combobox) |
| Anything else, or none (`video`, `result`, `item`, `one`, `article`, …) | **Results:** links (role `link`) whose title has at least three words, with a repeat of the previous candidate's title dropped |

Why the results rule looks like that:

- Links only, because browser chrome has none, so the toolbar, tabs and menu bar drop out without a page-content flag.
- At least three words, because a site's navigation links are short ("Home", "Shorts", "Subscriptions", "YouTube
  Home", "Watch later") and a result's title is long (a YouTube video link reads "Raptors vs Celtics Full Game
  Highlights 12 minutes"). Two-word results are rare and are still reachable by title or label number.
- A repeated title dropped, because one result is often two links with the same name (thumbnail and title), and
  "second video" must not land on the first video's title link.
- The noun is not matched against titles: "video" would match the "Videos" filter chip.

No candidates, or fewer than n, returns nil.

### Wiring

- `TargetResolver.element` (used by `resolveClick` and `resolveMove`): `find(named:)` first, unchanged. On a miss, if
  the name parses as an ordinal and maps to label n in `labels` (or, with no snapshot, in
  `LabelAssigner.assign(elements)`), return that label's click point. Otherwise fail with
  `no element named '<name>'; say its label number from the list` for an ordinal, and the plain message for any other
  name.
- `ActionExecutor` click: after the fresh walk, when `find` misses and the ordinal maps to label n in the snapshot, the
  click runs as `.label(n)`: through the harness ref when there is one, else the point. `move_cursor` stays on the
  resolver's point.
- `IntentSchema.systemPrompt` rule 3 gains one sentence: for "the first video", "the second result" or any position,
  use target_kind "label" with that element's number from the list; never put an ordinal in target_name.

## Tests

One table test on `TargetResolver.resolveClick` over a fixed list (menu-bar items, toolbar buttons, an address field,
tab buttons, short navigation links, then three results each with a thumbnail and a title link of the same name, and an
element titled "First video" in one variant):

- "first video", "second result", "3rd link", "last video", "the first one" resolve to the expected element;
- the list with "First video" as a real title clicks that element, not the first result;
- "first video" lands on the first result, not the menu bar, toolbar, tabs or a short nav link;
- "tenth video" with three results, and "first video" with no links, fail with the `no element named` prefix and the
  label hint;
- a plain name that matches nothing keeps today's message.

One case on `resolveMove` (same path). One `ActionExecutor` test that an ordinal with a harness ref clicks through the
harness, like a label. Parsing is covered through the resolver table, not a test of its own.

Manual, recorded in the PR: Chrome on a YouTube results page, goal "Click the first video." clicks the first result
with no failure in the step trail. `scripts/intent-eval.json` and `scripts/intent-eval-disfluent.json` pass on Claude
with no expectation edited.

## Calls I made

- **The noun never matches titles.** The ticket says to narrow by "title or role". Matching "video" against titles
  would pick YouTube's "Videos" filter chip for "first video", so only role nouns narrow; every other noun means
  "results".
- **"Results" means links with at least three words in the title, repeats dropped.** The ticket leaves the exact rule
  to the builder. This one needs no new element data and keeps the toolbar, tabs, menu bar and short nav links out. It
  misses a result whose title is one or two words; that one is still reachable by title or by number.
- **No links on screen means the ordinal fails** (with the label hint), even in a native app with a list of rows. A
  guess outside the browser could click the wrong row; the model has the numbered list and can answer with a label.
- **The count runs over the list the model was shown,** not a fresh walk, so "second" means the second in the model's
  own numbering.
- **Ordinal clicks with a harness ref are semantic,** through the same path as a label click.
- **Only `click` and `move_cursor` get ordinals.** The other element actions (`set_value`, `type_into`, `check`, …)
  keep failing on an ordinal name.
- **Ordinals up to "tenth" in words, any number with a suffix, and "last".** No "second to last", "top", "next".
- **The hint text** is `; say its label number from the list`, appended after the existing message.
