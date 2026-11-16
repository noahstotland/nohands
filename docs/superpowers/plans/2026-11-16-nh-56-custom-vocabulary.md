# NH-56 Custom Vocabulary Implementation Plan

> Spec: `docs/superpowers/specs/2026-11-16-nh-56-custom-vocabulary-design.md`. Follow `AGENTS.md` § Testing: one table-driven test per rule; test lines no more than feature lines.

## Files

- Create `Sources/NoHandsCore/Vocabulary.swift`: `Vocabulary` (Sendable, Equatable) with `entries`, `skipped: Int`, `init(raw entries decoded leniently)`, `apply(_ transcript: String) -> String`.
- Modify `Sources/NoHandsCore/AppConfig.swift`: `vocabulary: Vocabulary` (default empty), CodingKeys `vocabulary`, lenient decode (non-list ignored; each entry decoded on its own so a bad one is skipped), `skipped` count kept on the `Vocabulary`.
- Modify `Sources/NoHandsMac/VoicePipeline.swift`: `runASR` takes a `vocabulary: Vocabulary` (default `Vocabulary()` so existing tests compile) and applies it to the early and full pass text before `merge`; a stop (`StopWords.isStop`, plus attention-prefixed via `AttentionGate`) is passed unchanged. Pass `config.vocabulary` (and the attention gate) from `start()`.
- Modify `Sources/NoHands/AppDelegate.swift` `loadConfig()`: when `config.vocabulary.skipped > 0` log `PipelineLog.warning("vocabulary: skipped N entries (see docs/configuration.md)")`.
- Modify `docs/configuration.md`: row + bullet.
- Tests: `Tests/NoHandsCoreTests/VocabularyTests.swift` (apply table), `AppConfigTests.swift` (decode table), `VoicePipelineTests.swift` (runASR rewrite + stop unchanged).

## Tasks

1. `Vocabulary` + `apply` with the spec's matching rules (word split on whitespace; leading/trailing punctuation kept around `say`; case-insensitive whole-word; longest `hear` by word count wins, ties first entry; punctuation inside a multi-word match breaks it; one pass, no rescan; empty list returns input). Entry cleaning: skip when `say` empty/missing, no usable `hear`, or hear/say contains a stop word (use `StopWords.isStop` on each token, and "never mind"); `hear` spellings over 5 words dropped; `say` over 100 chars skips; cap 200 entries (rest counted skipped). Table test first.
2. Config decode and skipped count; table test: string and list `hear`, each skip rule, 200 cap, non-list ignored.
3. Pipeline: apply in `runASR`, stop unchanged; AppDelegate log line. Test with a fake transcriber hearing "search for raptures" and one hearing "stop".
4. Docs row in `docs/configuration.md` with the Raptors example, rules and limits.
5. `swift build` and `swift test` green; commit and push.
