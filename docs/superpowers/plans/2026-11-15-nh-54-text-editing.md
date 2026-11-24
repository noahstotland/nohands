# NH-54: Text editing by voice: Plan

**Spec:** [2026-11-15-nh-54-text-editing-design.md](../specs/2026-11-15-nh-54-text-editing-design.md) (approved). Follow it; tests per `AGENTS.md` § Testing (one table-driven test per rule; test lines ≤ feature lines).

## Task 1: Core range maths (`NoHandsCore/TextRanges.swift`)
Pure UTF-16 range functions: word, sentence, paragraph/line units, "last" units, delete range with adjacent space, phrase search (nearest before, else after; whole words; case-insensitive), replacement case, case change. Tests: range table, phrase-search table, replacement-case table.

## Task 2: Core types and grammar
`TextUnit`, `CaretPlace`, `CaseChange`, `TextEdit`, `Action.editText(TextEdit, otherwise: String?)`; join the exhaustive switches (`ActionSummary`, `SettlePolicy`, `SpokenFreeText`); `parseEdit` in `CommandGrammar` before `parsePattern`; `textFocused` flag through `grammar.parse` and `ModeMachine.route`; remove "delete line" from the exact table. Tests: grammar table incl. must-not-change rows.

## Task 3: Dictation routing
`ModeMachine`: edit phrases in dictation (fixed edits `otherwise: nil`, phrase edits carry the formatted text), `isDictationCommand` covers them (and "delete that"), session record dropped. Tests: dictation routing table.

## Task 4: Mac field access
`ElementProviding`: `focusedText()`, `setSelection(_:)`, `isTextFocused()` with default no-op impls; `AXQuery` implementation (UTF-16, 500 ms read budget via detached task, 200k cap); `FakeElements` support.

## Task 5: Executor and wiring
`.editText` in `ActionExecutor` per spec (AX range then type/Delete; chord fallback; failure messages; dictation `otherwise`; cancellation check); `VoicePipeline` passes `textFocused` and calls `forgetDictationRecord()` after an edit; `MergeBuffer` unaffected beyond `isDictationCommand`. Tests: executor table with the fake provider.

## Task 6: README
Voice command rows, new meaning of "delete line", dictation note.

Verify each task: `swift build` and `swift test`.
