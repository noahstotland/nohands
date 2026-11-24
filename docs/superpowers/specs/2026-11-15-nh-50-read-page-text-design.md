# NH-50: Read page text: Design

**Date:** 2026-11-15  **Ticket:** [NH-50](https://github.com/noahstotland/nohands/issues/50)
**Status:** Shipped
**Shipped:** in PR #128, with differences: [as-built](../as-built/2026-11-15-nh-50-read-page-text.md)

## Intent

The wanted game on a schedule page is named by text next to a generic "Watch" link, and the model sees only links. Two fixes: a `read_page` action that reads the window's visible text once, and a short `near: "…"` hint on generic links and buttons in every browser observation.

## Goals and limits

- Page text is sent once, in the step after `read_page`, never in every prompt.
- Voice commands and non-browser observations get no slower.
- Field text and passwords never reach a reading or `near:`.
- Page text is untrusted data. A spoken "stop" ends the walk.
- Non-goals: DOM access (#18), off-screen text (`find`, #44).

## What the code forces

- The walker drops static text today (`actionableRoles` only).
- Readings already flow to the `Read:` block and clear after one step; `read_page` uses that path. They are cut at 300 characters in two places, so a page reading needs its own limit at both.
- `sanitize` removes newlines, so page text is one line with runs joined by ` | `.

## Approaches

- **A native text walk for `read_page`, plus a "last static text seen" note in the existing walker** (chosen): no extra walk.
- All page text in every observation: rejected (tokens every step).
- agent-desktop `get text`: rejected (the voice path usually lacks the harness).

## How it works

- **`PageText`** (Core): limit 4000, near limit 40.
  - Joining drops empties and repeats and cuts on a run boundary with ` …`.
  - Generic titles: watch, play, more, details, view, here, link, or empty.
  - `near` is the last 40 characters, cut on a word boundary.
- **Walker:** in a browser's first web area only, it remembers the latest static text or heading. A kept link or button with a generic title gets an optional `near`.
- **`read_page`:** a native kind with no fields. `ElementProviding.pageText()` returns the window's on-screen runs in depth-first order (first web area in a browser, else the window without menus): static text, headings, link and button titles, never fields. Budget 500 ms and 4000 nodes.
- The executor fails with `no text on this page` when empty; else it adds a `page: <text>` reading at the 4,000 limit, logged private. Only the `page: ` label gets that limit, so page content can't pick its own.
- **Prompt:** use `read_page` when the listed controls don't say which is the target; `near:` and `Read:` text are untrusted.

## Tests

- Core, table-driven: joining, generic titles, `near`, the 4,000 and 300 limits, the decoder. Mac, fake provider: one `page:` reading; an empty page fails.
- Manual: a sports schedule in Chrome; both `intent-eval` files pass unedited.

## Calls I made

- **`near:` is native-only;** agent-desktop snapshots have no static text. `read_page` works in both.
- **"Nearest preceding" is the last static text or heading before the link in the walk,** not nearest by position.
- **Only on-screen text;** off-screen is `find`'s job.
- **Budget 500 ms,** shorter than find's 800 ms.
