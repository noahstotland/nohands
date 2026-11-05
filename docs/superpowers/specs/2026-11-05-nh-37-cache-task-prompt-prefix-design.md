# NH-37: Cache the task loop's prompt prefix on the Claude path — Design

**Date:** 2026-11-05  **Status:** Shipped  **Ticket:** [NH-37](https://github.com/noahstotland/nohands/issues/37)
**Shipped:** in PR #62, as specified

## Intent

Every task step, and every one-shot command, sends the same system prompt (about 2,200 tokens) and the same
JSON schema to Claude with no cache marker. Each request pays full input price and full time to first token
for that prefix. This change marks the stable prefix for Anthropic prompt caching, reads the response's
`usage` block, and logs cache hits so they can be checked on a real task.

## Today

- `ClaudeRequestBuilder.body(request:)` (`Sources/NoHandsCore/ClaudeRequestBuilder.swift`) sends `system` as
  one string (`IntentSchema.systemPrompt(for: harness)`), `output_config.format` with
  `IntentSchema.actionsJSONSchema`, and one user message whose `content` is the string from
  `userMessage(request:)`. No `cache_control` anywhere.
- `userMessage(request:)` builds, in this order: `Goal: …`, `Step: n of m`, `History:` with one line per
  record, `App/Window/URL`, `Mode/Overlay/Harness`, `Surface`, `Windows`, `Visible elements`, `Read`, and the
  `Request:` line.
- `OllamaRequestBuilder` uses the same `userMessage` string for its last user turn and keeps its prefix warm
  through Ollama's own cache (`warmBody`, `WarmPolicy`).
- `ClaudeIntentResolver.resolve` (`Sources/NoHandsMac/ClaudeIntentResolver.swift`) decodes the step with
  `IntentDecoder.step(fromResponse:)` and ignores `usage`. There is no per-step `PipelineLog` line in the app;
  the CLI prints steps through `TaskRunner.onStep`.
- Both one-shot callers (`VoicePipeline` through `IntentResolving.resolve(_:context:)`, and the CLI `resolve`
  and `eval` commands) go through the same resolver and builder as the task loop.

## The catch in the ticket's breakpoint plan

Prompt caching matches a prefix. The ticket asks for a breakpoint after the last history block and requires
the concatenated text to stay byte-identical to `userMessage`. But `Step: n of m` sits between the goal and
the history, and it changes on every step. The prefix up to the last history block is therefore different on
every request, so a breakpoint there writes a cache entry (at 1.25× input price) that no later request can
read. Moving the `Step` line below the history would fix that, but it changes the prompt text, which the
ticket puts out of scope and which would need the intent fixtures re-run.

So this change caches what can actually be reused under the ticket's constraints: the system prompt and
schema. It splits the user message into blocks as the ticket asks, but puts no breakpoint in the messages.
See § Calls I made.

## Approaches

1. **Breakpoint on the system block only; user message split into blocks; usage parsed in Core and logged
   by the resolver.** Gets the large saving (about 2,200 of the prompt's tokens on every request, task step
   or one-shot) with no wasted cache writes and no prompt change. Chosen.
2. **As 1, plus the ticket's breakpoint after the last history block.** Rejected: it never hits (see above)
   and adds a cache write on every step.
3. **Move `Step: n of m` below the history so the history prefix is stable, then add the history
   breakpoint.** Rejected for this ticket: it changes the prompt wording and order, which is out of scope, and
   breaks the byte-identical rule. A good follow-up once caching is measured.

## Design

### Request body (`NoHandsCore/ClaudeRequestBuilder.swift`)

- `system` becomes an array with one text block:
  `[{"type": "text", "text": <systemPrompt(for: harness)>, "cache_control": {"type": "ephemeral"}}]`.
  The native and harness prompts are different texts, so each caches as its own entry.
- New `public static func userBlocks(request:) -> [String]`, which returns the user message in pieces:
  1. the goal block: `Goal: …\nStep: n of m\n`;
  2. one block per history record; the first also carries the `History:\n` header
     (`"History:\n  1. …\n"`, then `"  2. …\n"`, …);
  3. the observation block: everything from `App:` through the `Request:` line.
- `userMessage(request:)` becomes `userBlocks(request:).joined()`. Its output stays byte-identical to today,
  and the existing golden test in `IntentStepTests` keeps pinning those bytes.
- `body(request:)` sends the user message as `content: [{"type": "text", "text": block}, …]`, one entry per
  block, with no `cache_control` on them.
- `output_config` (effort and schema), `max_tokens`, `fallbacks` and headers stay as they are.
- `body(transcript:context:)` keeps delegating to `body(request:)`, so one-shot commands get the same cached
  system block.

### Usage (`NoHandsCore`, new `ClaudeUsage`)

```swift
public struct ClaudeUsage: Equatable, Sendable {
    public var inputTokens: Int          // uncached input after the last breakpoint
    public var cacheReadTokens: Int      // cache_read_input_tokens
    public var cacheWriteTokens: Int     // cache_creation_input_tokens
    /// nil when the response has no usage object; a missing field reads as 0.
    public static func from(response data: Data) -> ClaudeUsage?
}
```

It reads only numbers. It never reads or returns text from the response.

### Log line (`NoHandsMac/ClaudeIntentResolver.swift`)

- The resolver times `IntentHTTP.send` with the continuous clock. The request is not streamed, so this is the
  time to the full response, which for these short outputs is about the time to first byte.
- After a 2xx response it logs one public line through `PipelineLog.info`:
  `claude: step <n> <ms>ms cache=<read>/<written> in=<input>`, for example
  `claude: step 2 1480ms cache=2214/0 in=612`. If `usage` is missing it logs `cache=-`. No transcript, goal,
  element or model text goes in it.
- The line is logged before decoding, so a malformed step still shows its cache numbers.
- `IntentStep` and `IntentResolving` don't change. The CLI `task` command shows the line too, because
  `PipelineLog` mirrors to the terminal.

### Ollama path

No change. `OllamaRequestBuilder` keeps using the single `userMessage` string, which stays byte-identical.

## Testing

Pure-logic tests in `NoHandsCoreTests`, no network:

- **Request body** (one test, both harness kinds and a 3-record history): `system` is a one-block array whose
  text equals `systemPrompt(for:)` and which carries `cache_control: {type: ephemeral}`; the user content has
  `2 + history.count` blocks, history blocks in order; no user block carries `cache_control`; the blocks'
  texts joined equal the existing golden `userMessage` string.
- **One-shot body**: `body(transcript:context:)` has the same cached system block.
- **`ClaudeUsage.from`**, table-driven: a full usage object, cache fields missing (0), no `usage` (nil),
  non-JSON (nil).
- The existing `userMessage` golden test and the Ollama request tests keep passing unchanged, which proves the
  Ollama body didn't change.

Manual (listed in the PR, needs an API key): run a 3-step task with `nohands-cli task …` and record each
step's log line. Steps 2 and 3 must show `cache=` read > 0 (the first one-shot or step 1 may already hit if a
request ran in the last 5 minutes). Record the per-step times before (on `main`) and after in the as-built.

