# NoHands: Voice-Only macOS Control — Design Spec

**Date:** 2026-11-04
**Status:** Draft, written from the user's brief without a brainstorming session. Decisions marked *(assumption)* were made by the planner and are the ones most worth challenging.

## 1. Goal

A menu-bar macOS app that operates the whole computer by voice alone (dictation, keys, mouse, natural-language commands), fast enough to replace a keyboard and mouse. Targets macOS 14.5+, Apple Silicon. Only the LLM path uses the network.

## 2. Non-goals

- Wake word. The app always listens; "go to sleep" / "wake up" gate it (optional attention word, NH-12).
- Vision fallback (shipped later, NH-41), LLM polish of dictation, custom vocabulary, Intel, notarization.

## 3. Architecture

Mic (16 kHz mono, echo cancellation unless `echoCancellation` is false) → Silero VAD → Parakeet TDT v2 → mode machine → dictation formatter, or command grammar (unmatched text goes to the Claude resolver) → action executor.

- **One vocabulary.** `Action` is the enum every stage produces or consumes. A new capability adds a case in grammar, LLM decoder and executor.
- **Grammar first, LLM second.** The common path is local (< 1 ms) and works offline. An untypeable `spell` phrase is rejected, not sent to the LLM.
- **Targets resolve late.** `numbered(42)` means grid cell or label, by which overlay is visible.

## 4. Modes and menu

- `command` (default): every utterance is a command (with `attentionWord` set, only those starting with it).
- `dictation`: everything is typed except "stop dictating", "command mode", "scratch that", "delete word", "delete that" and the text edits (`select the last sentence`, `delete <words>`, `replace x with y`, `go to the end of the line`, `uppercase that`; a phrase edit whose words are not in the field is typed as dictation).
- `sleep`: everything ignored except "wake up".

The menu bar shows `CMD` / `DICT` / `ZZZ`. The menu has Start at Login, Status Bar, Model (`Claude|Local|Off`, no restart, saves `intentBackend`), Open config.json…, Recent commands (last 50) and View Logs…. The log is `~/.config/nohands/command-log.json`, local only, mode 600.

## 5. Command grammar and dictation

Input is lowercased and stripped of `.,!?`. In a number slot "to"/"too" mean 2 and "for" means 4.

| Phrase | Action |
|---|---|
| `type <words>` | `.typeText(formatted words)` (through DictationFormatter) |
| `spell <tokens>` | `.typeText(string)`: letters, letter-name homophones, NATO words, digits, `space`/`dash`/`dot`/`underscore`/`at sign`; `capital` uppercases the next letter. One unknown token or a dangling `capital` types nothing |
| `press <modifiers…> <key>` e.g. "press command shift s" | `.pressKey(KeyChord)` |
| `enter`, `tab`, `escape`, `space`, `delete` / `backspace`, `forward delete`, `up`/`down`/`left`/`right` | `.pressKey` of that key |
| `undo`, `redo`, `copy`, `paste`, `cut`, `select all`, `save`, `find`, `new tab`, `close tab`, `close window`, `quit app`, `switch app`, `spotlight`, `delete word` | the standard ⌘ shortcut (`redo` = ⇧⌘Z, `switch app` = ⌘⇥, `spotlight` = ⌘␣, `delete word` = ⌥⌫); `delete line` and other spoken text edits are in the README voice commands and the NH-54 spec |
| `find <words>`, `scroll to <words>` | `.findOnPage(words, movePointer: true)`; bare `find` stays ⌘F, and `scroll to` an end of the page or a direction goes to the LLM |
| `click` | `.click(.cursor)` left, count 1 |
| `double click`, `triple click` | count 2 / 3 |
| `right click`, `middle click` | button |
| `click <n>` | `.click(.numbered(n))` |
| `click <name>` (anything else after "click") | `.click(.element(named: name))` |
| `hold click` / `release click` | `.pressMouse(.left)` / `.releaseMouse(.left)` |
| `move <up/down/left/right> [<n>]` | `.moveCursor(.relative(dx,dy))`, default 50 px |
| `move to <n>` | `.moveCursor(.numbered(n))` |
| `scroll <up/down/left/right> [<n>]` | `.scroll(direction, amount)`, default 5 lines, max 50 |
| `grid` / `show grid` | `.showGrid` |
| `zoom <n>` | `.zoomGrid(n)` (subdivide cell n with a fresh 10×8 grid) |
| `numbers` / `show numbers` / `show labels` | `.showLabels` |
| `hide` / `hide grid` / `hide numbers` / `cancel` | `.hideOverlay` |
| `open <app name>` | `.openApp(name)` |
| `start dictating`, `dictation mode`, `stop dictating`, `command mode`, `go to sleep`, `wake up` | `.setMode(...)` |
| anything else (except a `spell` with an unknown word, which is rejected on the HUD and never sent to the LLM) | unmatched → LLM |


