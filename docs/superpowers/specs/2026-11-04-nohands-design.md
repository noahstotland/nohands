# NoHands: Voice-Only macOS Control — Design Spec

**Date:** 2026-11-04
**Status:** Draft, written from the user's brief without a brainstorming session. Decisions marked *(assumption)* were made by the planner and are the ones most worth challenging.

## 1. Goal

A menu-bar macOS app that lets the user operate the whole computer with their voice and nothing else: dictate text into any app, press keys and shortcuts, move and click the mouse, and issue natural-language commands — with low enough latency that it feels like a keyboard and mouse replacement rather than an accessibility afterthought.

## 2. Non-goals (this version)

- Wake word. The app is always listening; "go to sleep" / "wake up" gate it (an optional transcript-matched attention word exists, NH-12).
- Vision-model fallback (screenshot → click). The accessibility tree plus a numbered grid covers element targeting; a vision fallback is a follow-up plan.
- LLM "polish" of dictated text (Wispr-Flow-style rewriting). Spoken punctuation and auto-capitalization are deterministic in this version; LLM polish is a follow-up.
- Custom vocabulary boosting, multi-language ASR, Intel Macs, macOS < 14.
- App Store distribution / notarization.

## 3. Target environment

- macOS 14.5+, Apple Silicon (tested on M1 Pro, 16 GB).
- Xcode 16.2 / Swift 6.0.3 toolchain. Swift Package Manager only; no `.xcodeproj`.
- Network only for the LLM path. Speech recognition is fully on-device.

## 4. Architecture

```
mic (AVAudioEngine with voice processing / echo cancellation unless `echoCancellation` is false, 16 kHz mono Float32)
  → Silero VAD (FluidAudio VadManager, streaming)        ~ per 4096-sample chunk
  → UtteranceAssembler  (speechStart…speechEnd + padding) → [Float] utterance
  → Transcriber (FluidAudio AsrManager, Parakeet TDT v2)  → text   ≤ 250 ms
  → ModeMachine (command / dictation / sleep)
      ├─ dictation  → DictationFormatter → Action.typeText
      ├─ command    → CommandGrammar (deterministic, <1 ms) → [Action]
      │                  └─ unmatched → ClaudeIntentResolver (HTTP) → [Action]
      └─ sleep      → only "wake up" is honored
  → ActionExecutor
      ├─ InputSynthesizer (CGEvent keys / unicode typing / mouse)
      ├─ AXQuery (element lookup in the frontmost app)
      └─ OverlayController (grid, numbered labels, prompt board, status bar, corner task panel)
```

**Single vocabulary.** `Action` is the one enum every stage produces or consumes. The grammar, the LLM decoder, and the executor all speak `Action`; adding a capability means adding a case and handling it in three places.

