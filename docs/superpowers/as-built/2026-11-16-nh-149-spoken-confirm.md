# As-built: Spoken yes before irreversible fixed phrases

**Shipped:** in PR #PRNUM
**Ticket:** NH-149
**Spec:** [2026-11-16-nh-149-spoken-confirm-design.md](../specs/2026-11-16-nh-149-spoken-confirm-design.md)

## Differs from the spec

- The spec's forced rule lists the `IrreversibleGuard` verbs. It also forces the confirm on the word "trash" in a pack phrase, so "trash note" asks.
- `nohands-cli run` uses the plain global grammar, so it refuses only global marked phrases (`empty trash`). A pack phrase is never run from the CLI, because `run` has no frontmost app.
- A newly added phrase in a `PackDiff` does not carry `(asks first)`; the diff reports `now asks first` and `no longer asks first` for phrases that exist in both versions. `pack add`, `install` and `update` summaries show `(asks first)` on every phrase.
- The spoken "say yes to <phrase>" is not tied to the row, so the held phrase's finish line is still spoken at `outcomes` and `all`.
- A reply that arrives before the pipeline starts waiting is kept, so the first words after a marked phrase are always its answer and never a held job.
- One forced phrase makes every phrase of its command ask, because a command shares one set of actions.
