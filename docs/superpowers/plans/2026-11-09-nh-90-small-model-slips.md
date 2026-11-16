# NH-90: Small-model slip guards: Plan

**Spec:** `docs/superpowers/specs/2026-11-08-nh-90-small-model-slips-design.md` (approved). Ticket [NH-90](https://github.com/noahstotland/nohands/issues/90).

All new logic is pure and lives in `NoHandsCore`, unit tested table-style. Never edit `scripts/intent-eval*.json`.

## File map

- Typed-address guard: `WebAddress.typedAddress`, `TypedAddressGuard.rewrite` (whole-text address becomes `open_url`; the Return after it is dropped).
- Menu-bar guard: `MenuBarGuard.blocked`, `ElementNames.bind`, `ScreenObservation.menuBarTitles`.
- Element list: `LabelAssigner.menuBarLast`, applied in `ScreenObserver.observeNative` for the task loop only, not while badges show.
- `TaskRunner.run`: rewrite before `repeats.record`; bind names on the running actions; `MenuBarGuard` after `ShortcutGuard` and `TabGuard`.
- Repeat nudge in `ClaudeRequestBuilder.userBlocks` after two identical non-empty steps ("a third identical step ends the task"); both backends.
- The typed-address rewrite is off for text-entry goals and for `type_text` after `open_app` or `command-l`; `type_into`, `set_value` and `search` are never rewritten.
- Prompt and `IntentExamples`: prefer `open_url`; local-only `localNamedTargetRule`; fictional channel `@mapleridgeworkshop`; Xcode example stays last.

## Verify

`swift build` and `swift test` pass; `scripts/intent-eval*.json` unchanged. Live and model checks are listed in the PR, not faked.
