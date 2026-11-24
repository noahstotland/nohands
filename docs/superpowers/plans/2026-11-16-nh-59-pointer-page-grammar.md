# NH-59: Grammar for pointer and page control: Plan

Spec: `docs/superpowers/specs/2026-11-16-nh-59-pointer-page-grammar-design.md` (approved).

1. **Core grammar** (`CommandGrammar.swift`): exact entries `top of page`/`top of the page` (command-up), `bottom of ...` (command-down), `zoom in` (command-equals), `zoom out` (command-minus), `actual size`/`reset zoom` (command-0), `move to center`/`centre`/`the center`/`the center of the screen`. In `parseFind`, top and bottom edges (`scrollEdges` top forms/bottom forms) return command-up/down; left/right/up/down stay nil. `drag <n> to <m>` and `drag from <n> to <m>` (numbers only, split at first `to`), `click <n> and hold` (number only; moveCursor then pressMouse).
2. **Core resolver**: `MoveTarget.screenCenter`, resolved in `TargetResolver.resolveMove` to the midpoint of the screen holding the cursor, else first screen, else failure `no screen`. Fix any exhaustive switch the build finds.
3. **Mac**: native drag in `ActionExecutor+Harness.swift` paced (press, ~100 ms, 10 dragged moves ~15 ms apart, ~50 ms, release), always releasing on a throw, hiding a used overlay. A stop phrase in `VoicePipeline` releases a held button (`executor.releaseHeldButton()` calls `input.releaseAll()` without hiding the overlay), task or not, and still halts the task as before.
4. **Tests** (table-driven, Core only): `CommandGrammarTests` (new phrases plus must-not-change rows), `TargetResolverTests` (`.screenCenter`).
5. **Docs**: `docs/voice-commands.md` rows per spec § Docs.
6. Verify: `swift build`, `swift test`, both intent fixture evals unchanged.
