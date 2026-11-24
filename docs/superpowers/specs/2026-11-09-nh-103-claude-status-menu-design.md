# NH-103: Claude status in the menu and a "Check Claude connection" test: Design

**Date:** 2026-11-09  **Ticket:** [NH-103](https://github.com/noahstotland/nohands/issues/103)
**Status:** Shipped
**Shipped:** in PR #105, as specified

## Intent

After adding a key, nothing says whether Claude works. The menu gets a Claude line that needs no network, plus an on-demand check from the menu or `nohands-cli claude-check`.

The check must answer "will my commands work?", not "is the key valid". With a valid key, `nohands-cli resolve` failed with HTTP 400 ("Schemas contains too many optional parameters (32)..."). A key-only check would say "connected" while every command fails.

Changes since the ticket: a 400 gets its own result, `request rejected`, and the API's error message is shown (reversing the ticket's "no response body" rule). The check reads the body itself, since the resolver cuts it to 200 characters.

## Non-goals and anti-goals

- Not here: fixing the schema, entering a key from the menu (#94), a local-model check, proving the model returns valid actions.
- Failure means: the key appears anywhere (menu, CLI, log, test output); network traffic the user did not ask for (launch, timer, menu open); `connected` when a real command would be refused.

## Approach

Chosen: send the app's real step request with `max_tokens` 1. Same URL, model, system prompt and schema, so it fails when a real step fails.

Rejected: the ticket's minimal one-word request, which would say `connected` while every command returns 400.

## How it works

- **Key source:** `AppConfig.anthropicKeySource` (`.environment` or `.file`), set only by `load`.
- **Probe:** `connectionCheckBody()` builds a fixed request (goal `ping`, no elements, no screenshot) with `maxTokens: 1` and the normal `vision` flag.
- **Results** (pure): 2xx connected; 400 requestRejected; 401 and 403 keyRejected; 404 modelNotFound; 429 rateLimited; other codes unavailable; deadline timedOut; transport error noNetwork; no key noKey (no request). Menu lines carry the check time and a next step; `request rejected` shows 70 characters of the API message.
- **Plain line** from config alone: key set with its source; no key (auto: using the local model; claude: LLM off); not used (local or off). A last result replaces it.
- **Detail** for non-2xx: read `error.type` and `error.message` (non-JSON or over 64 KB gives none); replace the configured key and `sk-ant-` strings with `[hidden]`; turn control characters into spaces; cap at 500 characters, redacting before any cut. It is only displayed (menu, CLI); the log gets the result name and status code.
- **Check:** `ClaudeConnectionCheck` shares the request setup with real steps so they cannot drift. One send, `llmDeadlineMs`, no retries.
- **Menu:** a disabled `Claude:` line and `Check Claude connection`, disabled while checking or with no key. It uses the launch config, so a changed key needs a restart.
- **CLI `claude-check`:** works whatever `intentBackend` says if a key is set; exits 0 only when connected.
- **Docs:** README notes the check spends about one request's input tokens.

## Tests

- Tables for the plain line, and for code and body to result and text, including bodies echoing the key across the cut points (the key never appears).
- `connectionCheckBody()` equals the real step body's `output_config`, `model` and `system` with `max_tokens` 1. This fails if the check turns back into a minimal request.
- Manual, in the PR: real key, wrong key, network off.

## Follow-ups (no tickets yet)

- Reduce optional parameters in `IntentSchema` (the action object requires only `kind`). Until then Claude commands fail with the 400 and the check says `request rejected`.

## Calls I made

1. Real step request, not a minimal one.
2. The ticket's "valid key prints connected and exits 0" cannot pass until the schema is fixed; it goes in the PR's `Not proven` list.
3. I assume the 400 still comes back with `max_tokens` 1 because the schema is checked first. The first manual check proves it; fallback is a higher `max_tokens`.
4. A 2xx is `connected` with no reply decoding. The check works when `intentBackend` is `local` or `off` if a key is set. All non-connected CLI runs exit 1.
