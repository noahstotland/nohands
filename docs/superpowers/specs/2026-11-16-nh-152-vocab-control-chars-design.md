# NH-152: Reject control characters in a vocabulary "say" and cap the spellings per entry

**Date:** 2026-11-16
**Status:** Draft
**Ticket:** [NH-152](https://github.com/noahstotland/nohands/issues/152)

## Goal

Two gaps in `Vocabulary.clean` (`Sources/NoHandsCore/Vocabulary.swift`), found in the NH-56 security review:

1. A `say` is trimmed at its ends only, so a newline or tab inside it survives and dictation types it as a Return or Tab (a Return can send a message or submit a form).
2. The number of spellings in one `hear` entry has no cap, so one entry can carry thousands and slow every transcript (`apply` walks every spelling at every word).

## Design

### Control characters in `say`

- After the existing trim, an entry whose `say` contains any Unicode scalar of general category `Cc` (U+0000 to U+001F and U+007F to U+009F: newline, carriage return, tab, escape, bell, and the rest) is dropped and counted in `skipped`, like the other bad entries. Nothing is stripped or replaced.
- The trim is unchanged: a newline or tab only at the ends of `say` is still trimmed away and the entry kept (today's behavior; the risk is a control character that would be typed).
- Format characters (`Cf`, such as the zero-width joiner inside emoji) are allowed.

### Spellings per entry

- New constant `Vocabulary.maxHearSpellings = 10`.
- After the existing per-spelling filter (empty, over five words, stop word), only the first 10 surviving spellings are kept; the rest are dropped. The entry itself is kept, so `skipped` does not change.

### Docs

`docs/configuration.md` § Vocabulary: `hear` is a string or a list of up to 10 spellings of up to five words each; a `say` with a control character (newline, tab and the like) skips the entry; past 10 spellings the rest are ignored.

## Tests

One table-driven test in `Tests/NoHandsCoreTests/AppConfigTests.swift` (beside the existing vocabulary decoding table), or new rows in that table:

- `say` with an inner `\n`, `\t`, `\u001b` or `\u0085` → skipped, `skipped` counts it.
- `say` with a newline only at its ends → kept, trimmed (guards the trim rule).
- An entry with 11 or 12 spellings → kept with exactly the first 10.
- An entry with bad spellings among the first 10 → the cap counts surviving spellings only.
- Ordinary entries (including an emoji with a ZWJ in `say`) → unchanged.

## Leaves out

- Control characters in `hear` (the matcher splits on whitespace and drops edge punctuation; out of scope per the ticket).
- Any other whitespace handling in the matcher.
- A launch log line naming dropped spellings (the existing count-only log is kept).

## Calls I made

- **Spellings past the cap are dropped, not the whole entry.** The ticket says "keep the first 10"; the entry still works and `skipped` stays a count of entries.
- **The cap counts valid spellings.** Bad spellings are filtered first, so an entry with a few bad ones still gets 10 working spellings.
- **Control set is `Cc` only, not `Cf`.** Foundation's `CharacterSet.controlCharacters` also covers `Cf`, which would reject emoji with a zero-width joiner (a family emoji) and soft hyphens. `Cc` is everything that can type a key or escape a terminal.
- **End-trimmed newlines stay accepted.** `"say": "Raptors\n"` keeps working as `Raptors`, as today; only a control character left after the trim rejects the entry.
- **No change to `maxHearWords` or `maxEntries`.**
