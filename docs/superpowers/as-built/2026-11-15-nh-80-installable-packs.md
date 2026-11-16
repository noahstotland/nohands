# As-built: Installable app packs

**Shipped:** in PR #142
**Ticket:** NH-80
**Spec:** [2026-11-15-nh-80-installable-packs-design.md](../specs/2026-11-15-nh-80-installable-packs-design.md)

## Differs from the spec

- The spec lists no `version` or `author` on built-in packs; `AppPack` now carries `id`, `version` and `author` (Terminal: `terminal`, author `NoHands`).
- The validator also rejects an empty `commands` list, a command with no phrases, control/format/bidi/line-separator characters in any string, and whitespace in URLs. A phrase is also checked against the reserved list with its "open" or "go to" lead stripped.
- `PackSummary` does not hold "replaces version X" or "shadowed by installed packs"; `nohands-cli pack add` derives those from the store and `PackSet.shadowed`.
- `PackFile.encode` skips a command holding an action the format cannot express (the built-ins have none).
- `nohands-cli parse` also loads installed packs, so authors can dry-run a phrase.
- The grammar is swapped on reload through `CommandGrammar.with(packs:)` and `ModeMachine.use(grammar:)`, with the merge window's copy behind a lock in `VoicePipeline`.
