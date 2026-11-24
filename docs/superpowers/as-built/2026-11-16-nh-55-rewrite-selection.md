# As-built: Rewrite the selection with the model

**Shipped:** in PR #160
**Ticket:** NH-55
**Spec:** [2026-11-16-nh-55-rewrite-selection-design.md](../specs/2026-11-16-nh-55-rewrite-selection-design.md)

## Differs from the spec

- `ModeMachine.namesTextEdit` is unchanged; a new `ModeMachine.namesRewrite` asks the pipeline for the focused-field check, in command mode only. Making `namesTextEdit` true for rewrites would have made them dictation commands.
- `rewrite that` and `make it clearer` are the same instruction (`.style(.clearer)`, "Rewrite it to read more clearly.").
- Line breaks in an answer collapse into one space when the selection had none (a blank line gives one space, not two).
- Tabs in an answer always become spaces (the spec kept them when the source had one), and when the source has line breaks the answer's are typed as Shift-Return between typed lines, never as a text segment that would press a plain Return (the spec said line breaks are kept as text).
- The done row ends in `…` only when the answer is longer than six words.
- The `rewriting…` row shows only after the field read, subject choice and cap check pass, so a refused rewrite never shows it.
- The "rewrite needs a model" and "rewrite is off" messages are chosen when the pipeline sets the rewriter, which also follows a live backend switch from the menu.
- A stop while the answer is being typed leaves what was typed so far; `undo` removes it. A stop during the model wait types nothing.
- `rewrite …` and `translate … to …` keep the full silence window (`CommandGrammar.opensRewrite`, `carriesSpokenText`), so a paused instruction merges into one utterance; the presets still close early.
