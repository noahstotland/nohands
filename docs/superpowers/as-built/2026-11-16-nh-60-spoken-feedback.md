# As-built: Spoken feedback

**Shipped:** in PR #167
**Ticket:** NH-60
**Spec:** [2026-11-16-nh-60-spoken-feedback-design.md](../specs/2026-11-16-nh-60-spoken-feedback-design.md)

## Differs from the spec

- The spec says only "Spoken feedback on." is spoken when a voice phrase changes the level. Shipped: any voice change to `outcomes` or `all` is confirmed aloud ("Spoken feedback on.", "Spoken feedback all."); `off` stays silent.
- The spec says a voice change applies live. Shipped: it also saves `speakFeedback` to config.json, like the menu. If the save fails the change still applies for the session and the HUD says it was not saved.
- A rewrite step inside a model task also counts as reading text, so that task's finish line is private (the spec named only the read actions).
- A rewrite's finish line at `all` is spoken as the preview alone, without "Done".
- A line that never reports its end is cut by a 45 s watchdog (not in the spec).
- A private "failed" line says "Stuck." when its detail starts with "stuck", else "Failed."; the 300-character cut leaves room for the final full stop.
