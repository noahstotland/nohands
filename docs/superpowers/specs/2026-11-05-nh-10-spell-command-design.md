# NH-10: Spell command for letter-by-letter typing — Design

**Date:** 2026-11-05  **Status:** Shipped  **Ticket:** [NH-10](https://github.com/noahstotland/nohands/issues/10)
**Shipped:** in PR #26, with differences: [as-built](../as-built/2026-11-05-nh-10-spell-command.md)

## Intent

`type` and dictation type whole words, so a password comes out as whatever the recogniser heard. `spell <tokens>` turns spoken letters, NATO words, digits and a few separators into one string typed with no spaces. If any token is unknown, nothing is typed and the HUD names the token, so nothing half-typed lands in a password.

## Approach

Chosen: a `Speller` in Core plus a grammar "reject" result that stops the model fallback. Rejected: returning nil, which sends the phrase to the model (it could type a half-right password).

## Design

- **Speller:** tokens come normalized and are read left to right, longest match first. Errors: empty, unknown (names the first bad token), capital without a letter.
  - Letters, homophones (`bee`, `see`, `you`...) and NATO words type that letter; digit words and numerals type digits; `space`, `dash`, `dot`, `underscore`, `at sign` type their characters.
  - `capital` upper-cases the next letter; before anything else it fails.
  - `x ray` is one NATO word, so "spell capital kilo nine x ray" gives `K9x`.
  - `oh` is the letter o, not zero. `to`, `too`, `for` fail rather than guess.
- **Grammar and routing:** a good spell returns `[.typeText(text)]`. A failed one returns a HUD line (`can't spell "<t>": say spell again`, and similar) via a new `Routing.reject`, never `.resolveWithLLM`. A routing case, not an `Action`, keeps the model's schema unchanged. Command mode only.
- **Pipeline:** `.reject` shows `.failed(message)` and logs `reject` with no payload, since the token may be part of a password.
- **Merge window:** a `spell` phrase always waits `mergeWindowMs` (500 ms), so a pause mid-spelling merges into one phrase instead of typing a prefix and sending the rest to the model.
- README gets the `spell` row.

## Tests

- One `Speller` table (including each failure) and one grammar-and-routing test (a bad spell never reaches the model). Manual, in the PR: `K9x` types into TextEdit.

## Calls I made

- A rejected spell never goes to the model: a model guess is the half-typed risk the ticket is about.
- Spell phrases always wait the merge window, so they are slightly slower.
- Letter homophones are accepted beyond the ticket's list, since the recogniser often writes a lone letter as a word.

## Out of scope

A persistent spell mode, hiding spoken letters from the board, spelling in dictation.
