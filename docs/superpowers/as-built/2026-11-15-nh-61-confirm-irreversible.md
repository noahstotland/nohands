# As-built: Confirm before irreversible actions

**Shipped:** in PR #120
**Ticket:** NH-61
**Spec:** [2026-11-15-nh-61-confirm-irreversible-design.md](../specs/2026-11-15-nh-61-confirm-irreversible-design.md)

## Differs from the spec

- The spec matches names with `CommandGrammar.normalize` alone. Shipped: names and goal are first reduced to letters and digits, so "Send…" and "File > Send Again" match ("normalize" strips only `.,!?`).
- "check out" is folded into "checkout" on both sides, so either spelling in the goal allows either button.
- A step with several guarded verbs asks about all of them ("say yes to place order and send"), so one yes covers exactly what was asked about; the spec had only the first.
- Return on a focused button is guarded only where the element list carries the focused state, which is the agent-desktop harness; the native accessibility walk does not report it.
- `ConfirmAnswer.isYes` takes the attention word as a parameter.
- With an attention word configured, a yes must start with it (the spec said the word was not needed). A stray "yes" from a TV then stops the task instead of confirming.
- A named target is also checked against every observed element in the tier the executor would use (exact title, else prefix, else contains), and moving the cursor or focus onto a guarded button is held like a click.
- A verb after a negation ("not", "never", "don't", "no", "without" and the like) in the same clause of the goal does not allow itself; a comma, "but" or "then" ends the clause. An element that appears on screen only after the observation, or beyond the element cap, is not seen by the guard.
