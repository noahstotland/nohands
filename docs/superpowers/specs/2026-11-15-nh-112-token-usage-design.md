# NH-112: Claude token usage per call and a session total: Design

**Date:** 2026-11-15  **Ticket:** [NH-112](https://github.com/noahstotland/nohands/issues/112)
**Status:** Draft

## Intent

Claude spend is invisible. Every Claude call should log its input, cached and output token counts, and the menu
should show a running total for this app session, so the user can see where the money goes and what to trim next.

## Goals, non-goals, anti-goals

Goals are the ticket's Scope and Acceptance.

Non-goals (ticket): dollar estimates, trimming the prompt or schema or screen context, choosing a model (#39),
saving totals across restarts. Also: adding output tokens to the NH-111 command log entries and the View Logs
window (see Calls I made).

Anti-goals, which would make this a failure even if it works:

- Any text (transcript, screen content, response text, API error message) reaches the total, the menu or the new
  log lines. Counts only.
- The total silently drops calls: a step that fails to decode, a call from a task that was later cancelled or
  stopped, or a plan call.
- The total resets when the config reloads or the backend switches (the resolver is rebuilt then); it resets only
  when the app restarts.
- A new network call, or a menu open that waits on anything.

## What the code forces

- **`ClaudeUsage`** (`Sources/NoHandsCore/ClaudeUsage.swift`) parses `input_tokens`, `cache_read_input_tokens`
  and `cache_creation_input_tokens`, and `logFragment` prints `cache=<read>/<written> in=<uncached>`. No
  `output_tokens`.
- **`ClaudeIntentResolver`** is an actor that `AppDelegate.makeResolver` rebuilds whenever the config or backend
  changes. Its `usage` list is drained by `takeUsage()` at task start (to drop a cancelled task's calls) and at task
  end (for the command log). So the session total cannot live in the resolver, and cannot be fed from
  `takeUsage()`, or cancelled tasks' calls would be lost.
- **`post`** throws on a non-2xx status and on a timeout before any usage is read. Such calls return no usage block
  and are, as far as the API bills, almost always free.
- **`ClaudeConnectionCheck`** (menu "Check Claude", and `nohands-cli claude-check`) sends a real `max_tokens: 1`
  request and reads only the status.
- **The menu** has a disabled `claudeItem` line refreshed in `refresh()`; `menuWillOpen` runs before the menu
  shows. Menu text must be one short line (product rule).
- **`OSAllocatedUnfairLock`** is already used in `NoHandsMac` (`FrontmostApp`, `EndpointReplay`) for small
  Sendable shared state without `@unchecked`.

## Approaches

1. **A pure total in Core, held by one process-wide meter in Mac, fed at each call site (chosen).** Core gets
   `ClaudeUsageTotal` (a value type: `calls`, `input`, `cacheRead`, `cacheWrite`, `output`, `adding(_:)`, a menu
   line and a log fragment). Mac gets `ClaudeUsageMeter`, a `final class: Sendable` around an
   `OSAllocatedUnfairLock<ClaudeUsageTotal>`, with a `shared` instance. The resolver and the connection check record
   into it right after each 2xx response, before decoding. It outlives resolver rebuilds and sees cancelled tasks'
   calls.
2. **Sum `takeUsage()` results in the pipeline.** Misses the calls a cancelled task made (drained and discarded at
   the next task start) and the connection check. Rejected.
3. **A callback from the resolver to `AppDelegate`.** Must be re-wired on every rebuild and still needs somewhere
   to keep the total. More plumbing for the same result. Rejected.

## Design

### Core

- `ClaudeUsage` gains `outputTokens` read from `output_tokens` (missing reads as 0, like the others). The init
  gets `outputTokens: Int = 0` so existing call sites and tests keep compiling.
- `logFragment` becomes `cache=<read>/<written> in=<uncached> out=<output>`; with no usage it stays `cache=-`.
- New `ClaudeUsageTotal` (in `ClaudeUsage.swift`): `adding(_ usage: ClaudeUsage?)` adds one call and its counts;
  a `nil` usage (2xx body with no `usage` object) still adds one call with zero tokens.
- `ClaudeUsageTotal.menuLine` returns nil when `calls == 0`, else
  `Claude this session: 14 calls, 31k in, 9k cached, 2k out` (`1 call` singular).
  - "in" is uncached input plus cache writes (both billed as fresh input); "cached" is cache reads.
  - Counts under 1,000 print as is; 1,000 to 9,999 with one decimal (`1.2k`, trailing `.0` dropped); 10,000 up to
    a million as whole `k`; a million and up as `1.2M`.
- `ClaudeUsageTotal.logFragment`: `calls=<n> in=<uncached> cache=<read>/<written> out=<output>`, numbers only.

### Mac

- `ClaudeUsageMeter` (`Sources/NoHandsMac/ClaudeUsageMeter.swift`): `static let shared`, `record(_ usage:
  ClaudeUsage?)`, `var total: ClaudeUsageTotal`. Tests and the CLI can make their own instance.
- `ClaudeIntentResolver` takes `meter: ClaudeUsageMeter = .shared` in its init. `resolve` and `plan` call
  `meter.record(used)` next to the existing `usage.append`, before decoding, so a malformed step still counts.
  The per-call log line already includes `logFragment`, so it gains `out=` for free.
- `ClaudeConnectionCheck` takes the same `meter` parameter and records the response's usage when the status is
  2xx. It is a real billed call; the ticket title says every Claude call.
- At task end, `VoicePipeline.runTask` logs `claude: session <total.logFragment>` when the effective backend is
  Claude and the total has at least one call. Counts only, public log field.
- `AppDelegate` adds one disabled menu item under the Claude line, `claudeUsageItem`, set in `refreshClaudeItems()`
  from `ClaudeUsageMeter.shared.total.menuLine`, hidden when that is nil (no key, LLM off, local model, or no calls
  yet). `menuWillOpen` calls `refreshClaudeItems()` so the line is current each time the menu opens.

### The measurement

After the build, run one real task on Claude (for example "open Safari and search for the weather") and comment on
NH-112 with the per-call counts from the log and which part dominates. Splitting system prompt, schema, screen
context and output: run `nohands-cli` with the same step against a request that omits the screen context (or read
the request sizes the builder produces) and compare. This is a manual step listed in the PR, not a test.

## Tests

One table-driven test per rule, in `Tests/NoHandsCoreTests`:

- `ClaudeUsage.from(response:)`: all four counts present; `output_tokens` missing; no `usage` object (nil);
  not JSON (nil). Extends the existing table in `IntentStepTests.swift`.
- `ClaudeUsageTotal.adding`: a sequence of calls including a `nil` usage, checking calls and every sum.
- `ClaudeUsageTotal.menuLine`: zero calls (nil), one call (singular), the number formatting boundaries (999,
  1000, 1250, 9999, 10000, 1,250,000).

No tests for the meter, the menu item or the log line (Mac wiring and copy, per `AGENTS.md` § Testing).

## Calls I made

- **The total counts only calls that got a 2xx response.** Timeouts, network errors and HTTP errors (401, 429,
  5xx) are not counted: there is no usage block to read and the API does not bill them. A 2xx body with no
  `usage` object counts as a call with zero tokens.
- **The connection check counts toward the total.** The ticket's scope names `resolve` and `plan`, but its title
  says every Claude call and the check is a real billed request (about one output token plus the full prompt).
- **"in" in the menu line is uncached input plus cache writes**, and "cached" is cache reads, matching the
  ticket's example wording. The log keeps all four numbers separate.
- **The menu line is hidden until the first call**, rather than showing zeros. The ticket allows either.
- **The total includes calls from tasks that were cancelled or stopped.** They were billed.
- **The NH-111 command log (and View Logs) does not gain output tokens.** Its saved `Usage` would need a
  backward-compatible decode for old entries; that is a small follow-up, outside this ticket's scope.
- **The CLI shares the same meter type** but no CLI command prints the total.
- **Number formatting is fixed `k`/`M` with no locale**, since it is a short menu line.
