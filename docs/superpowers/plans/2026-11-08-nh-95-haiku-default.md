# NH-95: Haiku at low effort by default — Plan

**Spec:** [design](../specs/2026-11-08-nh-95-haiku-default-design.md)  **Ticket:** [NH-95](https://github.com/noahstotland/nohands/issues/95)

Test command: `swift test` (no permissions, no Ollama, no network).

## Task 1: Defaults and builder

- `Sources/NoHandsCore/AppConfig.swift`: `intentModel = "claude-haiku-5-5"`, `intentEffort = "low"`; fix the effort comment if it names a default.
- `Sources/NoHandsCore/ClaudeRequestBuilder.swift`: `init(model:effort:vision:)` defaults `effort` to `AppConfig().intentEffort`; update the doc comment (no "medium").
- Do not touch `AppConfig.load`, the resolver, the decoder, or `scripts/intent-eval*.json`.

## Task 2: Tests

- `Tests/NoHandsCoreTests/AppConfigTests.swift`: update `configDefaultsAndEnvOverride` to the new values.
- Add one table-driven test: fresh `AppConfig()`, `load` of `{}`, config setting `intentModel` to `claude-opus-5-5`, config setting `intentEffort` to `medium`, config with an invalid effort (falls back to `low`).
- Run `swift test`; it must pass (including `successDecodesAndSendsRightRequest`).

## Task 3: Docs

- `README.md` § Configuration: sample shows `claude-haiku-5-5` / `low`; the "How the model reads a request" sentence names `low` as the default; add a line on picking a stronger model (`"intentModel": "claude-opus-5-5"`, `"intentEffort": "medium"`, restart), and that Haiku has no server-side fallback so a declined request just fails.
- `docs/superpowers/specs/2026-11-04-nohands-design.md` § 10 Model bullet and § 11 sample: default is now Haiku at low.

## Done when

`swift build` clean, `swift test` green, one commit per task group pushed to `feat/nh-95-haiku-default`.
