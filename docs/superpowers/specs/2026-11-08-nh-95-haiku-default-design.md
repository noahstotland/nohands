# NH-95: Default the Claude model to Haiku at low effort — Design

**Date:** 2026-11-08  **Ticket:** [NH-95](https://github.com/noahstotland/nohands/issues/95)
**Status:** Proposed

## Intent

Every model call goes to `claude-opus-5-5` at `medium` effort by default, and the API credit is burning. Switch the
default to `claude-haiku-5-5` at `low` now, without waiting for NH-39's measurements. Haiku 5.5 is $0.10 / $0.50 per
million tokens against Opus 5.5's $4 / $20, so the same traffic costs about 40 times less before counting the lower
effort. Someone who wants a stronger model edits one line of `config.json`.

## Goals and non-goals

Goals are the ticket's Scope and Acceptance.

Non-goals are the ticket's Out of scope: measuring the tiers and picking the final default (NH-39), the API-key menu
item (NH-94), the local model's pass rate (NH-8), and prompt or task-loop changes for a small model (NH-90).

Anti-goals, which would make this a failure even if the tests pass:

- A config file that sets `intentModel` or `intentEffort` stops winning over the new defaults.
- A fixture in `scripts/intent-eval*.json` is edited to make Haiku pass.
- The request Haiku receives is rejected, so every natural-language command fails.

## Approaches

1. **Change the two defaults in `AppConfig` (chosen).** The ticket's approach: two values, and the existing config
   keys already do the rest.
2. **Haiku for one-shot commands, a stronger model for the task loop.** Could protect multi-step tasks, but it adds a
   second model setting and a routing rule before there is any data to justify them. That is NH-39's question.
3. **Wait for NH-39.** The user ruled this out in the ticket.

## What changes

- `Sources/NoHandsCore/AppConfig.swift`: `intentModel` defaults to `"claude-haiku-5-5"`, `intentEffort` to `"low"`.
  `load` already falls back to `AppConfig().intentEffort` for an invalid effort, so an invalid value now becomes `low`.
- `Sources/NoHandsCore/ClaudeRequestBuilder.swift`: the `effort` parameter defaults to `AppConfig().intentEffort`
  instead of a second `"medium"` literal, and its comment stops saying "medium". The app always passes the effort, but
  `successDecodesAndSendsRightRequest` compares what the resolver sends with a builder built on that default, so it
  would fail if the two defaults disagreed.
- `README.md` § Configuration: the sample shows Haiku and `low`, the sentence naming the default says `low`, and a new
  line says how to pick a stronger model (`"intentModel": "claude-opus-5-5"`, `"intentEffort": "medium"`).
- `docs/superpowers/specs/2026-11-04-nohands-design.md` § 10 and § 11: the default model named there, since the docs
  check treats that file as living.
- Tests: `configDefaultsAndEnvOverride` gets the new values. One new table-driven test in `AppConfigTests` covers a
  fresh `AppConfig()`, `load` of `{}`, a config setting `intentModel` to Opus, and a config setting `intentEffort`.

`AppConfig.load`, the resolver and the decoder do not change. `IntentDecoder` already finds the answer by block type,
so the `thinking` blocks Haiku can return do not confuse it, and it already throws on `stop_reason: "refusal"`.

## Is `effort: low` accepted on Haiku?

Yes, according to the Claude API reference: Haiku 5.5 takes `low` through `max`, with `medium` as its default, and
`output_config.format` structured outputs carry over to it. So `output_config.effort` stays and no per-model omission
is needed. No live request has confirmed this yet, because this machine has no API key (see Calls I made).

## Accuracy check

The ticket accepts either route, with the result in the PR:

- **Eval:** build `nohands-cli` from `feat/nh-39-measure-claude-model-tiers` (75ec8b6) and run both fixture files (40
  and 14 cases) with `--model claude-haiku-5-5 --effort low` and again with `--model claude-opus-5-5`. Estimated cost
  is under $2 for the pair, nearly all of it the Opus run.
- **Manual:** five or six spoken commands, including one garbled phrase and one task-loop command, listed in the PR.

A Haiku failure is reported in the PR, not fixed in a fixture. If the pass rate is bad, the user decides.

## Calls I made

- **The accuracy check cannot run without a key, and this machine has none.** `~/.config/nohands/config.json` is `{}`
  and `ANTHROPIC_API_KEY` is unset in the agent's shell. If a key is available at build time, the build runs the eval.
  If not, the PR lists the eval commands and the manual script under Not proven, and the merge decision is the user's.
  The live check that Haiku accepts the request is in the same position, and it is the check that matters most: a
  rejected request would break every natural-language command.
- **`fallbacks: "default"` and its beta header stay on every request.** Haiku 5.5 has no server-side fallback. The API
  reference says not to send the field, but also that the `"default"` form does not fail; a declined request simply
  stays declined. Removing it for one model adds a per-model branch to a body the ticket does not ask to change, and
  keeping it means switching back to Opus restores the fallback with no code change.
- **A refusal now ends the command instead of being retried on another model.** Opus's fallback re-ran declined
  requests. On Haiku the prompt's row shows the existing "didn't catch that" failure. No new message is added.
- **The builder's default follows `AppConfig`** rather than being changed to a second `"low"` literal, so the two
  cannot drift apart again.
- **Existing users are switched too.** Anyone whose `config.json` omits the two keys moves to Haiku on the next
  restart, which is the point of the ticket. Nothing in the app announces it.
- **`visionFallback` is left alone.** It is off by default. The reference does not state image support for Haiku 5.5
  in the part I read, so turning it on with Haiku is an untested combination, and the build does not claim otherwise.
- **Task-loop deadlines and step caps stay as they are.** `llmDeadlineMs` was tuned for Claude over the network and a
  faster model only gives it more slack.
