# NH-95: Default the Claude model to Haiku at low effort — Design

**Date:** 2026-11-08  **Ticket:** [NH-95](https://github.com/noahstotland/nohands/issues/95)
**Status:** Shipped
**Shipped:** in PR #96, as specified

## Intent

Every model call went to `claude-opus-5-5` at `medium` effort and the API credit was burning. Switch the default to `claude-haiku-5-5` at `low` now. Haiku is $0.10 / $0.50 per million tokens against Opus's $4 / $20, about 40 times less. A stronger model is one line of `config.json`.

Anti-goals:

- A config that sets `intentModel` or `intentEffort` stops winning over the defaults.
- A fixture in `scripts/intent-eval*.json` is edited to make Haiku pass.
- Haiku rejects the request, so every natural-language command fails.

## What changes

Chosen: change the two `AppConfig` defaults.

- `AppConfig`: `intentModel` defaults to `claude-haiku-5-5`, `intentEffort` to `low`. An invalid effort falls back to `low`.
- `ClaudeRequestBuilder`'s `effort` default follows `AppConfig().intentEffort`, so the two cannot drift.
- README and the living design doc name the new default.
- One table-driven test covers a fresh config, `{}`, and configs setting the model or effort.

`effort: low` is accepted on Haiku 5.5 per the API reference. No live request has confirmed it.

## Accuracy check

Run both fixture files (40 and 14 cases) on Haiku at `low` and on Opus (under $2), or a few spoken commands. A Haiku failure is reported, not fixed in a fixture.

## Calls I made

- **The accuracy check cannot run without a key, and this machine has none.** The PR lists the eval commands under Not proven and the user decides.
- **`fallbacks: "default"` stays on every request.** Haiku has no fallback but the field does not fail.
- **A refusal ends the command** instead of retrying on another model.
- **Existing users are switched too**, on restart.
- **`visionFallback` is left alone**: Haiku image support is unconfirmed.
