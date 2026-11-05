# NH-10: Spell command for letter-by-letter typing — Design

**Date:** 2026-11-05  **Status:** Shipped  **Ticket:** [NH-10](https://github.com/noahstotland/nohands/issues/10)
**Shipped:** in PR #26, as specified

## Intent

There is no way to type a password, a code or a tricky URL letter by letter: `type <words>` and dictation type
whole words, so "k9x" comes out as whatever the recogniser heard. A new `spell <tokens>` command turns spoken
letter names, NATO words, digits and a few separators into one string and types it with no spaces. If any token
is unknown, nothing is typed and the HUD names the token, so nothing half-typed lands in a password field.

## Today

- `CommandGrammar.parse` (`Sources/NoHandsCore/CommandGrammar.swift`) returns `[Action]?`; `nil` means "not a
  grammar command", and `ModeMachine.route` then sends the phrase to the model (`Routing.resolveWithLLM`).
  There is no way for the grammar to say "this is mine, but it's wrong, don't ask the model".
- `VoicePipeline.isComplete` lets a phrase that parses skip the merge window, so a pause mid-phrase runs the first
  half at once and sends the second half on its own.
- `NumberWords` parses cardinals ("forty two"), including homophones ("to" → 2, "for" → 4).
- The executor types `.typeText` verbatim through `InputSynthesizer.type`, with no formatting.

## Approaches

1. **A `Speller` in Core, plus a grammar "reject" result that stops the model fallback.** Chosen. The ticket
   requires that an unknown token fails visibly; falling back to the model would let it guess at a password.
2. **Return `nil` for a bad spell and let the model handle it.** Rejected: the model could type a half-right
   string into a password field, which is exactly what the ticket forbids.
3. **Return an action that shows a HUD message.** Rejected: a new action type the model could also emit, which
   the security overlay says must go through the decoder and guards; a routing result is narrower.

## Design

### Speller (`NoHandsCore/Speller.swift`, new)

`public enum Speller { public static func spell(_ tokens: [String]) -> Result<String, SpellError> }`, where
`SpellError` is `.empty`, `.unknown(String)` (the first token it couldn't read) and `.capitalWithoutLetter`.
Tokens arrive already normalized by `CommandGrammar.normalize` (lowercased, `.,!?` stripped). Walked left to right,
longest match first:

| Spoken | Types |
|---|---|
| A single letter `a`–`z` | that letter, lower case |
| Letter-name homophones: `bee`, `see`/`sea`, `dee`, `gee`, `jay`, `kay`, `el`, `em`, `en`, `oh`, `pee`, `queue`/`cue`, `are`, `ess`, `tee`/`tea`, `you`, `vee`, `double you`, `ex`, `why`, `zee`/`zed`, `eye` | that letter, lower case |
| NATO: `alpha`/`alfa`, `bravo`, `charlie`, `delta`, `echo`, `foxtrot`, `golf`, `hotel`, `india`, `juliet`/`juliett`, `kilo`, `lima`, `mike`, `november`, `oscar`, `papa`, `quebec`, `romeo`, `sierra`, `tango`, `uniform`, `victor`, `whiskey`/`whisky`, `x-ray`/`xray`/`x ray`, `yankee`, `zulu` | that letter, lower case |
| Digit words `zero`–`nine`, and any all-digit token (`9`, `42`) | the digits |
| `space`, `dash`, `dot`, `underscore`, `at sign` | ` `, `-`, `.`, `_`, `@` |
| `capital` before any letter form above | that letter, upper case |

- `capital` followed by a digit, a separator, another `capital` or nothing is `.capitalWithoutLetter`.
- `x ray` is read as one NATO word before `x` alone, so "spell capital kilo nine x ray" gives `K9x`, per the
  ticket's acceptance check. A trailing `ray` with no `x` before it is unknown.
- `oh` is the letter o, not zero. The number homophones `to`, `too`, `for` are unknown here (they fail visibly).

### Grammar (`CommandGrammar.swift`)

- `parse`: a first token `spell` with a successful `Speller.spell(rest)` returns `[.typeText(text)]`. Any
  failure returns `nil` from `parse`, as before for non-matches.
- New `public func rejection(_ transcript: String) -> String?`: for a `spell` phrase whose spell fails, the HUD
  line; `nil` for anything else. Lines (one line, names the next step, per Product rules):
  - `.unknown(t)`: `can't spell "<t>": say spell again`
  - `.capitalWithoutLetter`: `capital needs a letter: say spell again`
  - `.empty` (bare "spell"): `say spell and then the letters`

### Routing (`ModeMachine.swift`)

- New `Routing.reject(String)`. In command mode, when `grammar.parse` is nil and `grammar.rejection` is non-nil,
  route returns `.reject(message)` instead of `.resolveWithLLM`. A rejected spell never reaches the model.
- `spell` is command-mode only; in dictation the word is dictated like any other.

### Pipeline (`NoHandsMac`)

- `VoicePipeline.process`: `.reject(message)` reports `.failed(message)` on the prompt board and logs
  `reject` (public) like other outcomes. Nothing is typed.
- `PipelineText.summary`: `.reject` → `"reject"` (no payload in the public summary; the message carries a
  token of what may be a password, so it goes only to the private detail).
- `VoicePipeline.isComplete`: a `spell` phrase is never "complete", so it always waits the merge window. A pause
  in "spell capital kilo … nine x ray" then merges into one phrase instead of typing `K` and sending "nine x ray"
  to the model. Cost: up to `mergeWindowMs` (500 ms default) before a spell types.

### CLI (`nohands-cli parse`)

- For a rejected spell, prints `rejected: <message>` instead of `no match -> LLM`.

### README

- Voice command table row: `spell <letters>` — types letters, NATO words, digits and `space`, `dash`, `dot`,
  `underscore`, `at sign` with no spaces; `capital` uppercases the next letter; an unknown word types nothing.
- CLI table: `nohands-cli parse "spell capital kilo nine x ray"` example.

## Tests

- `SpellerTests` (new, one table): letters, homophones, NATO incl. `x ray`/`x-ray`, digit words and numerals,
  `capital`, each separator, `at sign`, and failures: unknown token (names the first unknown), `capital` before a
  digit, trailing `capital`, empty.
- `SpellerTests` (same file): one test covers the grammar and routing: a good spell gives `[.typeText("K9x")]`; a bad one has
  `parse` nil and a `rejection`, and routes to `.reject`, never `.resolveWithLLM`; a non-spell phrase has `rejection == nil`.
- `MergeBufferTests` / `isComplete`: a valid spell phrase is not complete.
- Manual (PR): "spell capital kilo nine x ray" types `K9x` into TextEdit; "spell kilo banana" types nothing and the
  HUD shows `can't spell "banana"`; a pause mid-spell still types one string.

## Calls I made

- **A rejected spell never goes to the model.** The ticket says the whole phrase fails with the HUD; I read that
  as "no model fallback either", since a model guess is the half-typed risk the ticket is about.
- **Spell phrases always wait the merge window** (500 ms default), so a pause mid-spelling doesn't type half and
  send the rest to the model. Slightly slower than other grammar commands.
- **Letter homophones are accepted** (`bee`, `see`, `you`, `why`, `are`, `oh`…), beyond the ticket's list,
  because the recogniser often writes a lone spoken letter as a word. Anything not in the table still fails safely.
- **`oh` is the letter o, not zero**; `to`/`too`/`for` are not digits here (they fail rather than guess).
- **Numerals typed as is**: an ASR token `42` types `42`.
- **No extra separator aliases** (`hyphen`, `period`, `at` alone) beyond the ticket's list; easy to add later.
- **`capital` applies only to letters**; `capital nine` fails rather than silently typing `9`.
- **HUD names only the first unknown token**, as the ticket asks. The prompt board already shows the full
  transcript today (true for `type` too); hiding spelled text from the board is out of scope.
- New `Routing.reject` case rather than a new `Action`, so the model's action schema is unchanged.

## Out of scope

- A persistent spell mode (ticket).
- Hiding the spoken letters from the prompt board or the private log.
- Spelling inside dictation mode.
