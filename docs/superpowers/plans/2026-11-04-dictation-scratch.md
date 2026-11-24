# Dictation scratch that / delete word — Plan

**Spec:** `docs/superpowers/specs/2026-11-04-dictation-scratch-design.md` (approved)  **Ticket:** NH-9

Verify with `swift build` and `swift test`.

## Task 1: DictationSession record (`Sources/NoHandsCore/DictationFormatter.swift`)

- Add private `typedCount: Int` and `previousLast: String` to `DictationSession`. In `next(_:)`, when the result is non-empty, set `previousLast = last` (before `last = result`) and `typedCount = result.count` (Characters). An empty result leaves both alone.
- `mutating func scratch() -> Int?`: nil if `typedCount == 0`; else return the count, set `last = previousLast`, zero the record.
- `mutating func forgetLast()`: zero the record (leave `last`).

## Task 2: ModeMachine (`Sources/NoHandsCore/ModeMachine.swift`)

- `public static func isDictationCommand(_:) -> Bool`: `isDictationEscape` or the normalised phrase is `scratch that` / `delete word`.
- `route`, `.dictation` case, after the escape check: `scratch that` calls `session.scratch()`; nil gives `.ignore(reason: "nothing to scratch")`, else `.execute(Array(repeating: .pressKey(KeyChord(.delete)), count: n))`. `delete word` calls `session.forgetLast()` and returns `.execute([.pressKey(KeyChord(.delete, [.option]))])`.
- Match the `KeyChord` / `Key` spelling `CommandGrammar` uses for command-mode "delete word".

## Task 3: Merge window (`Sources/NoHandsMac`)

- `VoicePipeline.isComplete`, `.dictation` case: `isDictationEscape` becomes `isDictationCommand`.
- `MergeBuffer.transcript`: the dictation-escape branch also uses `isDictationCommand`. Otherwise "scratch that" spoken inside the merge window is appended to the held fragment ("hello scratch that") and typed, and the pending text is not flushed first. The spec's one-line Mac change missed this call site.

## Task 4: Tests (table-driven)

- `ModeMachineTests`: `isDictationCommand` table (true: exact and ASR variants; false: embedded phrases; command mode unaffected). Routing table: count equals typed characters across punctuation, leading space and "new paragraph"; second scratch ignored; scratch with no prior ignored; "delete word" yields option-delete and clears the record; the next utterance after a scratch gets the restored spacing and capitalisation.
- `MergeBufferTests`: extend `isCompleteCoversStopsAndDictationEscapes`; add a case that "scratch that" after a pending dictation fragment flushes the fragment first and arrives alone.

## Task 5: Docs

`README.md`: two rows in the voice command table; one sentence in "Pausing mid-command".
