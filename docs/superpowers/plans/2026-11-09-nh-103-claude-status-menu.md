# NH-103: Claude status in the menu and connection check: Plan

**Spec:** `docs/superpowers/specs/2026-11-09-nh-103-claude-status-menu-design.md` (approved). The spec is the source for
every table and rule below; this plan only orders the work.

**Test:** `swift test`. **Typecheck:** `swift build` (Swift 6 strict concurrency, no `@unchecked Sendable`).

## Task 1: Core (NoHandsCore, Foundation only) with tests

1. `AppConfig`: add `KeySource` (`.file`, `.environment`) and `anthropicKeySource`, outside `CodingKeys`, set by `load`. Add key source cases to the `AppConfigTests` load table.
2. `ClaudeRequestBuilder`: `maxTokens` parameter on `body(request:)` (default 1024) and `connectionCheckBody()` (fixed `StepRequest`, goal `ping`, no screen, `maxTokens` 1, the builder's `vision` flag).
3. New `ClaudeStatus.swift`: `ClaudeCheckResult` (kind plus optional detail), the status-code/body mapping, the detail pipeline (JSON only, 64 KB cap, redact the key and `sk-ant-[A-Za-z0-9_-]+` before any cut, control characters to spaces, whitespace collapse, 500 cap), the menu text (70-character detail cut) and the plain status line from config.
4. `ClaudeStatusTests.swift`, table-driven: the status line (backend x key x source); status code and body to kind and text, including a non-JSON body and bodies echoing the key across the 70 and 500 cuts, asserting neither the key nor `sk-ant-` appears in detail, menu text or CLI text; `connectionCheckBody()` shares `output_config`, `model` and `system` with the real step body and has `max_tokens` 1.

## Task 2: Check (NoHandsMac)

1. `ClaudeConnectionCheck` beside `ClaudeIntentResolver`, same `session`, `baseURL`, `deadline` seams. Move the `URLRequest` setup into one internal helper shared with `resolve` (`resolve` behavior unchanged).
2. Send once through `IntentHTTP.send`, no retries. `.timeout`/`.cancelled` gives timedOut, `.network` gives noNetwork, no key returns noKey without a request. `PipelineLog` gets the kind and status code only, never the detail.
3. If it needs only a few lines, one `NoHandsMacTests` test using `HTTPStub` for a stubbed 400 end to end (no network); the Core table covers the mapping.

## Task 3: Menu and CLI

1. `AppDelegate`: `claudeItem` (disabled text) and `checkClaudeItem` after `harnessItem`. `refresh()` sets the line (plain status, `Claude: checking…`, or last result with `HH:mm`); the click runs a main-actor `Task`; disable by setting the action to nil while checking or without a key (the menu uses `autoenablesItems`).
2. `nohands-cli claude-check`: no arguments (otherwise usage), prints the result and detail, exit 0 only when connected. Add it to `usage()`.
3. `README.md`: CLI table row and a Configuration note (status line, the check, about one request's input tokens).

## Done when

`swift build` and `swift test` are clean; `nohands-cli claude-check` with no key prints the no-key line and exits 1; no network use outside the check; the key never appears in output.
