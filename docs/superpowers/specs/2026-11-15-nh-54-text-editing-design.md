# NH-54: Text editing by voice: Design

**Date:** 2026-11-15  **Ticket:** [NH-54](https://github.com/noahstotland/nohands/issues/54)
**Status:** Draft

## Intent

Without a keyboard the user can dictate but cannot fix what they dictated. "Select the last sentence", "delete
that", "replace meeting with call" and "go to the end of the line" should work in any text field, in command mode and
in dictation mode, from the grammar: on-device, no model, no network.

## Goals, non-goals, anti-goals

Goals are the ticket's Scope and Acceptance.

Non-goals: model-written rewrites (#55); counts ("delete the last three words"); "next word", "select next
sentence" and other forward units; moving text ("move this sentence up"); editing in a field that is not focused;
teaching the task loop or the model these commands (they stay grammar only).

Anti-goals, which would make this a failure even if it works:

- An edit lands somewhere other than the focused field of the front app, or types into a field the user did not
  target.
- "Undo" can't take an edit back.
- A command that works today changes meaning outside text editing: "select all", "delete", "delete word" (option-
  delete), "scratch that", "go to youtube", "home", "end", "copy".
- A phrase that went to the model today because no text field was focused ("select the second option", "delete the
  email from John" in a message list) is now grabbed by the grammar and fails.
- A wrong guess: "delete meeting" with two "meeting"s deletes one the user can't predict, or a fuzzy near-match.
- A slow field read blocks the main actor, or a spoken "stop" during the read lets the edit go out.
- The field's text reaches a log line without the private marker, or leaves the Mac.

## What the code forces

- **Nothing reads the focused field today.** `AXQuery` walks windows for elements and page text but never reads
  `kAXFocusedUIElementAttribute`, a value with its selection, or sets a range. All of that is new, in `NoHandsMac`.
- **AX ranges are UTF-16 offsets** (`CFRange` in `kAXSelectedTextRangeAttribute`). Core's range maths works on
  UTF-16 offsets into the value string so the two sides agree on emoji and accents.
- **Dictation mode types everything but a few whole utterances** (`ModeMachine.route`, `.dictation`): the escapes,
  "scratch that", "delete word". `ModeMachine.isDictationCommand` is what `MergeBuffer` and `VoicePipeline` use to
  keep those unmerged and untyped. New dictation commands must go through it too.
- **`DictationSession` keeps a one-level "scratch that" record** that is only right while nothing else touched the
  field. Any edit must drop it (`forgetLast`).
- **The grammar order** is pack phrase, exact table, pack without a lead, `menu …`, tab rule, patterns, filler-
  stripped exact. "go to the end of the line" hits the `go` pattern today (types "the end of the line" into the
  address bar), so the edit rule runs before `parsePattern`. "delete that" already resolves through the filler table
  to the Delete key, which deletes a selection; it stays that way.
- **"delete line" is in the exact table as command-delete** (delete to the start of the line) but not in the README
  table. The ticket lists "delete line" as a new command; it becomes "delete the whole line".
- **`ModeMachine` is pure and synchronous**; only the Mac side knows whether a text field has focus. The pipeline
  already passes `frontmost:` in; a `textFocused:` flag goes in the same way.
- **The executor's fakes** (`Tests/NoHandsMacTests/Fakes.swift`, `FakeElements: ElementProviding`) are how Mac
  behavior is tested without Accessibility; the field access joins `ElementProviding` with default no-op
  implementations, like `pageText()`.

## Approaches

1. **Read the field, compute ranges in Core, select by AX, then type or press (chosen).** The executor reads the
   focused element's value and selection, Core finds the range, the executor sets the selection through
   `kAXSelectedTextRangeAttribute` and reads it back, then replaces by synthesized typing (or the Delete key). Works
   for every phrase target, and typing keeps the app's own undo and keeps web editors' state in step.
2. **Write through `kAXSelectedTextAttribute`** (the ticket's first choice for replace). One call and fast, but many
   apps don't put an AX write on their undo stack, and React-style web editors ignore or later revert a value they
   did not see typed. Kept out; see Calls I made.
3. **Keyboard chords only** (option-arrow, shift-command-arrow). Works where AX can't read the field, but can't find a
   phrase or a sentence. Used as the fallback, not the design.

## How it works

### Phrases (Core, `CommandGrammar` → `TextEdit`)

A new `parseEdit(tokens, transcript:)` runs after the tab rule and before `parsePattern`. "the" is optional wherever
it can appear. `<phrase>`, `<a>` and `<b>` keep the speaker's raw words (`rawWords`).

| Spoken | Edit |
|---|---|
| `select word` / `line` / `sentence` / `paragraph` | select the unit at the caret |
| `select last word` / `last sentence` | select the last whole unit that ends at or before the caret |
| `delete line` / `sentence` / `paragraph` | delete the unit at the caret |
| `delete last word` / `last sentence` | delete the last unit before the caret |
| `select <phrase>` | select the phrase |
| `delete <phrase>` | delete the phrase |
| `replace <a> with <b>` | replace phrase `a` with the words `b` |
| `go before <phrase>`, `go after <phrase>` | put the caret before / after the phrase |
| `go to end of line` / `start of line` / `beginning of line` | caret to the line end / start |
| `go to end of document` / `start of document` / `top of document` / `bottom of document` | caret to the document end / start |
| `capitalize that`, `uppercase that`, `lowercase that` | change the case of the selection |

```swift
public enum TextUnit: String, Codable, Sendable { case word, line, sentence, paragraph }
public enum CaretPlace: String, Codable, Sendable { case lineStart, lineEnd, documentStart, documentEnd }
public enum CaseChange: String, Codable, Sendable { case capitalize, upper, lower }
public enum TextEdit: Equatable, Codable, Sendable {
    case select(TextUnit, last: Bool), delete(TextUnit, last: Bool)
    case selectPhrase(String), deletePhrase(String), replace(String, with: String)
    case caretBefore(String), caretAfter(String), caret(CaretPlace)
    case changeCase(CaseChange)
}
// Action:
case editText(TextEdit, otherwise: String?)
```

Rules that keep today's phrases:

- The exact table runs first, so "select all", "delete", "delete word", "copy" are unchanged. "delete line" leaves the
  exact table and becomes `.delete(.line, last: false)`.
- `<phrase>` is not a unit word, not "all", "that", "this" or "it", and has at most 12 words. "replace" needs a
  `with` with words on both sides; `<a>` ends at the **first** "with" ("replace coffee with tea with milk" puts in
  "tea with milk").
- **Phrase targets need a focused text field in command mode.** `ModeMachine.route(_:frontmost:textFocused:)` passes
  the flag to the grammar; with `textFocused: false`, `select <phrase>`, `delete <phrase>`, `replace … with …` and
  `go before/after …` return nil and go to the model as they do today. The unit, caret and case commands parse
  regardless and fail with `no text field` when there is none.
- `editText` is grammar only, like `.goToTab`: the decoder has no kind for it, so model output can never produce one.
  It joins the exhaustive switches (`ActionSummary`, `SettlePolicy`, `SpokenFreeText`).

### Dictation mode (Core, `ModeMachine`)

`isDictationCommand` grows to cover every edit phrase, so they are never merged or typed as dictation. In
`.dictation`, a fixed edit (units, caret, case) routes to `.editText(edit, otherwise: nil)`. A phrase edit routes to
`.editText(edit, otherwise: <the formatted text session.next would type>)`: when the phrase is not in the field, the
executor types the text instead, so dictating "Delete the old files." still types it unless "the old files" is
already in the field. The pipeline calls `forgetDictationRecord()` after any edit that ran, so "scratch that" never
deletes the wrong characters. "delete that" becomes a dictation command too (the Delete key, as in command mode).
"scratch that" and "delete word" are unchanged.

### Range maths (Core, `TextRanges.swift`)

Pure functions over a value string and a selection (UTF-16 `location`, `length`), returning UTF-16 ranges:

- **Word:** a run of letters, digits and apostrophes. The unit at the caret is the word the caret is in or touching,
  else the word before it. "last word": the last word ending at or before the caret's start.
- **Sentence:** ends after `.`, `?` or `!` (and any closing quote or paren after it) followed by whitespace or the
  end, or at a newline. Leading whitespace is not part of it. "last sentence": the last sentence ending at or before
  the caret, so right after dictating it is the one just dictated.
- **Paragraph:** text between newlines. **Line:** the visual line the field reports for the caret
  (`kAXInsertionPointLineNumberAttribute` + `kAXRangeForLineParameterizedAttribute`), passed in by the Mac side;
  when the field doesn't report one, the paragraph.
- **Delete range:** a deleted word, sentence or phrase also takes one adjacent space (the one after it, else the one
  before), so no double space is left; a deleted line or paragraph takes its newline.
- **Phrase search:** case-insensitive, on word boundaries, whitespace runs match any whitespace, the phrase's trailing
  ASR punctuation dropped. The nearest match that ends at or before the caret wins; with none before, the nearest
  after it. No match: nil. No fuzzy matching.
- **Replacement case:** when the found text starts with a capital and `<b>` starts lowercase, `<b>` gets a capital.
- **Case change:** `capitalize` capitalizes each word's first letter, `upper` and `lower` the whole text. With no
  selection, the word before the caret.

### Field access and executor (Mac, `TextEditor.swift`, `ActionExecutor`)

`ElementProviding` gains `focusedText() -> FocusedText?` (value, selection, the caret's line range, whether the range
is settable) and `setSelection(_:) -> Bool` (sets it, reads it back, true only when it took). `AXQuery` implements
them on the frontmost app's `kAXFocusedUIElementAttribute`; `isTextFocused()` is true for text field, text area,
search field and combo box roles and for an element with an `AXEditableAncestor`. Values over 200,000 UTF-16 units
count as unreadable.

`.editText` in the executor:

1. Read the field in a detached task with a 500 ms budget, then check `Task.isCancelled` (a spoken stop wins).
2. Readable with a settable range: Core computes the range; `setSelection`; then type the replacement through
   `InputSynthesizer` (`.typeText`), press Delete for a delete, or leave the selection for select and the caret for
   moves. Case changes select, then type the changed text.
3. Not readable, or the range didn't take (some web editors, Google Docs): keyboard chords where one exists. Word:
   option-left, shift-option-right; last word: shift-option-left; line: command-left, shift-command-right;
   paragraph: option-up, shift-option-down; delete = the selection, then Delete. Caret commands always use chords
   (command-left/right, command-up/down), with no read.
4. No chord for it (sentences, phrases, case changes): the row fails with the next step, `can't read the text here:
   select it by hand or say "select line"`. A phrase not found: `no "<phrase>" in the text` (the user's words, never
   the field's); in dictation with `otherwise`, the text is typed instead and the row is ordinary dictation.
5. No focused text field: `no text field: click into one first`.

The field's text is never logged except with the private marker, and it goes nowhere but Core.

### README

Rows in the voice command table for every phrase above, the new meaning of "delete line", and a note in the
dictation section that the edit commands work while dictating (phrase commands type the words when the phrase isn't
there).

## Tests

Per `AGENTS.md` § Testing, one table-driven test per rule:

- Core grammar table: every phrase to its `TextEdit`, the `textFocused: false` rows going to nil, and the
  must-not-change rows (`select all`, `delete`, `delete word`, `delete that`, `go to youtube`, `home`, `end`,
  `replace` alone, `replace x`, `go to the end`).
- Core `ModeMachine` dictation table: fixed edits route with `otherwise: nil`, phrase edits carry the typed text,
  `scratch that` and `delete word` unchanged, `isDictationCommand` true for edit phrases.
- Core range table: word, sentence, paragraph, line-fallback boundaries at start, middle, end and in emoji text;
  "last" units; delete ranges with the adjacent space.
- Core phrase search table: nearest-before wins, else nearest after; case-insensitive; word boundaries ("meet" does
  not find "meeting"); trailing punctuation; no match. Replacement case table.
- Mac executor with the fake provider: "replace meeting with call" sets the range of the right "meeting" and types
  "Call"/"call"; a range that doesn't take falls back to chords for "select line" and fails for "select sentence";
  a phrase not found in dictation types the `otherwise` text; no focused field fails with nothing typed.

Manual (in the PR): TextEdit, Notes, Mail compose, a Google Docs page, a plain textarea in Safari and Chrome: each
phrase family, then "undo" after a replace and a delete; "select the second option" in a settings window still goes
to the model.

## Calls I made

- **Replacing types the new text instead of writing `kAXSelectedTextAttribute`.** The ticket names the AX write first;
  I chose select-by-AX then type, because typing goes on every app's undo stack (product rule: actions reversible by
  voice) and web editors see real input. Cost: a long replacement types for a moment instead of landing at once.
- **In dictation, a phrase edit falls back to typing the words when the phrase isn't in the field.** So "Delete the
  old files" dictates normally, but "Replace the filter with a new one" replaces "the filter" if it is in the field.
  The alternative was no phrase edits while dictating, which the ticket asks for.
- **Phrase commands in command mode only take over when a text field is focused**; otherwise they go to the model as
  today, so "select the Wi-Fi option" keeps working.
- **"delete line" changes from command-delete (to the start of the line) to deleting the whole line.** It was never in
  the README table and the ticket lists it as new.
- **"delete that" keeps pressing Delete** (today's filler route), which deletes the selection.
- **Nearest match before the caret wins, then the nearest after; whole words only, no fuzzy guess.** "meet" does not
  find "meeting".
- **"replace a with b" splits at the first "with".**
- **The replacement copies a leading capital** from the text it replaces.
- **"last word" and "last sentence" mean the last before the caret**, not the end of the document.
- **Line means the visual line when the field reports it, else the text between newlines.** Sentence ends are a simple
  `.?!` rule, so "Mr. Smith" splits there.
- **"capitalize that" capitalizes each word**; with nothing selected, all three case commands act on the word before
  the caret.
- **Caret commands are chords only** (command-arrow), no field read, so they work everywhere.
- **Added "delete last word/sentence"** beside the ticket's "select last word/sentence"; added "top/bottom of
  document" as synonyms.
- **A field read has a 500 ms budget and fields over 200,000 characters count as unreadable** (chords or a failure).
- **Phrase targets are capped at 12 words.**
