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
