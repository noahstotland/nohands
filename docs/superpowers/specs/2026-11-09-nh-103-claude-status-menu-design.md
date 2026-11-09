# NH-103: Claude status in the menu and a "Check Claude connection" test: Design

**Date:** 2026-11-09  **Ticket:** [NH-103](https://github.com/noahstotland/nohands/issues/103)
**Status:** Shipped
**Shipped:** in PR #105, as specified

## Intent

After adding a key, nothing in the app says whether Claude is set up or whether the key works. The menu gets a Claude
line that needs no network, plus a check the user runs on demand from the menu or `nohands-cli claude-check`.

The check has to answer the real question: will my commands work? The user's own run shows why that is more than "is
the key valid". With a valid key, `nohands-cli resolve "open the downloads folder"` fails with HTTP 400:

> Schemas contains too many optional parameters (32), which would make grammar compilation inefficient. Reduce the
> number of optional p...

A check that only proved the key would say "connected" while every Claude command fails.

## What changed since the ticket was written

- **The 400 above.** The ticket's outcome list has no case for it, and its rule that no response body is ever shown
  would hide it. This spec adds a `request rejected` result and shows the API's error message (see
  [Showing the API's message](#showing-the-apis-message)).
- **The error text was cut off by our own code.** `ClaudeIntentResolver` keeps only the first 200 characters of an error
  body, which is why the quote stops at "optional p...". The check reads the body itself and does not go through
  `IntentError.http`.

## Goals, non-goals, anti-goals

Goals are the ticket's Scope and Acceptance, with the two changes above.

Non-goals:

- Fixing the schema. That is a separate ticket (see [Follow-ups](#follow-ups)).
- Entering or changing the key from the menu (#94).
- A check for the local Ollama model, saving the last result to disk, spend counters.
- Proving the model returns valid actions. The check stops at the HTTP status.

Anti-goals, which would make this a failure even if it works:

- The key appearing anywhere: menu, CLI, log, error, test output.
- Any network traffic the user did not ask for: at launch, on a timer, when the menu opens or when the pipeline starts.
- Reporting `connected` when a real command would be refused.

## Approaches

1. **Send the app's real step request with `max_tokens` of 1 (chosen).** Same URL, headers, model, effort, system prompt
   and schema as a real step, so it fails when a real step fails. It costs about the input of one real step and one
   output token.
2. **The ticket's minimal request, one word and no schema.** The cheapest, but it would report `connected` today while
   every Claude command returns 400. It also would not catch a bad `intentEffort` or a future schema problem.
3. **Minimal request first, then the real one.** Could separate "key bad" from "request bad", but the status code and
   message already do that, for a second call and more code.

## How it works

### Key source (`AppConfig`, NoHandsCore)

`AppConfig` gains `anthropicKeySource: KeySource?` (`.file` or `.environment`), left out of `CodingKeys` and set only by
`load`: `.environment` when `ANTHROPIC_API_KEY` is non-empty, else `.file` when the decoded key is non-empty, else nil.

### Probe body (`ClaudeRequestBuilder`, NoHandsCore)

`body(request:)` gains `maxTokens: Int = 1024`. A new `connectionCheckBody()` builds a fixed `StepRequest` (goal `ping`,
no elements, no screenshot) with `maxTokens: 1`, and with the builder's normal `vision` flag so the schema matches what
the app sends. It reads no screen.

### Status and results (`ClaudeStatus`, NoHandsCore, Foundation only)

`ClaudeCheckResult` holds a kind and an optional `detail`. A pure function maps a status code and body to it:

| Outcome | Kind | Menu text (`14:32` is the check time, passed in as a string) |
|---|---|---|
| 2xx | connected | `Claude: connected at 14:32` |
| 400 | requestRejected | `Claude: request rejected at 14:32: <first 70 characters of detail>` |
| 401, 403 | keyRejected | `Claude: key rejected at 14:32, check anthropicAPIKey` |
| 404 | modelNotFound | `Claude: model not found at 14:32, check intentModel` |
| 429 | rateLimited | `Claude: rate limited at 14:32, try again soon` |
| other HTTP codes | unavailable(code) | `Claude: unavailable at 14:32 (HTTP 529), try again later` |
| deadline | timedOut | `Claude: timed out at 14:32, check your connection` |
| transport error | noNetwork | `Claude: no network at 14:32, check your connection` |
| no key | noKey | none: the plain status line covers it and the item is disabled |

The plain status line, from the config alone:

| `intentBackend` | Key | Line |
|---|---|---|
| auto or claude | set | `Claude: key set (config.json)` or `Claude: key set (ANTHROPIC_API_KEY)` |
| auto | missing | `Claude: no key, using the local model` |
| claude | missing | `Claude: no key, LLM off (add anthropicAPIKey)` |
| local or off | either | `Claude: not used (intentBackend = local)` (or `off`) |

A key with no recorded source reads `Claude: key set`. A last result, when there is one, replaces the plain line.

### Showing the API's message

`detail` is built for every non-2xx response, in this order:

1. Parse the body as JSON and read `error.type` and `error.message`. A body that is not JSON, or is over 64 KB, gives no
   detail, so a proxy's HTML page never reaches the menu.
2. Replace every occurrence of the configured key, and anything matching `sk-ant-[A-Za-z0-9_-]+`, with `[hidden]`.
3. Turn control characters into spaces, which also strips terminal escape sequences, and collapse whitespace.
4. Cap at 500 characters. Redaction comes before any cut, so a truncated key can't survive.

The detail is only displayed. It is never logged, never sent to a model and never parsed for actions. `PipelineLog`
gets the kind and status code and nothing else.

### The check (`ClaudeConnectionCheck`, NoHandsMac)

Next to `ClaudeIntentResolver`, with the same `session`, `baseURL` and `deadline` test seams. The `URLRequest` setup
moves out of `resolve` into one shared internal helper, so the check and real steps can't drift apart. It sends once
through `IntentHTTP.send` with the config's `llmDeadlineMs` and no retries. `.timeout` and `.cancelled` map to timedOut,
`.network` to noNetwork. A missing key returns noKey with no request.

### Menu (`AppDelegate`)

- `claudeItem` (disabled, text only) and `checkClaudeItem` (`Check Claude connection`) go directly after `harnessItem`.
- `refresh()` sets the line. It already runs on the poll and uses no network. While a check runs the line reads
  `Claude: checking…`.
- The click starts a `Task` on the main actor and stores the result and its `HH:mm` time in memory.
- **Disabling the item:** this menu leaves `autoenablesItems` on, so AppKit overrides `isEnabled` on any item with a
  target and action. `refresh()` sets `checkClaudeItem.action` to nil while a check runs or no key is set, and back to
  the selector otherwise.

The check uses the config loaded at launch, like the rest of the app, so a changed key needs a restart.

### CLI (`nohands-cli claude-check`)

Takes no arguments (extra ones print usage). Loads the config, runs the check, waits for nothing and reads no screen. It
works whatever `intentBackend` says, as long as a key is set. It prints to stdout and exits 0 only when connected,
otherwise 1:

```
Claude: request rejected (HTTP 400, model claude-haiku-5-5)
invalid_request_error: Schemas contains too many optional parameters (32), which would make grammar compilation inefficient. ...
```

### Docs

`README.md`: the CLI table and `usage()` gain `claude-check`. § Configuration gains the status line, the check, and a
note that the check spends about one request's input tokens.

## Tests

- One table-driven test in NoHandsCore for the status line: backend crossed with key present or missing and key source.
- One table-driven test for status code and body to result and text, covering each row above, a non-JSON body, and
  bodies that echo the key, including one where the key sits across the 70 and 500 character cuts. It asserts the key
  and `sk-ant-` text never appear in `detail`, the menu text or the CLI text.
- One test that `connectionCheckBody()` equals the real step body's `output_config`, `model` and `system`, with
  `max_tokens` of 1. This is what fails if someone turns the check back into a minimal request.
- Key source added to the existing `AppConfig.load` test table.

Manual checks, listed in the PR because they need a real key or a real menu:

- `claude-check` with the real key prints the full 400 message today.
- A wrong key prints key rejected and exits non-zero. Network off prints no network.
- The menu shows the line at launch with no traffic. A click changes it to the result and the item is disabled during
  the call.

## Follow-ups

Noted here, not done in this ticket. Neither has a ticket yet.

- **Reduce the optional parameters in `IntentSchema`.** The action object requires only `kind`
  (`Sources/NoHandsCore/IntentSchema.swift:84`), so everything else counts as optional. Until this lands, Claude
  commands fail with the 400 and the check will report `request rejected`, which is correct.
- `localModelItem.isEnabled` is set in `refresh()` under the same `autoenablesItems` rule and may be having no effect.

## Left to the builder

- Exact type and file names beyond those above, and wording tweaks that stay on one line with a next step.
- Whether `cancelled` needs its own path. No user action cancels a check today.

## Calls I made

1. **The check uses the app's real step request, not a minimal one.** It sends the real schema, system prompt and effort
   with `max_tokens` of 1, so it catches the 400 you hit. The ticket asked for one minimal call. This one costs about the
   input of one real step, and the first run also writes the prompt cache.
2. **The ticket's "valid key prints connected and exits 0" can't pass until the schema is fixed.** With today's schema, a
   valid key correctly gets `request rejected`. That acceptance line goes in the PR's `Not proven` list.
3. **The API's error message is shown, which reverses the ticket's "no response body" rule.** You asked for this. It is
   limited to the parsed `error.message` and `error.type`, with the key redacted, and only in the menu and CLI. The log
   rule stays as the ticket wrote it: result name and status code only.
4. **400 gets its own result, `request rejected`,** instead of "Claude unavailable (HTTP 400)", because the problem is
   the request and retrying won't help. A 400 can have other causes, for example Anthropic's low-credit error, so the
   wording stays general.
5. **The `request rejected` menu line has no fixed next step.** Product rules want every failure to name one. Here the
   API's message is the next step, and there is no room for both on one line. The CLI prints all of it.
6. **I assume the 400 still comes back with `max_tokens` of 1.** It should, because the schema is checked before anything
   is generated, but I have not run it. The first manual check proves it. If it doesn't hold, the fallback is a higher
   `max_tokens`.
7. **The user message is the real step format with the goal `ping`,** not literally one word, because it goes through
   the real builder.
8. **A 2xx is `connected`, with no decoding of the reply.** One token can't hold a valid step.
9. **The check stays available when `intentBackend` is `local` or `off`** as long as a key is set, as the ticket says.
   A result replaces the `not used` line until restart.
10. **Non-connected CLI runs all exit 1.** The ticket only says non-zero.
