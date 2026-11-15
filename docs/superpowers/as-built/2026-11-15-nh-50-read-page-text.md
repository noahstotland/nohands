# As-built: Read page text

**Shipped:** in PR #128
**Ticket:** NH-50
**Spec:** [2026-11-15-nh-50-read-page-text-design.md](../specs/2026-11-15-nh-50-read-page-text-design.md)

## Differs from the spec

- The spec cuts nothing per text run; shipped, each run and each `near:` source text is read up to 400 characters (the AX string default of 120 would cut a paragraph).
- A double quote inside a `near:` hint is rendered as a single quote, so page text cannot fake the `= "…"` value structure.
- `read_page` also re-walks once after a Chromium page tree was just exposed, as `find` does.
- The harness executor file is unchanged: `.readPage` is handled in the native `run` switch before the harness is consulted.
- The `near:` source keeps the latest static text with no on-screen check (to save AX calls).
- Known limit: an editor that exposes its text as an `AXGroup` with `AXEditable` (rather than a text area) is read as page text, because only the text-entry roles are skipped.
- Only the page reading, added by code, gets the 4,000-character limit; any other reading's label has its colons removed and a bare "page" renamed, so page content can't claim the long limit. The page text is joined to leave room for its label, so the cut mark is kept.
