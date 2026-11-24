# NH-104: Shrink the Claude step schema so Anthropic stops rejecting it — Design

**Date:** 2026-11-09  **Ticket:** [NH-104](https://github.com/noahstotland/nohands/issues/104)
**Status:** Shipped
**Shipped:** in PR #108, with differences: [as-built](../as-built/2026-11-09-nh-104-shrink-claude-step-schema.md)

## Intent

Every Claude call fails with HTTP 400: the step schema has 32 optional action fields and Anthropic allows 24. Send a schema Anthropic compiles, with every action still expressible, without loosening the decoder or the task guards.

Non-goals: the menu status and connection check (NH-103).

Anti-goals: a kind the decoder accepts can no longer be produced; a forced blank (`""` or `0`) ever means more than a missing field; the Ollama request changes; a fixture in `scripts/intent-eval*.json` is edited.

## The limits

Anthropic lists 24 optional and 16 union-typed parameters, plus unpublished limits on compiled grammar size. The grammar limit decides the design. Measured with `nohands-cli resolve` and a real key:

- One `anyOf` branch per field shape (24 to 51 branches): 400, grammar too large.
- A flat object with 23 optional strings: client timeout.
- **13 branches grouped by what the decoder reads, 57 fields, all required: accepted**, also with `look` (vision).

## Approach

Group kinds into 13 `anyOf` branches with every field required. A field that does not apply is sent as `""` or `0`. Field names are unchanged, so `IntentDecoder` reads the flat object as before. Rejected: one branch per kind (grammar too large; the ticket's idea) and dropping `output_config.format` (loses the validity guarantee; the fallback if the limit tightens).

## What changes

- `IntentSchema.swift`: a private `claudeSchema(kinds:)` builds the shape for both Claude schemas. The flat `orderedSchema` stays for Ollama. `predicate` is not offered.
- A `claudeFieldsRule` tells the model to send every listed field, with `""` or `0` for one that does not apply. `ClaudeRequestBuilder.systemText` appends it, so the Ollama prompt is unchanged and the cached system block stays stable.
- `IntentDecoder.swift`: blanks must never gain meaning.
  - A blank required target or name still drops the action.
  - `dragSource` rejects `from_x` and `from_y` both `0`, or a blank drag would start at the top-left corner.
  - `0` in an integer field means omitted (`optInt`), so defaults apply: `count` and `scroll` 1, `scroll_element` 3, `wait` 1000 ms, `timeout_ms` 5000.
  - `set_value` and `clipboard_set` with a blank `value` and a filled `text` or `option` are dropped, since clearing would destroy data. A `set_value` with nothing else filled still clears.

## Tests

Table-driven: both schemas stay within the limits and within 13 branches and 57 fields (re-run the live check before raising); every kind is reachable; blank target, name and drag source decode to nothing; the Claude `output_config.format` is stable across requests. Manual, in the PR: a live `nohands-cli resolve` returns an intent, and `nohands-cli eval` on both fixture files (54, a few cents) shows no accuracy loss.

## Risks

- The grammar limit is unpublished; new kinds should join an existing branch.
- A `click` carries about 12 fields (50 more tokens). `max_tokens` is 2048, about twenty clicks; a longer step is cut off and runs nothing.

## Calls I made

- **Blanks and 13 merged branches, not one branch per kind.** Anthropic rejects that on grammar size.
- **Three stricter decoder changes:** a `0,0` drag source is rejected, `0` in `optInt` means omitted, and a misfiled blank `value` drops `set_value` and `clipboard_set`. The last two came from code review.
- **Ollama keeps its flat schema and prompt.**
- **A tripwire at 13 branches and 57 fields**, because the optional count alone passed rejected shapes.
- **`max_tokens` rises from 1024 to 2048** for real steps; the connection check stays 1.
- **Key order is fixed (added during the build).** A Swift dictionary scrambled the schema keys; Claude Haiku scored 37% and 0% on the two fixture files scrambled and 70% and 78% in order. `ClaudeRequestBuilder` now builds `OrderedJSON`, also byte-stable for the prompt cache.
