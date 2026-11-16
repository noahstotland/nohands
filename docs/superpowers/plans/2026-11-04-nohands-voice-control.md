# NoHands Voice Control Implementation Plan

**Goal:** A menu-bar macOS app that types, presses keys, and drives the mouse from continuous speech, with a deterministic command grammar on the fast path and Claude for natural-language requests the grammar cannot match.

**Architecture:** Silero VAD segments mic audio and Parakeet (FluidAudio) transcribes it on-device. A mode machine routes each transcript to the dictation formatter, the command grammar, or the Claude intent resolver. All three produce the same `Action` enum, which one executor turns into CGEvents, accessibility lookups, and overlay windows. Pure logic lives in `NoHandsCore` (unit-tested); macOS integration lives in `NoHandsMac` (verified through `nohands-cli`).

**Tech Stack:** Swift 6.0 / SwiftPM, Swift Testing, AVFoundation, FluidAudio 0.18.x (Parakeet TDT v2 + Silero VAD), ApplicationServices (AXUIElement, CGEvent), AppKit, URLSession to the Anthropic Messages API.

**Spec:** `docs/superpowers/specs/2026-11-04-nohands-design.md`

## Global Constraints

- Swift tools 6.0, macOS 14+, language mode 6 on every target.
- Only dependency: FluidAudio `from: "0.18.2"`, product `FluidAudio` (no `FluidAudioTTS`).
- `NoHandsCore` imports only `Foundation` and `CoreGraphics`: no AppKit, FluidAudio or networking.
- Audio is 16 kHz, mono, `Float32`.
- CGEvent and AX coordinates are top-left-origin global points; AppKit flips happen only in `CoordinateMapper`.
- Anthropic request: `POST https://api.anthropic.com/v1/messages`, headers `x-api-key`, `anthropic-version: 2026-10-21`, `anthropic-beta: server-side-fallback-2026-07-01`. Body: `model` (default `claude-opus-5-5`), `max_tokens: 1024`, `fallbacks: "default"`, `output_config: {"effort": "low", "format": {"type": "json_schema", "schema": …}}`. No `temperature`, `thinking` or `tool_choice`.
- Config `~/.config/nohands/config.json`; env `ANTHROPIC_API_KEY` overrides its `anthropicAPIKey`.
- Bundle id `dev.nohands.app`, `LSUIElement = true`, mic usage description present.
- Test first, one conventional commit per task; never commit model files or `.build/`.

## Review Focus

1. ASR punctuation and casing on commands ("Click 42.") still match the grammar.
2. Number homophones ("click to", "click for") resolve to 2 / 4 in a number slot.
3. Out-of-range numbered targets ("click 150" with 80 cells, "click 7" with no overlay) do nothing and report, never click (0,0).
4. Non-BMP text (emoji, flags, combining marks) is typed without tearing surrogate pairs.
5. Malformed or unknown LLM output (unknown `kind`, missing fields, empty array, refusal) yields zero actions, not a crash or wrong action.

## Layout

- `Sources/NoHandsCore`: `Action`, `Keys`, `NumberWords`, `CommandGrammar`, `DictationFormatter`, `ModeMachine`, `GridModel`, `LabelAssigner`, `CoordinateMapper`, `TextChunker`, `UtteranceAssembler`, `IntentSchema`, `IntentDecoder`, `AppConfig`, `LatencyTrace`, `OverlayState`, `TargetResolver`.
- `Sources/NoHandsMac`: mic capture, VAD and Parakeet wrappers, `InputSynthesizer`, `Permissions`, `AXQuery`, `OverlayController`, `ActionExecutor`, `ClaudeIntentResolver`, `VoicePipeline`.
- `Sources/NoHands`: app bootstrap and `AppDelegate`. `Sources/nohands-cli`: subcommands for manual checks.
- `Tests/NoHandsCoreTests`, `Resources/Info.plist`, `scripts/bundle.sh`.

## Tasks

Each task is test-first (failing test, implement, pass, one commit). Manual checks need a focused app and Accessibility granted to the terminal. Signatures are in the repo; only contracts are listed.

### Task 1: Package scaffold and the Action vocabulary

- Targets: `NoHandsCore` (no deps), `NoHandsMac` (Core, FluidAudio), executables `NoHands` and `nohands-cli`, test target `NoHandsCoreTests`. The first build compiles FluidAudio (several minutes).
- Vocabulary (all `Codable, Sendable`): `Mode` (command, dictation, sleep), `ClickTarget` (cursor, numbered, element(named:), point), `MoveTarget` (adds relative(dx:dy:)), `KeyChord`, and `Action`: typeText, pressKey, click, pressMouse, releaseMouse, moveCursor, scroll, showGrid, zoomGrid, showLabels, hideOverlay, setMode, openApp, ignore.
- `Key.keyCode` is a hand-written Carbon `kVK_*` table because Core must not import Carbon. `Key.named` accepts the raw value plus "enter", "backspace", "dash", digit words and "f5".

