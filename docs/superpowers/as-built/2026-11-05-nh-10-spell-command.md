# As-built: Spell command for letter-by-letter typing

**Shipped:** in PR #26
**Ticket:** NH-10
**Spec:** [2026-11-05-nh-10-spell-command-design.md](../specs/2026-11-05-nh-10-spell-command-design.md)

## Differs from the spec

- The spec says a `spell` phrase waits `mergeWindowMs` (500 ms). It waits `mergeWindowUnfinishedMs` (1.5 s by default): `UtteranceMerger.isUnfinished` treats any phrase starting with `spell` as unfinished. Review found 500 ms too short: a pause past it typed half the string and sent the rest to the model. A pause longer than 1.5 s still splits it.
- The grammar and routing tests live in `SpellerTests.swift`, not in `CommandGrammarTests` and `ModeMachineTests`.
- Added: a line in `PipelineTextTests` pinning that a rejected spell's message stays out of the public summary, and a `spell` line in `UtteranceMergerTests`.
- The longer hold ignores the mode, so dictated text that starts with "spell" (such as "spell check this") also waits 1.5 s before it is typed.