Spoken tokens → characters: `period` `.`, `comma` `,`, `question mark` `?`, `exclamation point|mark` `!`, `colon` `:`, `semicolon` `;`, `dash` ` - `, `hyphen` `-`, `open quote` `"`, `close quote` `"`, `open paren` `(`, `close paren` `)`, `new line` `\n`, `new paragraph` `\n\n`. No space before `.,?!:;)`; space after them when followed by a word; capitalize the first letter of the utterance and of any word following `.`, `?`, `!`, or a newline. Across utterances, `DictationSession` inserts a leading space when the previous insertion ended in a word character and the new text starts with one. Parakeet already emits punctuation and casing; the formatter preserves it and only adds what is spoken.

The README voice table is the user-facing list; the table above is the grammar contract.

- `spell` takes letters, NATO words, digits and symbol words; one unknown token or a dangling `capital` types nothing.
- `find <words>` and `scroll to <words>` find on the page; bare `find` is ⌘F.
- `move` defaults to 50 px; `scroll` to 5 lines, max 50. `zoom <n>` puts a fresh 10×8 grid inside cell n.
- Dictation: spoken punctuation becomes characters; capitalize the utterance start and after `.`, `?`, `!`, newline; add a leading space between utterances when both sides touch words.

## 6. Mouse targeting

- **Grid:** 10×8 on the screen with the pointer, cells 1–80; zoomed cells are about 15×12 px.
- **Labels:** numbered badges on actionable accessibility elements of the frontmost app. Depth limit 12, budget 150 ms and 2000 nodes (browser: 600 ms and 5000, web area first), deduplicated by frame, capped at 200.
- **By name:** `click <name>` matches title, description or value: exact, then prefix, then contains.
- **Typing:** `CGEvent` Unicode events, at most 20 UTF-16 units per chunk, split on `Character` boundaries so emoji are never torn. No clipboard use.

## 7. LLM intent resolution

- **Provider:** Anthropic Messages API over raw HTTPS (no Swift SDK), `anthropic-version: 2026-10-21`, beta `server-side-fallback-2026-07-01`.
- **Model:** default `claude-haiku-5-5` at effort `low` (NH-95, for cost); `intentModel` and `intentEffort` override. Haiku has no fallback, so a declined request fails.
- **Request:** cacheable `system` prompt; one user turn with frontmost app, mode, up to 60 visible element titles with label numbers, then the transcript. `max_tokens` 2048. Output is forced to a JSON schema.
- **Schema:** `{intent, status, actions}`, all required; `actions.items` is an `anyOf` of 13 closed branches, every field required (`""` or `0` means omitted). Anthropic rejects one flat 32-field object and one branch per kind (NH-104 spec). Ollama still gets flat `ActionJSON`. No recursion or numeric constraints.
- **Prompt rules:** fewest actions; ambiguous requests return `ignore`.
- **Failures:** timeout 4 s. Any refusal, error or undecodable reply gives no actions and "didn't catch that". A missing key disables the path with a one-time notice.

## 8. Configuration

`~/.config/nohands/config.json`, all keys optional (the README lists them); `ANTHROPIC_API_KEY` wins over `anthropicAPIKey`. Defaults: `asrModelVersion` `v2` (English; `v3` multilingual), `silenceMs` 1000 (raised from 350 to allow pauses mid-command), `earlySilenceMs` 350 (ends a complete grammar command or "stop" early; 0 = off), grid 10×8, `moveStepPx` 50, `scrollStepLines` 5.

## 9. Latency budget (grammar path)

- End of speech 350 ms (`earlySilenceMs`; others wait `silenceMs`). Parakeet on ≤ 5 s, M1 Pro: ≤ 250 ms. Grammar plus executor ≤ 20 ms.
- Browser `show numbers` and `click <name>` add up to about 450 ms, plus a 600 ms settle the first time a Chromium browser is walked.
- **Total ≤ 650 ms**. The LLM path adds 1–3 s.

## 10. Permissions and packaging

`scripts/bundle.sh` builds `NoHands.app` (`LSUIElement`, `dev.nohands.app`), signed with `$CODESIGN_IDENTITY` (default ad-hoc). Accessibility trust follows the signature, so ad-hoc builds need re-granting each rebuild.

## 11. Acceptance (manual, end to end)

1. Launch `NoHands.app`, grant both permissions; the menu shows `CMD`.
2. In TextEdit say "start dictating", then "hello world period this is a test exclamation mark new line second line". TextEdit shows `Hello world. This is a test!⏎Second line`.
3. Say "stop dictating", "select all", "copy", "open safari", "new tab", "press command l", "type news dot ycombinator dot com", "enter". Safari loads the page.
4. Say "show numbers", then "click <n>" on a visible link: it opens. Say "grid", "zoom 35", "click 40": the pointer clicks inside the sub-cell.
5. Say "scroll down 10", "hold click", "move down 100", "release click": a drag happens.
6. Say "go to sleep", "click" (nothing happens), "wake up", "click" (click happens).
7. With an API key set, say "make this window full screen" (unmatched by the grammar): the model returns `press_key control command f` and the window toggles.
8. The console shows per-utterance latency lines; grammar-path totals are under 650 ms for complete grammar commands and stop phrases (early close, NH-36).
