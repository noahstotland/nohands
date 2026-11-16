# NH-57: Voice macros: Design

**Date:** 2026-11-16  **Ticket:** [NH-57](https://github.com/noahstotland/nohands/issues/57)
**Status:** Shipped
**Shipped:** in PR #159, with differences: [as-built](../as-built/2026-11-16-nh-57-voice-macros.md)

## Intent

Every night the user says the same four things to get the game on. This lets them name the sequence once in `config.json` and say one phrase ("night game"); NoHands runs the steps in order, as if each had been spoken, and stops at the first one that fails.

Non-goals: recording a macro by voice; editing macros from the menu; macros in app packs; arguments ("night game raptors"); running steps in parallel; a `nohands-cli` subcommand.

Anti-goals: a macro that a stop cannot end; a macro name that shadows a built-in phrase; a macro that runs another macro; a step that changes mode and leaves the rest typing into dictation; a step that goes to the network when it would not if spoken.

## How it works

### Config

```json
"macros": {
  "night game": ["open chrome", "go to streameast.app", "find raptors", "click"]
}
```

- `macros` is an object: the name is the phrase to say, the value is a list of steps, each a phrase written exactly as the user would say it (without the attention word).
- `AppConfig.macros` holds the cleaned set as a `Macros` value (`NoHandsCore`). Decoding never fails the config: a `macros` that is not an object counts as one skipped macro, and each bad macro is skipped whole.
- A macro is skipped when:
  - its name is empty after `CommandGrammar.normalize`, longer than 6 words, contains a stop word (`StopWords`, as `Vocabulary` checks), or is a phrase the built-in grammar parses with no pack in front (`CommandGrammar().parse(name) != nil`): it would never be reached, and every built-in phrase keeps working;
  - it has no steps, more than 20, or a step that is empty, over 200 characters, contains a stop word, is a mode or release phrase (`CommandGrammar.isReservedGlobal`: `start dictating`, `go to sleep`, `wake up`, …), or is the name of any macro (no recursion);
  - its name is the same as another macro's after normalization ("Night Game" and "night game"): both are skipped, since `JSONDecoder` does not keep key order and there is no "first" to prefer.
- Limit: 50 macros, kept in name order; the rest are skipped. `load` records the skipped count; the app logs `macros: skipped 2 (see docs/configuration.md)` at launch when it is not zero. The log names no macro or step.

### Matching (`Macros.match`)

- Whole phrase only: `CommandGrammar.normalize(transcript)` joined with spaces equals a normalized name. Case and `.,!?` do not matter. "night game please" or "no, night game" is not a match and routes as before.
- An unknown phrase returns nil and is left alone.

### Routing (`ModeMachine`)

- New case `Routing.macro(Macro)` (name and steps).
- Command mode only, after the attention word check (with `attentionWord` set, say "computer, night game"; bare "night game" is ignored like any command). The grammar is asked first, including the front app's pack: only when it returns nil and the phrase is not a `spell` rejection is the macro looked up, and only then does the phrase fall to `.resolveWithLLM`. A macro trigger never reaches the model.
- Dictation and sleep never match a macro: in dictation "night game" is typed.
- `ModeMachine.routeStep(_:)` routes one step: command mode, no attention word, no macro lookup (a step that happens to equal a macro name was already rejected at load; this is the second guard). It uses the same grammar (with the front app's pack, read per step) and the same `textFocused` rule as a spoken phrase.
- The merge window treats a macro name as complete (`VoicePipeline.isComplete`), so "night game" acts after the short silence like a grammar command.

### Running (`VoicePipeline`)

- `.macro` always runs inside `activeTask`, like a task, even when every step is a grammar command. That is what lets a stop end it at any step and holds other speech until it ends.
- The macro's prompt is one row on the board. For each step n of m, in order:
  1. If the pipeline is stopped or the task cancelled (`canExecute`), the macro ends: `stopped at step n of m`.
  2. The row shows `running("step n of m · <step>")`.
  3. `routeStep(step)`:
     - `.execute(actions)`: the executor runs them. A failure ends the macro: `failed("step n of m · <failure>")`. Then a 500 ms pause before the next step, so an app the step opened can come forward.
     - `.resolveWithLLM(goal)`: runs as a task on the current runner (`runTask`), on the same row. The runner's `running` lines show as `step n of m · <runner detail>`; its final line is not shown (the macro writes its own). The next step starts only after the task ends `done`. `stuck`, `failed` or `ignored` end the macro with `failed("step n of m · <why>")`; `stopped` ends it as stopped. No runner (LLM off): `failed("step n of m · <LLM-off hint>")`, before anything is sent.
     - `.reject(message)` or `.ignore`: `failed("step n of m · <message or \"not understood\">")`.
  4. If a step left command mode (a pack phrase that sets a mode; the reserved phrases were refused at load), the macro ends after it: `failed("step n of m · changed mode")`.
- All steps done: `done("done · m steps")`.
- After the macro, a held utterance runs exactly as after a task (the same loop in `startTask`).
- A stop phrase during any step goes through `busy()` unchanged: it cancels the runner and `activeTask`, discards the held utterance, and the macro ends at that step. A stop is never merged or rewritten (unchanged); the macro adds no path around it.
- A model step that asks a question (NH-47) or waits for a spoken yes (NH-61) works as it does today: the next words go to that runner through `busy()`. While it waits, the macro waits.
- Pause (`stop()`) cancels `activeTask` as today; the macro ends at its step.
- Command log: each step is an entry as if spoken, with the phrase written `night game › open chrome`. Grammar steps go through `recordCommand`, model steps through `recordTask`. The macro itself gets no extra entry.

### Follow-up memory (NH-48)

- The macro name never reaches the model, so a macro is never a follow-up and never starts one.
- Each model step is an ordinary task: it reads the follow-up memory with `FollowUp.memory` like a spoken request, and its result replaces or keeps the memory by the same rules. A step written as a follow-up ("also open the second one") follows up on the step before it, if that was a model step within `followUpWindowMs`.
- Grammar steps leave the memory alone, as spoken grammar commands do.
- After the macro, "no, the other one" refers to its last model step that kept a task. A stopped macro leaves the memory as its last finished step left it.

### Vocabulary (NH-56)

- The swap runs in `runASR`, before routing, so the spoken macro name is matched after the swap: a misheard name is fixed by a `vocabulary` entry, and a name written with the corrected spelling ("StreamEast night") matches.
- Steps are text from the config, not the recognizer, so the vocabulary is not applied to them. The user writes them spelled right.

### Tests

- `MacrosTests` (core), one table for matching: exact name, different case and punctuation, extra words do not match, unknown phrase returns nil. One table for load rules: each skip reason (stop word in name or step, built-in phrase as name, mode phrase as step, step naming a macro, empty, too many steps, step too long), the 50 cap and the skipped count.
- `AppConfigTests`: `macros` decodes; a non-object `macros` counts one skipped and leaves the rest of the config intact.
- `ModeMachineTests`, one table: a macro name routes to `.macro` in command mode; the grammar wins over a macro; the attention word is required when set; dictation types it; `routeStep` does not expand a macro.
- `VoicePipelineTests` (scripted resolver, no audio): a macro with a grammar step then a model step runs them in order and ends `done`; a stop phrase during the model step ends the macro and the third step never runs; a failing step ends the macro with `step n of m` on the row.

### Docs

- `docs/configuration.md`: a `macros` row (`{}`, up to 50 macros of 20 steps) and a bullet with the night game example, the skip rules, the attention word and the vocabulary interplay.
- `docs/voice-commands.md`: a row "`<macro name>` (from `macros` in config) | Runs its steps in order on one row (`step 2 of 4 · go to …`); a failure or a stop ends it at that step".
- `docs/tasks.md`: one line in the follow-up section that model steps in a macro are ordinary tasks for follow-ups.
- README: no change.

## Calls I made (surprising first)

- The built-in grammar wins over a macro name: a macro named after a built-in phrase is skipped at load, and one that collides with the front app's pack phrase loses in that app. No existing phrase can be hidden.
- A whole macro is skipped when any step is bad (stop word, mode phrase, another macro's name), not just that step: running half a sequence the user did not write is worse than a log line.
- Steps that change mode (`start dictating`, `go to sleep`) are refused at load; a pack phrase that changes mode at run time ends the macro after it.
- A 500 ms pause after each grammar step, fixed, not configurable; model steps need none (the task loop observes the screen).
- Model steps follow the normal follow-up rules instead of being isolated, so a step can be written as a follow-up and "no, the other one" after the macro works.
- The vocabulary applies to the spoken name, not to the steps.
- The macro row hides the inner task's final line and shows its own (`done · 4 steps`, `step 3 of 4 · stuck: …`).
- With the LLM off, grammar steps before the first model step still run; the macro fails at the model step with the usual hint.
- Command log: one entry per step, phrase `night game › <step>`, no entry for the macro itself.
- Limits I picked: 50 macros, 20 steps, 6-word names, 200-character steps.
- Two names that normalize to the same phrase are both skipped (the decoder keeps no key order to pick a winner).
- The macro name skips the merge window like a grammar command.
- Steps route without the attention word even when it is set: the user wrote them without it.
- No CLI support and no live reload (read at launch, like the other keys).
