# NH-55 Rewrite the selection: Implementation Plan

Spec: [2026-11-16-nh-55-rewrite-selection-design.md](../specs/2026-11-16-nh-55-rewrite-selection-design.md). Tests follow `AGENTS.md` § Testing: one table-driven test per rule.

## Task 1: Core (`Sources/NoHandsCore`, tests in `Tests/NoHandsCoreTests`)

- [ ] `RewriteInstruction` / `RewriteStyle` (new `Rewrite.swift`), `Action.rewriteText(RewriteInstruction)`; add it to every exhaustive switch (`ActionSummary`, `SettlePolicy`, `SpokenFreeText`, `PipelineText`, others the compiler names). The decoder gets no kind for it.
- [ ] `CommandGrammar.parseRewrite(_:textFocused:)` after `parseEdit`; `ModeMachine.namesTextEdit` true for it; dictation mode still types the words.
- [ ] `RewriteSubject` (selection, else last sentence before caret via `TextRanges`, 2,000-char cap), `RewriteRequestBuilder` (Claude and Ollama bodies, one-field `{text}` schema, `<text>` escaping), `RewriteResult` (decode both backends, `clean`).
- [ ] Table tests: grammar (incl. must-not-change rows), request bodies, answer cleanup, subject choice. Run `swift test`.
- [ ] Commit.

## Task 2: Mac (`Sources/NoHandsMac`, tests in `Tests/NoHandsMacTests`)

- [ ] `TextRewriter.swift`: `TextRewriting`, `ClaudeTextRewriter`, `OllamaTextRewriter` via `IntentHTTP.send`, usage into `ClaudeUsageMeter`.
- [ ] `ActionExecutor` handles `.rewriteText` as spec § Running it (read, subject, cap, rewrite, clean, re-read and compare, select, type); executor gets an optional rewriter; failure texts per spec.
- [ ] `VoicePipeline`: build the rewriter from `effectiveBackend`; run `.rewriteText` in the task slot so "stop" cancels; log counts only with the private marker; command log counts only.
- [ ] Fake-rewriter tests per spec § Tests. Run `swift build` and `swift test`. Commit.

## Task 3: Docs

- [ ] `docs/voice-commands.md` rows, `docs/privacy.md` Rewrites bullet, README § Privacy line, `docs/configuration.md` mentions. Spec: Status Shipped + Shipped line. Commit and push.