## Leaves out

- Any change to the prompt wording, the order of the user message, or the schema.
- Caching the history (needs the `Step` line moved; see Approach 3).
- Shrinking the element list.
- Streaming, or a real time-to-first-byte measure.
- Any change to the Ollama request.

## Calls I made

- **No breakpoint after the history.** The ticket asks for one, but the `Step: n of m` line before the
  history changes every step, so that breakpoint could never be read and would add a cache write to every
  step. Only the system block gets a breakpoint. Moving the `Step` line to make the history cacheable is left
  for a follow-up ticket, because it changes the prompt.
- The user message is still split into goal / history / observation blocks as the ticket asks. It has no
  effect on cost today, but the follow-up can then add the history breakpoint with a one-line change.
- The `Step` line stays in the goal block, and the `History:` header goes in the first history block.
- The cache numbers are logged from the resolver as their own `claude: step …` line, because the app has no
  per-step log line today. `IntentStep` stays as it is.
- The time logged is the time to the full response, not a true time to first byte, because the request isn't
  streamed.
- Usage is parsed in Core (`ClaudeUsage`) so it can be unit tested. The log line itself isn't tested.
- The 512-token minimum and the 5-minute lifetime come from the ticket and will be checked against the
  Anthropic docs during build. If the server-side fallback answers with another model, that request misses
  the cache; that's accepted.
