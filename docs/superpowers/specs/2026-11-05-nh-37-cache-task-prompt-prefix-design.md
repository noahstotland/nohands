# NH-37: Cache the task loop's prompt prefix on the Claude path — Design

**Date:** 2026-11-05  **Ticket:** [NH-37](https://github.com/noahstotland/nohands/issues/37)
**Status:** Shipped
**Shipped:** in PR #62, as specified

## Intent

Every request sends the same system prompt (about 2,200 tokens) and schema uncached. This marks that prefix for prompt caching and logs cache hits from the response's `usage`.

## The catch in the ticket's breakpoint plan

The ticket asks for a breakpoint after the last history block, but `Step: n of m` sits before the history and changes every step, so that prefix never repeats. The breakpoint would write a cache entry (1.25× input price) that nothing reads. Moving `Step` would fix it but changes the prompt, which is out of scope (a follow-up).

So only the system prompt and schema are cached. The user message is still split into blocks as the ticket asks, with no breakpoint in the messages.

## Design

### Request body (`ClaudeRequestBuilder`)

- `system` becomes one text block with `cache_control: {"type": "ephemeral"}`.
- `userBlocks(request:)` splits the user message into the goal block (`Goal`, `Step`), one block per history record (the first with the `History:` header), and the observation block (`App:` through `Request:`).
- `userMessage(request:)` is the joined blocks, byte-identical to before (golden test in `IntentStepTests`).
- `body(request:)` sends one content entry per block, with no `cache_control`. One-shot bodies get the same cached system block. The Ollama path is unchanged.

### Usage (`ClaudeUsage`, NoHandsCore)

`inputTokens`, `cacheReadTokens` and `cacheWriteTokens` (the response's `cache_read_input_tokens`, `cache_creation_input_tokens`). `ClaudeUsage.from(response:)` is nil without a usage object; a missing field reads 0.

### Log line (`ClaudeIntentResolver`)

After a 2xx, before decoding, one public `PipelineLog.info` line: `claude: step <n> <ms>ms cache=<read>/<written> in=<input>` (for example `claude: step 2 1480ms cache=2214/0 in=612`; `cache=-` without usage). The time is to the full response (not streamed). No transcript, goal, element or model text goes in it.

## Testing

Pure-logic tests, no network: the body (one cached system block, `2 + history.count` uncached user blocks, joined text equal to the golden message), the one-shot body, and a `ClaudeUsage.from` table.

Manual (needs a key): a 3-step `nohands-cli task`; steps 2 and 3 must show `cache=` read > 0. Record step times before and after in the as-built.

## Leaves out

Prompt, message order or schema changes; caching the history; shrinking the element list; streaming; Ollama changes.

## Calls I made

- **No breakpoint after the history**: it could never be read and would add a write every step.
- **The user message is still split**, so a follow-up can add the history breakpoint in one line.
- **Cache numbers get their own log line,** since the app has no per-step line.
- **The 512-token minimum and 5-minute lifetime** come from the ticket, checked against the Anthropic docs. A server-side fallback to another model misses the cache; accepted.
