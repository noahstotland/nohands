# NH-104: Shrink the Claude step schema: Plan

**Spec:** `docs/superpowers/specs/2026-11-09-nh-104-shrink-claude-step-schema-design.md` (approved). Ticket [NH-104](https://github.com/noahstotland/nohands/issues/104).
Branch `feat/nh-104-shrink-claude-step-schema`. Test: `swift test`. Typecheck: `swift build`.

All logic stays in `NoHandsCore` (no AppKit or network). Never edit `scripts/intent-eval*.json`. Test lines stay under the feature lines (`AGENTS.md` § Testing).

## Task 1: Claude schema (`IntentSchema.swift`)

- Add private `claudeSchema(kinds:)` with the 13 branches in the spec's table, every property required, `additionalProperties: false`, inside `actions.items.anyOf`. A branch is dropped when none of its kinds is in `kinds`; a branch's `kind` enum lists only its kinds that are in `kinds`. `intent`, `status`, `actions` stay required at the top, in that order.
- `actionsJSONSchema` = `claudeSchema(kinds: kinds)`, `visionActionsJSONSchema` = `claudeSchema(kinds: kinds + ["look"])`. `orderedSchema`, `orderedSchema(for:)` and `schema(kinds:)` are untouched.
- Add `claudeFieldsRule` (every listed field must be sent; `""` or `0` for a field that does not apply or that the instructions say to omit; an enum field that does not apply takes any value and is ignored). Append it in `ClaudeRequestBuilder.systemText` after `tabKindsRule`. The Ollama prompt does not change.

## Task 2: Decoder (`IntentDecoder.swift`)

`dragSource`: a `from_x`/`from_y` pair of `0,0` is not a source (returns nil). No other decoder change.

## Task 3: Tests

- Retarget `OllamaIntentTests` (the `actionsJSONSchema` comparison, line ~21) and `schemaListsNewKindsAndFieldsAndStaysClosed` (`IntentHarnessTests`) to `IntentSchema.orderedSchema.foundationObject`.
- Table test over both Claude schemas: optional parameters <= 24, union parameters (`anyOf` or type arrays) <= 16 (counted by walking the schema; limits named with the docs link in a comment), branches <= 13, total fields <= 57 (comment: largest shape a live call accepted; re-run the live check before raising).
- Table test: a sample action per kind (all fields filled, blanks where the schema forces them) matches exactly one branch's kinds and required fields, and decodes to the expected `Action`. Branch kinds equal `IntentSchema.kinds`; `look` only in the vision schema.
- Table test: blank targets, blank names and a `0,0` drag source decode to no action.
- One test: Claude request bodies for two different requests carry an identical `output_config.format`.

## Task 4: Live checks (manual, listed in the PR)

- `.build/debug/nohands-cli resolve "open the downloads folder"` returns an intent.
- `nohands-cli eval scripts/intent-eval.json` and `scripts/intent-eval-disfluent.json` against Claude Haiku; report pass counts. Do not edit fixtures. Report any failure in the PR under Not proven or Proof.