### Task 2: Spoken number parsing

- `NumberWords.parse` accepts digits, words ("forty two", "forty-two", "one hundred five") and in-slot homophones ("to"/"too" = 2, "for" = 4). `leadingNumber(in:)` returns the longest numeric prefix and the rest.

### Task 3: Command grammar

- Defaults: `moveStepPx` 50, `scrollStepLines` 5, `maxScroll` 50.
- `normalize` lowercases, strips `.,!?` and collapses whitespace. `parse` returns nil when no rule matches (the caller falls back to the LLM).
- Rule order: exact-phrase table (modes, shortcuts, overlays, bare keys), then prefix rules `press`, `click` (also double/triple/right/middle), `move`, `scroll`, `zoom`, `open`, `type`.
- `press`: modifier tokens (`command`, `cmd`, `alt`, `ctrl`...) then a last token that must resolve via `Key.named`, else nil.
- `click <rest>`: a leading number is a numbered target, else strip a leading "the" and use the rest as an element name ("click the save button" gives "save button"). Scroll clamps to `maxScroll`.
- Modes: "start dictating" / "dictation mode"; "stop dictating" / "command mode"; "go to sleep"; "wake up".
- Shortcuts: "undo", "redo", "select all", "switch app" (cmd-tab), "spotlight", "delete word" (option-delete), "delete line" (cmd-delete).
- Also: grid, zoom, numbers, hide, open app, hold/release click, move, type. "make this window full screen" and "" are nil.

### Task 4: Dictation formatting

- `DictationFormatter.format(_:capitalizeStart:)` turns spoken punctuation into characters with spacing and sentence capitalization.
- Two-word tokens match before single words: question mark, exclamation point/mark, new line, new paragraph, open/close quote, open/close paren; also period, comma, colon, semicolon, dash, hyphen.
- The first letter and the first after `.`, `?`, `!` or newline are capitalized. ASR casing ("NASA", "I'm") is preserved.
- `DictationSession.next` prefixes a space when the previous insertion ended in a word character and the new text starts with one, and capitalizes only after a sentence end or an empty start. `type <words>` in the grammar goes through the formatter.

### Task 5: Mode machine and routing

- `route` returns `execute([Action])`, `resolveWithLLM(String)` or `ignore(reason:)`.
- Command mode: grammar, else LLM; blank is ignored. Dictation: the grammar runs only against the two exit phrases, everything else is typed through the session ("click save period" types "Click save."); entering dictation resets the session. Sleep: only "wake up" is checked.

### Task 6: Grid geometry, label numbering, coordinate flip

- `GridModel(bounds, columns 10, rows 8)`: cells are 1-based, row-major, nil out of range. `zoomed(into:)` gives the same grid inside that cell.
- `UIElementInfo(id, frame, title, role)`: `id` is an opaque AX handle, `frame` is top-left global.
- `LabelAssigner.assign(limit: 200)` dedupes by frame, sorts top-to-bottom then left-to-right (row tolerance 8 pt) and numbers from 1. `find(named:in:)` matches exact (case-insensitive), then prefix, then contains.
- `CoordinateMapper` flips AppKit and CG using the primary screen height.

### Task 7: Claude request builder and response decoder

- `AppConfig`: `anthropicAPIKey`, `intentModel` "claude-opus-5-5", `asrModelVersion` "v2", `silenceMs` 350, `gridColumns` 10, `gridRows` 8, `moveStepPx` 50, `scrollStepLines` 5. Loading defaults missing keys, ignores unknown ones and lets the env key win.
- `IntentContext(frontmostApp, mode, labeledElements)` carries at most 60 elements.
- User message: app, mode, numbered visible elements, then `Request: <transcript>`. The system prompt lists each `kind` with its fields and the three rules from spec §10.
- `IntentDecoder` checks `stop_reason` first (refusal throws), then parses the first `text` block as JSON and maps by `kind`. Unknown `kind` or missing required fields drops that action. Defaults: click button `left`, count 1.
- Tests cover the request body vs the Global Constraints, a schema with no `$ref`, closed objects and no `minimum`/`maxLength`, every `kind`, unknown `kind` and refusal.

### Task 8: Text chunking and CGEvent input

- `TextChunker.chunks(maxUTF16: 20)` splits on Character boundaries and never emits empty chunks.
- `CGEventInputSynthesizer`: `type` posts per chunk a key-down with `keyboardSetUnicodeString` and a key-up to `.cghidEventTap`, 1 ms between chunks. `press` sets flags from modifiers. `click` moves, then posts `count` down/up pairs with `mouseEventClickState`; middle uses `.otherMouse*`. `scroll` uses line units with two wheels (vertical positive = up, horizontal positive = left).
- Tests: chunk sizes, and flags, family emoji and combining marks are never split.