**Grammar first, LLM second.** Every phrase in §6 is matched deterministically with no network. Only unmatched utterances go to the LLM (a `spell` phrase that can't be typed is rejected instead), so the common path is fully local and fast, and the app degrades to "grammar only" when offline.

**Targets are resolved late.** The grammar emits `ClickTarget.numbered(42)`; the executor decides whether 42 means a grid cell or a label based on which overlay is currently visible.

## 5. Modes

| Mode | Entered by | Behavior |
|---|---|---|
| `command` (default) | launch, "command mode", "stop dictating", "wake up" | every utterance is a command (with `attentionWord` set, only those that start with it) |
| `dictation` | "start dictating", "dictation mode" | every utterance is typed, except "stop dictating" / "command mode", "scratch that" and "delete word" |
| `sleep` | "go to sleep" | everything ignored except "wake up" |

Mode is shown in the menu bar: `mic` icon + `CMD` / `DICT` / `ZZZ` text.

The menu ends with a group above Quit: **Start at Login** (a checkbox backed by `SMAppService.mainApp`, read from the system each time the menu opens), **Status Bar** (a submenu Off / Top / Bottom for the always-on status bar, kept in user defaults) and **Open config.json…** (creates the file with mode 600 if missing, opens it in the default editor, and says to restart NoHands to apply changes).

## 6. Command grammar (deterministic)

Input is normalized first: lowercased, ASR punctuation stripped (`.,!?`), whitespace collapsed. Numbers may be digits or words ("forty two"); in a number slot, "to"/"too" → 2 and "for" → 4 (common ASR homophones).

| Phrase | Action |
|---|---|
| `type <words>` | `.typeText(formatted words)` (through DictationFormatter) |
| `spell <tokens>` | `.typeText(string)`: letters, letter-name homophones, NATO words, digits, `space`/`dash`/`dot`/`underscore`/`at sign`; `capital` uppercases the next letter. One unknown token or a dangling `capital` types nothing |
| `press <modifiers…> <key>` e.g. "press command shift s" | `.pressKey(KeyChord)` |
| `enter`, `tab`, `escape`, `space`, `delete` / `backspace`, `forward delete`, `up`/`down`/`left`/`right` | `.pressKey` of that key |
| `undo`, `redo`, `copy`, `paste`, `cut`, `select all`, `save`, `find`, `new tab`, `close tab`, `close window`, `quit app`, `switch app`, `spotlight`, `delete word`, `delete line` | the standard ⌘ shortcut (`redo` = ⇧⌘Z, `switch app` = ⌘⇥, `spotlight` = ⌘␣, `delete word` = ⌥⌫, `delete line` = ⌘⌫) |
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

## 7. Dictation formatting (deterministic)

Spoken tokens → characters: `period` `.`, `comma` `,`, `question mark` `?`, `exclamation point|mark` `!`, `colon` `:`, `semicolon` `;`, `dash` ` - `, `hyphen` `-`, `open quote` `"`, `close quote` `"`, `open paren` `(`, `close paren` `)`, `new line` `\n`, `new paragraph` `\n\n`. No space before `.,?!:;)`; space after them when followed by a word; capitalize the first letter of the utterance and of any word following `.`, `?`, `!`, or a newline. Across utterances, `DictationSession` inserts a leading space when the previous insertion ended in a word character and the new text starts with one. Parakeet already emits punctuation and casing; the formatter preserves it and only adds what is spoken.

## 8. Mouse targeting

- **Grid:** 10 columns × 8 rows over the screen containing the pointer, cells numbered 1–80 left-to-right, top-to-bottom, drawn as a translucent overlay with the number centered in each cell. `zoom <n>` replaces the grid with a 10×8 grid inside cell n; on a 1512×982 screen the zoomed cells are about 15×12 px, small enough to hit any control. `click <n>` clicks the cell center and hides the grid.
- **Labels:** numbered badges on every actionable accessibility element of the frontmost app (roles: button, link, text field, text area, checkbox, radio button, pop-up button, menu item, menu bar item, tab, slider, combo box, cell, row, disclosure triangle, increment/decrement). Elements are gathered depth-first with a depth limit of 12 and a time budget of 150 ms, deduplicated by frame, capped at 200, sorted top-to-bottom then left-to-right, numbered from 1.
- **By name:** `click <name>` finds, among those same elements, the one whose title / description / value matches `name` (case-insensitive; exact match preferred, then prefix, then contains). The executor moves the pointer there and clicks.
- **Coordinates:** CGEvent and the accessibility API both use a top-left-origin global coordinate space; AppKit windows use bottom-left. One `CoordinateMapper` does the flip using the primary screen's height.

## 9. Text input

Text is typed with `CGEvent` keyboard events carrying a Unicode string, in chunks of at most 20 UTF-16 code units, split only on `Character` boundaries (so emoji and combining sequences are never torn). No clipboard use, so the user's pasteboard is never clobbered. Key chords are posted as key-down / key-up pairs with modifier flags set on the event.

## 10. LLM intent resolution

- **Provider:** Anthropic Messages API over raw HTTPS (`URLSession`); there is no official Swift SDK. Endpoint `POST https://api.anthropic.com/v1/messages`, headers `x-api-key`, `anthropic-version: 2026-10-21`, `anthropic-beta: server-side-fallback-2026-07-01`.
- **Model:** default `claude-opus-5-5` at `output_config.effort: "low"` *(assumption: the Claude API skill's default; the user said "any model under the hood")*. `intentModel` in the config file overrides it; `claude-haiku-5-5` is the latency-oriented alternative. `fallbacks: "default"` is on so a safety refusal is re-run server-side instead of silently doing nothing.
- **Request:** `system` = fixed description of the `Action` vocabulary and the rules below (stable prefix, cacheable); `messages` = one user turn containing a compact context block (frontmost app name, current mode, up to 60 visible element titles with their label numbers) followed by the transcript. `max_tokens: 1024`. `output_config.format` = `{type: "json_schema", schema: ActionsSchema}` so the reply is guaranteed to parse.
- **ActionsSchema:** `{"actions": [ActionJSON]}` where `ActionJSON` is a flat object with `additionalProperties: false`, a required `kind` enum (`type_text, press_key, click, press_mouse, release_mouse, move_cursor, scroll, show_grid, zoom_grid, show_labels, hide_overlay, set_mode, open_app, search, ignore`) and optional `text, key, modifiers[], button, count, target_kind (cursor|grid_cell|label|element|point|relative), target_number, target_name, x, y, dx, dy, direction, amount, mode, app_name`. No recursion, no numeric constraints (the API rejects both).
- **Rules in the system prompt:** emit the fewest actions that accomplish the request; if the request is ambiguous or not an action, return `[{"kind":"ignore"}]`; refer to visible elements by their label number when one is listed; never invent app names.
- **Failure handling:** timeout 4 s; `stop_reason == "refusal"`, HTTP error, decode failure, or unknown `kind` → no actions, the prompt's row shows "didn't catch that"; missing API key → the LLM path is disabled and a notice line above the prompt rows says so once.

## 11. Configuration

`~/.config/nohands/config.json`, all keys optional:

```json
{
  "anthropicAPIKey": "sk-ant-…",       // or env ANTHROPIC_API_KEY (env wins)
  "intentModel": "claude-opus-5-5",
  "asrModelVersion": "v2",             // "v2" English-only (default) | "v3" multilingual
  "silenceMs": 1000,                   // VAD end-of-utterance silence (raised from 350 so you can pause mid-command)
  "earlySilenceMs": 350,               // shorter silence that ends a complete grammar command or "stop" early (0 = off)
  "gridColumns": 10, "gridRows": 8,
  "moveStepPx": 50, "scrollStepLines": 5
}
```

## 12. Latency budget (voice-to-action, grammar path)

| Stage | Budget |
|---|---|
| end-of-speech detection (silence) | 350 ms (`earlySilenceMs`, complete grammar commands and stop phrases only; anything else waits `silenceMs`, 1000 ms) |
| Parakeet TDT v2 on a ≤ 5 s utterance, M1 Pro | ≤ 250 ms |
| grammar + executor | ≤ 20 ms |
| **total** | **≤ 650 ms** |

Measured numbers for the early-close path are in [the NH-36 as-built](../as-built/2026-11-08-nh-36-early-grammar-endpointing.md).

The LLM path adds one network round trip (typically 1–3 s). Every utterance logs `t_speech_end, t_asr_done, t_actions_done` to the console so the budget can be verified.

## 13. Permissions and packaging

- Microphone (`NSMicrophoneUsageDescription`) and Accessibility (`AXIsProcessTrustedWithOptions`) are requested on first launch; the menu shows a red dot and an "Open Accessibility Settings" item until granted.
- The SwiftPM executable is wrapped into `NoHands.app` by `scripts/bundle.sh` (Info.plist with `LSUIElement = true`, bundle id `dev.nohands.app`), signed with `$CODESIGN_IDENTITY` (default ad-hoc `-`). Accessibility trust is tied to the code signature, so with ad-hoc signing every rebuild needs re-granting; a stable self-signed or Apple Development identity avoids that.
- `nohands-cli` (same package) exposes each subsystem for manual verification and latency measurement: `listen`, `transcribe <wav>`, `endpoint-test <wav>…`, `parse "<text>"`, `type "<text>"`, `elements`, `click "<name>"`, `grid`, `resolve "<text>"`.

## 14. Acceptance (manual, end to end)

1. Launch `NoHands.app`, grant both permissions, menu shows `CMD`.
2. Open TextEdit. Say "start dictating". Say "hello world period this is a test exclamation mark new line second line". TextEdit shows `Hello world. This is a test!⏎Second line`.
3. Say "stop dictating", "select all", "copy", "open safari", "new tab", "press command l", "type news dot ycombinator dot com", "enter". Safari loads the page.
4. Say "show numbers", "click <n>" for a visible link. The link opens. Say "grid", "zoom 35", "click 40". The pointer clicks inside the chosen sub-cell.
5. Say "scroll down 10", "hold click", "move down 100", "release click" — a drag happens.
6. Say "go to sleep", "click" (nothing happens), "wake up", "click" (click happens).
7. With an API key configured, say "make this window full screen" (unmatched by grammar). The LLM returns `press_key control command f` and the window toggles.
8. Console shows per-utterance latency lines; grammar-path totals are under 650 ms for complete grammar commands and stop phrases (early close, NH-36).
