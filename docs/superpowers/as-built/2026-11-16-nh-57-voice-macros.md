# As-built: Voice macros

**Shipped:** in PR #159
**Ticket:** NH-57
**Spec:** [2026-11-16-nh-57-voice-macros-design.md](../specs/2026-11-16-nh-57-voice-macros-design.md)

## Differs from the spec

- The spec skips a macro whose name the built-in grammar parses. It also skips one whose name the grammar rejects (a `spell …` phrase), since routing never reaches the macro lookup for it.
- Macro names are stored normalized (lower case, no `.,!?`).
- The "a step names a macro" rule checks every macro name in the config, including macros that are themselves skipped.
- The 500 ms pause follows a successful grammar step only, and not the last step.
- `ModeMachine` takes the macros in its initializer; there is no `use(macros:)` (macros are read at launch).
- A spoken stop during a model step goes through the normal task path, so it clears the follow-up memory unless the step was a follow-up (the spec said a stopped macro keeps the memory its last finished step left).
- A grammar step's reading (`is it playing`) is discarded; it is not shown on the macro row.