### Task 9: Microphone, VAD, utterance assembly, Parakeet

- `UtteranceAssembler(16 kHz, prePadMs 200, minSpeechMs 250, maxSpeechMs 15_000)` consumes samples plus VAD events and returns the utterance (speech plus pre-pad) when one ends. Shorter than `minSpeechMs` is dropped; `maxSpeechMs` forces a cut.
- `LatencyTrace` records `speechEnd`, `asrDone`, `actionsDone`.
- `MicrophoneCapture`: `AVAudioEngine` tap, converted to 16 kHz mono Float32 in chunks of 4096 samples (VAD chunk size).
- `VoiceActivity` (actor) wraps the FluidAudio VAD. `minSilenceDuration = silenceMs / 1000`, so end-of-speech delay follows the config.
- `ParakeetTranscriber` (actor) loads v2 or v3 models and transcribes with source `.microphone`; text is trimmed.
- Tests cover pre-pad, too-short drop and forced cut.
- Manual targets: ASR under 400 ms after warm-up, <= 250 ms for short phrases on an M1 Pro. First run downloads models (hundreds of MB).

### Task 10: Permissions and accessibility queries

- `Permissions`: Accessibility check with optional prompt, microphone request, open the Accessibility settings pane.
- `AXQuery`: frontmost app name; `actionableElements()` (roles per spec §8, depth <= 12, 150 ms budget, returns what it has when the budget is spent); `element(for:)`; `activate(appNamed:)` (case-insensitive).
- The walk skips zero-size or off-screen elements; title falls back to description, then value.

### Task 11: Overlay windows

- `OverlayState` (`none`, `grid`, `labels`) lives in Core so `TargetResolver` needs no AppKit.
- `@MainActor OverlayController`: `showGrid`, `showLabels`, `hide`, `showHUD` (default 1.5 s, bottom-center of the pointer's screen).
- One borderless non-activating `NSPanel` per role at `.screenSaver` level, ignoring mouse events, on all Spaces. Grid draws 25 % white borders with the cell number centered; labels draw a badge at each element's top-left; the HUD is a dark pill with 18 pt white text.
- Manual: the focused app keeps focus.

### Task 12: Action executor

- `TargetResolver.resolveClick` and `resolveMove` return a point or a failure message ("no cell 150", "no grid or labels shown", "no label 2", "no element named 'quit'"). They are two names because `.numbered(1)` is ambiguous across target types.
- `@MainActor ActionExecutor` runs actions in order, stops at the first failure, shows it in the HUD and returns it.
- Rules: `click` hides the overlay if a grid or labels were used; `showGrid` uses the screen under the cursor; `zoomGrid` without a grid fails; `showLabels` uses `LabelAssigner`; `.element(named:)` queries AX fresh each time; `setMode` calls `onModeChange`; `openApp` fails with "no app named …".
- Tests cover numbered targets against the visible overlay, out-of-range reporting, and element/cursor targets.

### Task 13: Claude intent resolver over HTTPS

- `IntentError`: `noAPIKey`, `network`, `http(Int, String)`, `decode`.
- `ClaudeIntentResolver` (actor) throws `.noAPIKey` without a key, sends the builder headers with a 4 s timeout, maps non-2xx to `.http(status, bodyPrefix)` and wraps decode errors.

### Task 14: Voice pipeline, menu-bar app, bundle script, README

- `@MainActor VoicePipeline` has `onStatus`, `start()`, `stop()`. Per transcript: show it in the HUD, route, then execute, or call the resolver (nil resolver shows "LLM disabled: no API key"), or ignore. A `LatencyTrace` per utterance is printed. The executor's `onModeChange` feeds back into the mode machine.
- App: `.accessory` activation policy. `AppDelegate` loads config, requests the mic, checks Accessibility with prompt, and creates a status item (`mic` symbol, title `CMD`/`DICT`/`ZZZ`). Menu: last transcript, Pause/Resume Listening, Open Accessibility Settings (red dot while not granted), Quit.
- The pipeline starts once both permissions are granted; Accessibility is polled every 2 s until then.
- `Info.plist` and `scripts/bundle.sh` (release build, assemble `build/NoHands.app`, copy resource bundles, ad-hoc codesign by default via `CODESIGN_IDENTITY`).
- README covers build, first-run permissions and the ad-hoc re-grant caveat, config, phrases, CLI, latency.
- Verify end to end with `scripts/bundle.sh && open build/NoHands.app`, spec §14 steps 1-8. One latency line per utterance, grammar-path totals <= 650 ms.
