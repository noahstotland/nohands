# NH-104: Shrink the Claude step schema so Anthropic stops rejecting it — Design

**Date:** 2026-11-09  **Ticket:** [NH-104](https://github.com/noahstotland/nohands/issues/104)
**Status:** Shipped
**Shipped:** in PR #108, with differences: [as-built](../as-built/2026-11-09-nh-104-shrink-claude-step-schema.md)

## Intent

Every Claude call fails with HTTP 400, because the step schema has 32 optional action fields and Anthropic allows 24.
Natural-language commands and tasks do not work on the Claude backend at all. Send Claude a schema that Anthropic
compiles, with every action still expressible, without loosening the decoder or the task guards.

## Goals and non-goals

Goals are the ticket's Scope and Acceptance. Non-goals are its Out of scope: the menu status and connection check
(NH-103) and logging the HTTP error body.

Anti-goals, which would make this a failure even if the tests pass:

- A kind the decoder accepts today can no longer be produced by Claude.
- A blank value the new schema forces the model to send turns into an action that runs. A field filled with `""` or
  `0` must never mean more than a missing field did.
- The Ollama request changes, so the local model's measured pass rate no longer applies.
- A fixture in `scripts/intent-eval*.json` is edited.

## What the limits really are

Anthropic's structured-outputs page lists two limits for a request: 24 optional parameters and 16 parameters with
union types (`anyOf` or a type array). It also says there are internal limits on compiled grammar size that it does
not publish. The second one is what decides this design, so I measured it with `nohands-cli resolve` and a real key,
using throwaway patches that are not on this branch.

| Shape sent as `actions.items` | Size | Result |
|---|---|---|
| Today's single object | 1 object, 32 optional | 400, too many optional parameters |
| One `anyOf` branch per field shape | 40 branches, 14 optional | 400, grammar too large |
| Same, `drag` expanded to remove its optionals | 51 branches, 0 optional | 400, grammar too large |
| Same, native and tab kinds only | 24 branches | 400, grammar too large |
| Grouped more loosely, all fields required | 20 branches, 79 fields, 0 optional | 400, grammar too large |
| Single flat object, 9 required strings, 23 optional | 1 object | Client timeout, no answer |
| Subset of kinds, per-field-shape | 15 branches, about 56 fields | Accepted |
| **Grouped by what the decoder reads, all fields required** | **13 branches, 57 fields, 0 optional** | **Accepted, returns an intent** |
| The same with `look` added (the vision schema) | 13 branches, 57 fields | Accepted, returns an intent |

The per-kind `anyOf` the ticket suggests clears the optional limit and then fails on grammar size. The chosen shape is
the smallest change that passed.

## Approaches

1. **Group kinds into 13 `anyOf` branches with every field required (chosen).** Kinds that read similar fields share
   a branch. A field that does not apply is sent as `""` or `0`. The field names stay exactly as they are, so the
   model's output is still one flat object and `IntentDecoder` reads it the same way.
2. **One branch per kind or per field shape.** Clearest for the model, and rejected by Anthropic (table above).
3. **Single flat object with some fields made required.** Timed out, and every action would carry about 30 fields.
4. **Drop `output_config.format`, or send each action as a JSON string.** Compiles trivially, but gives up the
   guarantee of valid JSON and the `kind` enum, and needs decoder changes. Worth keeping as the fallback if the
   grammar limit tightens.

## What changes

### `Sources/NoHandsCore/IntentSchema.swift`

A new private `claudeSchema(kinds:)` builds the Claude shape. `actionsJSONSchema` and `visionActionsJSONSchema` use it
(same names, so NH-103 picks it up). `orderedSchema` and `orderedSchema(for:)` keep today's flat shape and are not
touched. `intent`, `status` and `actions` stay required at the top.

| # | Kinds | Fields besides `kind` |
|---|---|---|
| 1 | `show_grid`, `show_labels`, `hide_overlay`, `ignore`, `read_clipboard`, `read_notifications` (and `look` with vision) | none |
| 2 | `type_text`, `search` | `text` |
| 3 | `press_key` | `key`, `modifiers` |
| 4 | `click`, `move_cursor`, `drag`, `press_mouse`, `release_mouse` | `target_kind`, `target_number`, `target_name`, `x`, `y`, `dx`, `dy`, `button`, `count`, `from_number`, `from_name`, `from_x`, `from_y` |
| 5 | `scroll`, `scroll_element` | `target_kind`, `target_number`, `target_name`, `direction`, `amount` |
| 6 | `set_mode` | `mode` |
| 7 | `open_app`, `close_app`, `dismiss_notifications`, `open_url` | `app_name`, `url` |
| 8 | `move_window` | `placement` |
| 9 | `wait` | `ms` |
| 10 | `wait` | `wait_for`, `event`, `value`, `timeout_ms`, `target_kind`, `target_number`, `target_name` |
| 11 | `zoom_grid`, `close_tab`, `close_window`, `select_tab`, `clear`, `check`, `uncheck`, `toggle`, `expand`, `collapse`, `focus`, `scroll_to`, `read_value`, `set_value`, `type_into`, `select`, `clipboard_set` | `target_kind`, `target_number`, `target_name`, `value`, `text`, `option` |
| 12 | `click_in`, `menu_item` | `surface`, `target_name` |
| 13 | `window` | `window_action`, `app_name`, `title` |

In branches 5, 10 and 11, `target_kind` is limited to `label` and `element`. Branch 4 takes the full `targetKinds`
list. `predicate` is not offered, because the harness prompt already puts the predicate in `value` and the decoder
reads `value` first. The `app_name` the prompt lists for `wait` with `wait_for` is also not offered: the decoder has
never read it.

A new `claudeFieldsRule` string says that every listed field must be sent, that a field that does not apply or that
the instructions say to omit is `""` or `0`, and that an enum field that does not apply takes any value and is
ignored. `ClaudeRequestBuilder.systemText` appends it next to `tabKindsRule`, so the Ollama prompt does not change.
The rule is the same on every request, so the cached system block stays stable.

### `Sources/NoHandsCore/IntentDecoder.swift`

One tightening. `dragSource` rejects `from_x` and `from_y` when both are `0`. Without this, a `drag` with all four
source fields blank, which used to be dropped, would drag from the top-left corner of the screen.

I walked every other kind against blanks and nothing else changes meaning:

- `0` fails `number()`, and `""` fails `nonBlank`, so a required target or name that is blank still drops the action.
- Fields a kind does not read are ignored, and `target_kind` decides which target field is used.
- A `0` in an integer field means the field was omitted (`optInt`), so its default applies: `count` and `scroll` `amount`
  1, `scroll_element` `amount` 3, `wait` `ms` 1000, `timeout_ms` 5000.
- `set_value` and `clipboard_set` with a blank `value` and a filled `text` or `option` are dropped: branch 11 shares
  those fields, so the model put the text in the wrong one, and clearing the field or clipboard would destroy data. A
  `set_value` with nothing else filled still clears, as before.
- A blank `app_name` means no app, which is the meaning of leaving it out. A blank wait-element `value` falls through
  to `exists`.

### Tests (`Tests/NoHandsCoreTests/`)

- **Limits, table-driven over `actionsJSONSchema` and `visionActionsJSONSchema`:** optional parameters are at most 24
  and union parameters at most 16, counted by walking the schema, with the limits named and linked to the docs page.
  Branches at most 13 and fields at most 57: the largest shape a live call has accepted, since no published number
  covers grammar size. The test comment tells whoever hits it to re-run the live check before raising it.
- **Every kind is reachable, table-driven:** one sample action per kind, with blanks filled the way the schema forces.
  Each must match exactly one branch's kinds and fields, and decode to the expected `Action`. The branches' kinds must
  equal `IntentSchema.kinds` exactly, with `look` only in the vision schema.
- **Blank values do not act, table-driven:** a blank target, blank name and a blank drag source each decode to no
  action.
- **Stability:** two Claude bodies for different requests carry an identical `output_config.format`.
- **Retargeted:** `OllamaIntentTests` line 21 and `schemaListsNewKindsAndFieldsAndStaysClosed` read the flat shape
  from `actionsJSONSchema`, so they move to `orderedSchema.foundationObject`. They keep their assertions, and the flat
  shape is still what Ollama receives. `schemaHasNoRecursionAndClosesObjects` and `decodesEveryKind` do not change.

### Manual checks, listed in the PR

- `nohands-cli resolve "open the downloads folder"` with a real key returns an intent.
- `nohands-cli eval` on both fixture files against Claude Haiku, 54 fixtures, a few cents of API credit, to see that
  the blank-filling rule does not hurt accuracy.

## Risks

- Anthropic does not publish the grammar limit, so it could change. The test catches our own growth, not theirs. A new
  action kind should join an existing branch wherever it can.
- Actions get longer. A `click` now carries about 12 fields, roughly 50 more output tokens. `max_tokens` is 2048, which
  still fits around twenty clicks in one step. A much longer step would be cut off and fail to decode, so it would run
  nothing.
- A branch shared by unrelated kinds asks the model to fill irrelevant fields. The live calls behaved, but a one-shot
  sample is not a measurement, which is why the eval run is listed.

## Calls I made

- **Blanks instead of optional fields, and 13 merged branches instead of one per kind.** The ticket suggested one
  object per kind. Anthropic rejects that on grammar size, measured above.
- **One decoder change, rejecting a `0,0` drag source.** The ticket allowed decoder changes only to match the shape.
  This makes it stricter, and a real drag from the exact screen corner is no longer possible.
- **Ollama keeps its flat schema and prompt.** The ticket left this open. Its request is unchanged, so its pass rate
  stands and the local fixtures have nothing new to catch. Two existing tests are retargeted to say so.
- **A Claude-only prompt rule** explains the blanks, rather than editing the shared prompt.
- **A tripwire test at 13 branches and 57 fields**, beyond the optional-count test the ticket asked for, because that
  count alone passed shapes Anthropic still rejected.
- **The eval against Claude spends a few cents of real credit.** The ticket only required the local model's eval.
- **`max_tokens` is raised from 1024 to 2048** for real steps (the connection check stays 1), so a long step is not cut off
  and dropped; a test pins it.
- **Key order is fixed in this PR (changed during the build).** The spec first left it alone, because it does not cause
  the 400. The live eval showed it matters: `foundationObject` goes through a Swift dictionary, so the keys came out
  scrambled (`kind` late in a branch, `actions` before `status`). Claude Haiku scored 37% and 0% on the two fixture
  files with the scrambled order and 70% and 78% with the declared order kept. `ClaudeRequestBuilder` now builds the
  whole request as `OrderedJSON`, which also makes the request byte-stable for the prompt cache. A test pins the order.
