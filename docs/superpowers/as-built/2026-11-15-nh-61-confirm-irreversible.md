# As-built: Confirm before irreversible actions

**Shipped:** in PR #PRN
**Ticket:** NH-61
**Spec:** [2026-11-15-nh-61-confirm-irreversible-design.md](../specs/2026-11-15-nh-61-confirm-irreversible-design.md)

## Differs from the spec

- The spec matches names with `CommandGrammar.normalize` alone. Shipped: names and goal are first reduced to letters and digits, so "Send…" and "File > Send Again" match ("normalize" strips only `.,!?`).
- "check out" is folded into "checkout" on both sides, so either spelling in the goal allows either button.
- A name with several guarded verbs asks about the first verb, in list order, that the goal does not allow.
- `ConfirmAnswer.isYes` takes the attention word as a parameter.
