# NoHands Voice Control Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A menu-bar macOS app that types, presses keys, and drives the mouse from continuous speech, with a deterministic command grammar on the fast path and Claude for natural-language requests the grammar cannot match.

**Architecture:** Mic audio is segmented by Silero VAD and transcribed on-device by Parakeet (FluidAudio). A mode machine routes each transcript to the dictation formatter, the command grammar, or the Claude intent resolver; all three produce the same `Action` enum, which one executor turns into CGEvents, accessibility lookups, and overlay windows. Pure logic lives in `NoHandsCore` (fully unit-tested); macOS integration lives in `NoHandsMac` (verified through `nohands-cli`).

**Tech Stack:** Swift 6.0 / SwiftPM, Swift Testing, AVFoundation, FluidAudio 0.18.x (Parakeet TDT v2 + Silero VAD, CoreML), ApplicationServices (AXUIElement, CGEvent), AppKit (NSStatusItem, NSPanel), URLSession → Anthropic Messages API.

**Spec:** `docs/superpowers/specs/2026-11-04-nohands-design.md`

## Global Constraints

- `// swift-tools-version: 6.0`; `platforms: [.macOS(.v14)]`; Swift language mode 6 (strict concurrency) on every target.
- Dependency: `https://github.com/FluidInference/FluidAudio.git` `from: "0.18.2"`, product `FluidAudio` only (no `FluidAudioTTS`). No other third-party dependencies.
- `NoHandsCore` imports only `Foundation` and `CoreGraphics` (for `CGPoint`/`CGRect`). No AppKit, no FluidAudio, no networking.
- Audio everywhere is 16 kHz, mono, `Float32`, as `[Float]`.
- Coordinates handed to CGEvent and read from AX are top-left-origin global points; AppKit flips happen only in `CoordinateMapper`.
- Anthropic request: `POST https://api.anthropic.com/v1/messages`, headers `x-api-key`, `anthropic-version: 2026-10-21`, `anthropic-beta: server-side-fallback-2026-07-01`; body has `model` (default `claude-opus-5-5`), `max_tokens: 1024`, `fallbacks: "default"`, `output_config: {"effort": "low", "format": {"type": "json_schema", "schema": …}}`. No `temperature`, no `thinking`, no `tool_choice`.
- Config file: `~/.config/nohands/config.json`; env `ANTHROPIC_API_KEY` overrides the file's `anthropicAPIKey`.
- App bundle id `dev.nohands.app`, `LSUIElement = true`, `NSMicrophoneUsageDescription` present.
- Tests use Swift Testing (`import Testing`, `@Test`, `#expect`). Run with `swift test`.
- Commit after every task with a conventional-commit message; never commit model files or `.build/`.

## Review Focus

1. **ASR punctuation and casing on commands** ("Click 42." / "Press Enter.") must still match the grammar. Pinned in Task 3 (`normalizesAsrPunctuation`).
2. **Number homophones** ("click to", "click for", "scroll down too") must resolve to 2 / 4 / 2 in a number slot. Pinned in Task 2 (`homophonesInNumberSlot`).
3. **Out-of-range numbered targets** ("click 150" with 80 cells, "click 7" with no overlay) must do nothing and report, not crash or click (0,0). Pinned in Task 12 (`numberedTargetOutOfRangeIsReported`).
4. **Non-BMP text** (emoji, flags, combining marks) must be typed without tearing surrogate pairs. Pinned in Task 8 (`neverSplitsGraphemeClusters`).
5. **Malformed or unknown LLM output** (unknown `kind`, missing fields, empty array, refusal) must yield zero actions rather than a crash or a wrong action. Pinned in Task 7 (`unknownKindYieldsNoActions`, `refusalYieldsNoActions`).

---

## File Structure

```
Package.swift
Sources/
  NoHandsCore/                       # pure logic, unit-tested
    Action.swift                     # Action, ClickTarget, MoveTarget, Direction, MouseButton, Mode
    Keys.swift                       # Key, Modifier, KeyChord, Key.keyCode
    NumberWords.swift                # spoken number parsing
    CommandGrammar.swift             # deterministic phrase → [Action]
    DictationFormatter.swift         # spoken punctuation, casing, DictationSession spacing
    ModeMachine.swift                # mode state + routing decision
    GridModel.swift                  # grid geometry, zoom
    LabelAssigner.swift              # ordering/numbering of UI elements
    CoordinateMapper.swift           # AppKit ⇄ CG flip
    TextChunker.swift                # ≤20 UTF-16 unit chunks on Character boundaries
    UtteranceAssembler.swift         # VAD events + samples → utterances
    IntentSchema.swift               # ActionsSchema JSON + ClaudeRequestBuilder
    IntentDecoder.swift              # Claude response JSON → [Action]
    AppConfig.swift                  # config.json model + defaults
    LatencyTrace.swift               # per-utterance stage timestamps
  NoHandsMac/                        # macOS integration, verified via CLI
    MicrophoneCapture.swift          # AVAudioEngine → 16 kHz [Float] chunks
    VoiceActivity.swift              # FluidAudio VadManager wrapper
    ParakeetTranscriber.swift        # FluidAudio AsrManager wrapper
    InputSynthesizer.swift           # CGEvent keys, typing, mouse
    Permissions.swift                # AX + mic authorization
    AXQuery.swift                    # actionable elements of the frontmost app
    OverlayController.swift          # grid / labels / HUD NSPanels
    ActionExecutor.swift             # Action → side effects
    ClaudeIntentResolver.swift       # URLSession client
    VoicePipeline.swift              # wires mic → VAD → ASR → router → executor
  NoHands/
    main.swift                       # NSApplication bootstrap
    AppDelegate.swift                # status item, menu, pipeline lifecycle
  nohands-cli/
    main.swift                       # subcommands for manual verification
Tests/NoHandsCoreTests/              # one test file per Core source file
Resources/Info.plist
Scripts/bundle.sh
```

---

### Task 1: Package scaffold and the Action vocabulary

**Files:**
- Create: `Package.swift`, `Sources/NoHandsCore/Action.swift`, `Sources/NoHandsCore/Keys.swift`, `Sources/NoHandsMac/Placeholder.swift`, `Sources/NoHands/main.swift`, `Sources/nohands-cli/main.swift`, `Tests/NoHandsCoreTests/KeysTests.swift`, `.gitignore`

**Interfaces:**
- Produces:
  ```swift
  public enum Mode: String, Codable, Sendable { case command, dictation, sleep }
  public enum MouseButton: String, Codable, Sendable { case left, right, middle }
  public enum Direction: String, Codable, Sendable { case up, down, left, right }
  public enum ClickTarget: Equatable, Codable, Sendable {
      case cursor
      case numbered(Int)                       // grid cell or label; executor decides
      case element(named: String)
      case point(CGPoint)
  }
  public enum MoveTarget: Equatable, Codable, Sendable {
      case numbered(Int)
      case element(named: String)
      case point(CGPoint)
      case relative(dx: Int, dy: Int)
  }
  public enum Action: Equatable, Codable, Sendable {
      case typeText(String)
      case pressKey(KeyChord)
      case click(ClickTarget, button: MouseButton, count: Int)
      case pressMouse(MouseButton)
      case releaseMouse(MouseButton)
      case moveCursor(MoveTarget)
      case scroll(Direction, amount: Int)
      case showGrid
      case zoomGrid(Int)
      case showLabels
      case hideOverlay
      case setMode(Mode)
      case openApp(String)
      case ignore
  }
  public enum Modifier: String, Codable, Sendable, CaseIterable { case command, shift, option, control, function }
  public enum Key: String, Codable, Sendable, CaseIterable {
      case a, b, …, z, zero, one, …, nine
      case `return`, tab, space, delete, forwardDelete, escape
      case up, down, left, right, home, end, pageUp, pageDown
      case f1, …, f12
      case minus, equal, leftBracket, rightBracket, semicolon, quote, comma, period, slash, backslash, grave
      public var keyCode: UInt16 { get }        // Carbon kVK_* values
      public static func named(_ spoken: String) -> Key?   // "enter"→.return, "backspace"→.delete, "dash"→.minus, "a"…, digits, "f5"
  }
  public struct KeyChord: Equatable, Codable, Sendable { public var key: Key; public var modifiers: Set<Modifier>; public init(_ key: Key, _ modifiers: Set<Modifier> = []) }
  ```

- [ ] **Step 1: Write `Package.swift`**

Targets: library `NoHandsCore` (no deps); library `NoHandsMac` (deps: `NoHandsCore`, `.product(name: "FluidAudio", package: "FluidAudio")`); executable `NoHands` (dep `NoHandsMac`); executable `nohands-cli` (dep `NoHandsMac`); test target `NoHandsCoreTests` (dep `NoHandsCore`). Add `swiftSettings: [.swiftLanguageMode(.v6)]` to each target. `.gitignore`: `.build/`, `*.app`, `.DS_Store`, `.swiftpm/`.

- [ ] **Step 2: Write the failing test**

```swift
// Tests/NoHandsCoreTests/KeysTests.swift
import Testing
@testable import NoHandsCore

@Test func keyCodesMatchCarbon() {
    #expect(Key.a.keyCode == 0)
    #expect(Key.return.keyCode == 36)
    #expect(Key.space.keyCode == 49)
    #expect(Key.delete.keyCode == 51)
    #expect(Key.escape.keyCode == 53)
    #expect(Key.left.keyCode == 123)
    #expect(Key.up.keyCode == 126)
}

@Test func spokenKeyNames() {
    #expect(Key.named("enter") == .return)
    #expect(Key.named("backspace") == .delete)
    #expect(Key.named("escape") == .escape)
    #expect(Key.named("f5") == .f5)
    #expect(Key.named("seven") == .seven)
    #expect(Key.named("banana") == nil)
}

@Test func actionRoundTripsThroughJSON() throws {
    let actions: [Action] = [.click(.numbered(42), button: .left, count: 2), .pressKey(KeyChord(.s, [.command])), .moveCursor(.relative(dx: -50, dy: 0))]
    let data = try JSONEncoder().encode(actions)
    #expect(try JSONDecoder().decode([Action].self, from: data) == actions)
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --filter KeysTests`
Expected: compile error, `Key` not defined.

- [ ] **Step 4: Implement `Action.swift` and `Keys.swift`**

`Key.keyCode`: `NoHandsCore` must not import Carbon, so write the table by hand from `Carbon.HIToolbox/Events.h` `kVK_*` constants (ANSI layout). `Key.named` accepts the raw value, the spoken aliases listed in the interface, and English digit words. Placeholder files for the other targets contain only an `import Foundation` / `print("nohands")` so the package builds.

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift build && swift test --filter KeysTests`
Expected: `Test run with 3 tests passed`. (First `swift build` resolves and compiles FluidAudio; several minutes.)

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources Tests .gitignore
git commit -m "feat: scaffold package with Action vocabulary and key table"
```

---

### Task 2: Spoken number parsing

**Files:**
- Create: `Sources/NoHandsCore/NumberWords.swift`, `Tests/NoHandsCoreTests/NumberWordsTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public enum NumberWords {
      /// Parses a run of tokens as a cardinal number. Accepts digits ("42"), words ("forty two", "one hundred five"),
      /// and in-slot homophones ("to"/"too" → 2, "for" → 4). Returns nil if the tokens are not a number.
      public static func parse(_ tokens: [String]) -> Int?
      /// Longest prefix of `tokens` that parses as a number, with the remainder.
      public static func leadingNumber(in tokens: [String]) -> (value: Int, rest: [String])?
  }
  ```

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import NoHandsCore

@Test func digitsAndWords() {
    #expect(NumberWords.parse(["42"]) == 42)
    #expect(NumberWords.parse(["forty", "two"]) == 42)
    #expect(NumberWords.parse(["forty-two"]) == 42)
    #expect(NumberWords.parse(["one", "hundred", "five"]) == 105)
    #expect(NumberWords.parse(["zero"]) == 0)
    #expect(NumberWords.parse(["twelve"]) == 12)
}

@Test func homophonesInNumberSlot() {
    #expect(NumberWords.parse(["to"]) == 2)
    #expect(NumberWords.parse(["too"]) == 2)
    #expect(NumberWords.parse(["for"]) == 4)
    #expect(NumberWords.parse(["twenty", "to"]) == 22)
}

@Test func nonNumbers() {
    #expect(NumberWords.parse(["save"]) == nil)
    #expect(NumberWords.parse([]) == nil)
    #expect(NumberWords.parse(["forty", "save"]) == nil)
}

@Test func leadingNumberSplitsRest() {
    let r = NumberWords.leadingNumber(in: ["thirty", "five", "pixels"])
    #expect(r?.value == 35)
    #expect(r?.rest == ["pixels"])
    #expect(NumberWords.leadingNumber(in: ["pixels"]) == nil)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter NumberWordsTests`
Expected: compile error, `NumberWords` not defined.

- [ ] **Step 3: Implement `NumberWords`**

Units 0–19, tens 20–90, `hundred` multiplier, optional `and`. Split hyphenated tokens before parsing. `leadingNumber` tries prefixes from longest to shortest.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter NumberWordsTests`
Expected: 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/NoHandsCore/NumberWords.swift Tests/NoHandsCoreTests/NumberWordsTests.swift
git commit -m "feat: parse spoken numbers with ASR homophones"
```

---

### Task 3: Command grammar

**Files:**
- Create: `Sources/NoHandsCore/CommandGrammar.swift`, `Tests/NoHandsCoreTests/CommandGrammarTests.swift`

**Interfaces:**
- Consumes: `NumberWords.leadingNumber`, `Key.named`, `Action` (Task 1–2).
- Produces:
  ```swift
  public struct GrammarConfig: Sendable { public var moveStepPx: Int = 50; public var scrollStepLines: Int = 5; public var maxScroll: Int = 50; public init() }
  public struct CommandGrammar: Sendable {
      public init(config: GrammarConfig = GrammarConfig())
      /// Lowercases, strips ASR punctuation (.,!?), collapses whitespace, splits on spaces.
      public static func normalize(_ transcript: String) -> [String]
      /// nil when no rule matches (caller falls back to the LLM).
      public func parse(_ transcript: String) -> [Action]?
  }
  ```
  `typeText` payloads from `type <words>` pass through `DictationFormatter.format` (Task 4). Until Task 4 lands, `parse` returns the raw words; Task 4 switches it over.

- [ ] **Step 1: Write the failing tests** (one `@Test` per spec row group)

```swift
import Testing
@testable import NoHandsCore

let g = CommandGrammar()

@Test func normalizesAsrPunctuation() {
    #expect(CommandGrammar.normalize("  Click 42. ") == ["click", "42"])
    #expect(g.parse("Press Enter.") == [.pressKey(KeyChord(.return))])
}

@Test func modeCommands() {
    #expect(g.parse("start dictating") == [.setMode(.dictation)])
    #expect(g.parse("dictation mode") == [.setMode(.dictation)])
    #expect(g.parse("stop dictating") == [.setMode(.command)])
    #expect(g.parse("command mode") == [.setMode(.command)])
    #expect(g.parse("go to sleep") == [.setMode(.sleep)])
    #expect(g.parse("wake up") == [.setMode(.command)])
}

@Test func keysAndShortcuts() {
    #expect(g.parse("press command shift s") == [.pressKey(KeyChord(.s, [.command, .shift]))])
    #expect(g.parse("press escape") == [.pressKey(KeyChord(.escape))])
    #expect(g.parse("enter") == [.pressKey(KeyChord(.return))])
    #expect(g.parse("backspace") == [.pressKey(KeyChord(.delete))])
    #expect(g.parse("left") == [.pressKey(KeyChord(.left))])
    #expect(g.parse("undo") == [.pressKey(KeyChord(.z, [.command]))])
    #expect(g.parse("redo") == [.pressKey(KeyChord(.z, [.command, .shift]))])
    #expect(g.parse("select all") == [.pressKey(KeyChord(.a, [.command]))])
    #expect(g.parse("switch app") == [.pressKey(KeyChord(.tab, [.command]))])
    #expect(g.parse("spotlight") == [.pressKey(KeyChord(.space, [.command]))])
    #expect(g.parse("delete word") == [.pressKey(KeyChord(.delete, [.option]))])
    #expect(g.parse("delete line") == [.pressKey(KeyChord(.delete, [.command]))])
}

@Test func mouseCommands() {
    #expect(g.parse("click") == [.click(.cursor, button: .left, count: 1)])
    #expect(g.parse("double click") == [.click(.cursor, button: .left, count: 2)])
    #expect(g.parse("right click") == [.click(.cursor, button: .right, count: 1)])
    #expect(g.parse("click forty two") == [.click(.numbered(42), button: .left, count: 1)])
    #expect(g.parse("click to") == [.click(.numbered(2), button: .left, count: 1)])
    #expect(g.parse("click save") == [.click(.element(named: "save"), button: .left, count: 1)])
    #expect(g.parse("click the save button") == [.click(.element(named: "save button"), button: .left, count: 1)])
    #expect(g.parse("hold click") == [.pressMouse(.left)])
    #expect(g.parse("release click") == [.releaseMouse(.left)])
    #expect(g.parse("move up") == [.moveCursor(.relative(dx: 0, dy: -50))])
    #expect(g.parse("move right 120") == [.moveCursor(.relative(dx: 120, dy: 0))])
    #expect(g.parse("move to 12") == [.moveCursor(.numbered(12))])
    #expect(g.parse("scroll down") == [.scroll(.down, amount: 5)])
    #expect(g.parse("scroll up 500") == [.scroll(.up, amount: 50)])
}

@Test func overlaysAndApps() {
    #expect(g.parse("grid") == [.showGrid])
    #expect(g.parse("show grid") == [.showGrid])
    #expect(g.parse("zoom 35") == [.zoomGrid(35)])
    #expect(g.parse("show numbers") == [.showLabels])
    #expect(g.parse("numbers") == [.showLabels])
    #expect(g.parse("hide") == [.hideOverlay])
    #expect(g.parse("cancel") == [.hideOverlay])
    #expect(g.parse("open safari") == [.openApp("safari")])
    #expect(g.parse("open visual studio code") == [.openApp("visual studio code")])
}

@Test func typeCommandAndUnmatched() {
    #expect(g.parse("type hello world") == [.typeText("hello world")])
    #expect(g.parse("make this window full screen") == nil)
    #expect(g.parse("") == nil)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter CommandGrammarTests`
Expected: compile error, `CommandGrammar` not defined.

- [ ] **Step 3: Implement `CommandGrammar`**

Rule order matters: exact-phrase table (modes, shortcuts, overlays, bare keys) first; then prefix rules `press`, `click`, `double/triple/right/middle click`, `move`, `scroll`, `zoom`, `open`, `type`. In `press`, every token that is a `Modifier` raw value (plus aliases `cmd`, `alt`, `ctrl`) is a modifier; the last token must resolve via `Key.named`, else return nil. `click <rest>`: leading number → `.numbered`; otherwise strip a leading article ("the") and join the rest as the element name. Clamp scroll to `maxScroll`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter CommandGrammarTests`
Expected: 7 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/NoHandsCore/CommandGrammar.swift Tests/NoHandsCoreTests/CommandGrammarTests.swift
git commit -m "feat: deterministic command grammar"
```

---

### Task 4: Dictation formatting

**Files:**
- Create: `Sources/NoHandsCore/DictationFormatter.swift`, `Tests/NoHandsCoreTests/DictationFormatterTests.swift`
- Modify: `Sources/NoHandsCore/CommandGrammar.swift` (route `type <words>` through `DictationFormatter.format`)

**Interfaces:**
- Produces:
  ```swift
  public enum DictationFormatter {
      /// Spoken punctuation → characters, spacing, sentence capitalization. Pure function of one utterance.
      /// `capitalizeStart: false` leaves the first word's case alone (used mid-sentence by DictationSession).
      public static func format(_ transcript: String, capitalizeStart: Bool = true) -> String
  }
  public struct DictationSession: Sendable {
      public init()
      /// Formats `transcript` and prefixes a space when the previous insertion ended with a word character
      /// and the new text starts with one. Records the text as inserted.
      public mutating func next(_ transcript: String) -> String
  }
  ```

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import NoHandsCore

@Test func spokenPunctuation() {
    #expect(DictationFormatter.format("hello world period this is a test exclamation mark") == "Hello world. This is a test!")
    #expect(DictationFormatter.format("yes comma please question mark") == "Yes, please?")
    #expect(DictationFormatter.format("one colon two semicolon three") == "One: two; three")
    #expect(DictationFormatter.format("open quote hi close quote") == "\"hi\"")
    #expect(DictationFormatter.format("open paren note close paren") == "(note)")
    #expect(DictationFormatter.format("a dash b") == "A - b")
    #expect(DictationFormatter.format("well hyphen known") == "Well-known")
}

@Test func newlines() {
    #expect(DictationFormatter.format("first line new line second line") == "First line\nSecond line")
    #expect(DictationFormatter.format("para one new paragraph para two") == "Para one\n\nPara two")
}

@Test func preservesAsrPunctuationAndCasing() {
    #expect(DictationFormatter.format("Hello, I'm Noah. Nice to meet you.") == "Hello, I'm Noah. Nice to meet you.")
    #expect(DictationFormatter.format("send it to NASA period") == "Send it to NASA.")
}

@Test func sessionSpacing() {
    var s = DictationSession()
    #expect(s.next("hello") == "Hello")
    #expect(s.next("world period") == " world.")
    #expect(s.next("next sentence") == " Next sentence")
    #expect(s.next("new line") == "\n")
    #expect(s.next("after break") == "After break")
}

@Test func grammarTypeUsesFormatter() {
    #expect(CommandGrammar().parse("type hello comma world") == [.typeText("Hello, world")])
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter DictationFormatterTests`
Expected: compile error, `DictationFormatter` not defined.

- [ ] **Step 3: Implement `DictationFormatter` and `DictationSession`; update `CommandGrammar`**

Tokenize on whitespace; two-word tokens (`question mark`, `exclamation point|mark`, `new line`, `new paragraph`, `open quote`, `close quote`, `open paren`, `close paren`) are matched before single-word tokens. Capitalize the first alphabetic character of the output and the first alphabetic character after `.`, `?`, `!`, or `\n`. `DictationSession` capitalizes only when its previous insertion ended a sentence or was empty; after `" world."` the next utterance is capitalized, after `"hello"` it is not (test above reflects this: `"Hello"` then `" world."` then `" Next sentence"`).

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter "DictationFormatterTests|CommandGrammarTests"`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/NoHandsCore/DictationFormatter.swift Sources/NoHandsCore/CommandGrammar.swift Tests/NoHandsCoreTests/DictationFormatterTests.swift
git commit -m "feat: dictation formatting with spoken punctuation"
```

---

### Task 5: Mode machine and routing

**Files:**
- Create: `Sources/NoHandsCore/ModeMachine.swift`, `Tests/NoHandsCoreTests/ModeMachineTests.swift`

**Interfaces:**
- Consumes: `CommandGrammar.parse`, `DictationSession.next`, `Mode`, `Action`.
- Produces:
  ```swift
  public enum Routing: Equatable, Sendable {
      case execute([Action])
      case resolveWithLLM(String)     // normalized transcript
      case ignore(reason: String)
  }
  public struct ModeMachine: Sendable {
      public private(set) var mode: Mode
      public init(grammar: CommandGrammar = CommandGrammar(), mode: Mode = .command)
      /// Applies mode transitions contained in the result and returns what the executor should do.
      public mutating func route(_ transcript: String) -> Routing
  }
  ```

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import NoHandsCore

@Test func commandModeRoutesGrammarThenLLM() {
    var m = ModeMachine()
    #expect(m.route("click") == .execute([.click(.cursor, button: .left, count: 1)]))
    #expect(m.route("make the window bigger") == .resolveWithLLM("make the window bigger"))
    #expect(m.route("   ") == .ignore(reason: "empty"))
}

@Test func dictationModeTypesEverythingExceptExit() {
    var m = ModeMachine()
    #expect(m.route("start dictating") == .execute([.setMode(.dictation)]))
    #expect(m.mode == .dictation)
    #expect(m.route("click save period") == .execute([.typeText("Click save.")]))
    #expect(m.route("stop dictating") == .execute([.setMode(.command)]))
    #expect(m.mode == .command)
}

@Test func sleepIgnoresAllButWakeUp() {
    var m = ModeMachine()
    _ = m.route("go to sleep")
    #expect(m.mode == .sleep)
    #expect(m.route("click") == .ignore(reason: "sleeping"))
    #expect(m.route("make it bigger") == .ignore(reason: "sleeping"))
    #expect(m.route("wake up") == .execute([.setMode(.command)]))
    #expect(m.mode == .command)
}

@Test func dictationSessionSpacingPersistsAcrossRoutes() {
    var m = ModeMachine()
    _ = m.route("start dictating")
    #expect(m.route("hello") == .execute([.typeText("Hello")]))
    #expect(m.route("world") == .execute([.typeText(" world")]))
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ModeMachineTests`
Expected: compile error, `ModeMachine` not defined.

- [ ] **Step 3: Implement `ModeMachine`**

In `.dictation`, run the grammar only against the two exit phrases; everything else goes through the stored `DictationSession`. Entering dictation resets the session. In `.sleep`, only `"wake up"` is checked.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ModeMachineTests`
Expected: 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/NoHandsCore/ModeMachine.swift Tests/NoHandsCoreTests/ModeMachineTests.swift
git commit -m "feat: mode machine routing transcripts to grammar, dictation, or LLM"
```

---

### Task 6: Grid geometry, label numbering, coordinate flip

**Files:**
- Create: `Sources/NoHandsCore/GridModel.swift`, `Sources/NoHandsCore/LabelAssigner.swift`, `Sources/NoHandsCore/CoordinateMapper.swift`, `Tests/NoHandsCoreTests/GridModelTests.swift`, `Tests/NoHandsCoreTests/LabelAssignerTests.swift`, `Tests/NoHandsCoreTests/CoordinateMapperTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public struct GridModel: Equatable, Sendable {
      public let bounds: CGRect; public let columns: Int; public let rows: Int
      public init(bounds: CGRect, columns: Int = 10, rows: Int = 8)
      public var cellCount: Int { columns * rows }
      public func frame(of cell: Int) -> CGRect?          // 1-based, row-major; nil if out of range
      public func center(of cell: Int) -> CGPoint?
      public func zoomed(into cell: Int) -> GridModel?     // same columns/rows inside that cell
  }
  public struct UIElementInfo: Equatable, Sendable {
      public var id: Int               // opaque handle the Mac layer maps back to an AXUIElement
      public var frame: CGRect         // top-left-origin global
      public var title: String; public var role: String
      public init(id: Int, frame: CGRect, title: String, role: String)
  }
  public enum LabelAssigner {
      /// Dedupes by frame, sorts top-to-bottom then left-to-right (row tolerance 8 pt), caps at `limit`, numbers from 1.
      public static func assign(_ elements: [UIElementInfo], limit: Int = 200) -> [Int: UIElementInfo]
      /// exact (case-insensitive) title match first, then prefix, then contains; nil if none.
      public static func find(named name: String, in elements: [UIElementInfo]) -> UIElementInfo?
  }
  public enum CoordinateMapper {
      public static func toAppKit(_ p: CGPoint, primaryScreenHeight: CGFloat) -> CGPoint
      public static func toAppKit(_ r: CGRect, primaryScreenHeight: CGFloat) -> CGRect
      public static func toCG(_ p: CGPoint, primaryScreenHeight: CGFloat) -> CGPoint
  }
  ```

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import CoreGraphics
@testable import NoHandsCore

@Test func gridCellsAreRowMajorOneBased() {
    let g = GridModel(bounds: CGRect(x: 0, y: 0, width: 1000, height: 800))
    #expect(g.cellCount == 80)
    #expect(g.frame(of: 1) == CGRect(x: 0, y: 0, width: 100, height: 100))
    #expect(g.frame(of: 10) == CGRect(x: 900, y: 0, width: 100, height: 100))
    #expect(g.frame(of: 11) == CGRect(x: 0, y: 100, width: 100, height: 100))
    #expect(g.center(of: 80) == CGPoint(x: 950, y: 750))
    #expect(g.frame(of: 0) == nil)
    #expect(g.frame(of: 81) == nil)
}

@Test func zoomSubdividesCell() {
    let g = GridModel(bounds: CGRect(x: 0, y: 0, width: 1000, height: 800))
    let z = g.zoomed(into: 12)!
    #expect(z.bounds == CGRect(x: 100, y: 100, width: 100, height: 100))
    #expect(z.center(of: 1) == CGPoint(x: 105, y: 106.25))
    #expect(g.zoomed(into: 99) == nil)
}

@Test func labelsOrderedTopToBottomLeftToRight() {
    let a = UIElementInfo(id: 1, frame: CGRect(x: 300, y: 10, width: 50, height: 20), title: "Save", role: "AXButton")
    let b = UIElementInfo(id: 2, frame: CGRect(x: 10, y: 14, width: 50, height: 20), title: "Cancel", role: "AXButton")
    let c = UIElementInfo(id: 3, frame: CGRect(x: 10, y: 200, width: 50, height: 20), title: "Help", role: "AXLink")
    let dup = UIElementInfo(id: 4, frame: a.frame, title: "Save", role: "AXButton")
    let labels = LabelAssigner.assign([a, c, b, dup])
    #expect(labels.count == 3)
    #expect(labels[1] == b); #expect(labels[2] == a); #expect(labels[3] == c)
    #expect(LabelAssigner.assign([a, b, c], limit: 2).count == 2)
}

@Test func findByNamePrefersExact() {
    let els = [UIElementInfo(id: 1, frame: .zero, title: "Save As…", role: "AXButton"),
               UIElementInfo(id: 2, frame: .zero, title: "Save", role: "AXButton"),
               UIElementInfo(id: 3, frame: .zero, title: "Don't Save", role: "AXButton")]
    #expect(LabelAssigner.find(named: "save", in: els)?.id == 2)
    #expect(LabelAssigner.find(named: "save as", in: els)?.id == 1)
    #expect(LabelAssigner.find(named: "don't", in: els)?.id == 3)
    #expect(LabelAssigner.find(named: "quit", in: els) == nil)
}

@Test func coordinateFlip() {
    #expect(CoordinateMapper.toAppKit(CGPoint(x: 10, y: 20), primaryScreenHeight: 1000) == CGPoint(x: 10, y: 980))
    #expect(CoordinateMapper.toCG(CGPoint(x: 10, y: 980), primaryScreenHeight: 1000) == CGPoint(x: 10, y: 20))
    #expect(CoordinateMapper.toAppKit(CGRect(x: 0, y: 0, width: 100, height: 50), primaryScreenHeight: 1000) == CGRect(x: 0, y: 950, width: 100, height: 50))
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter "GridModelTests|LabelAssignerTests|CoordinateMapperTests"`
Expected: compile errors for the three undefined types.

- [ ] **Step 3: Implement the three files**

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter "GridModelTests|LabelAssignerTests|CoordinateMapperTests"`
Expected: 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/NoHandsCore/GridModel.swift Sources/NoHandsCore/LabelAssigner.swift Sources/NoHandsCore/CoordinateMapper.swift Tests/NoHandsCoreTests
git commit -m "feat: grid geometry, label numbering, coordinate mapping"
```

---

### Task 7: Claude request builder and response decoder

**Files:**
- Create: `Sources/NoHandsCore/IntentSchema.swift`, `Sources/NoHandsCore/IntentDecoder.swift`, `Sources/NoHandsCore/AppConfig.swift`, `Tests/NoHandsCoreTests/IntentTests.swift`, `Tests/NoHandsCoreTests/AppConfigTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public struct AppConfig: Codable, Equatable, Sendable {
      public var anthropicAPIKey: String?
      public var intentModel: String = "claude-opus-5-5"
      public var asrModelVersion: String = "v2"
      public var silenceMs: Int = 350
      public var gridColumns: Int = 10; public var gridRows: Int = 8
      public var moveStepPx: Int = 50; public var scrollStepLines: Int = 5
      public init()
      /// Decodes `data` (missing keys → defaults, unknown keys ignored); then `environment["ANTHROPIC_API_KEY"]` overrides the key.
      public static func load(from data: Data?, environment: [String: String]) throws -> AppConfig
      public var grammarConfig: GrammarConfig { get }
  }
  public struct IntentContext: Sendable {
      public var frontmostApp: String; public var mode: Mode
      public var labeledElements: [(number: Int, title: String)]   // ≤ 60, already truncated by caller; tuples, so no Equatable
      public init(frontmostApp: String, mode: Mode, labeledElements: [(number: Int, title: String)])
  }
  public enum IntentSchema {
      public static let actionsJSONSchema: [String: Any]      // §10 of the spec
      public static let systemPrompt: String                  // fixed; §10 rules
  }
  public struct ClaudeRequestBuilder: Sendable {
      public init(model: String)
      public func body(transcript: String, context: IntentContext) throws -> Data   // JSON per Global Constraints
      public static let headers: (apiKey: String) -> [String: String]
  }
  public enum IntentDecodeError: Error, Equatable { case refusal, noTextBlock, malformed(String) }
  public enum IntentDecoder {
      /// Full Messages API response body → actions. Unknown `kind` or missing required fields → that action is dropped.
      public static func actions(fromResponse data: Data) throws -> [Action]
  }
  ```

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import NoHandsCore

@Test func configDefaultsAndEnvOverride() throws {
    let c = try AppConfig.load(from: nil, environment: [:])
    #expect(c.intentModel == "claude-opus-5-5"); #expect(c.silenceMs == 350); #expect(c.anthropicAPIKey == nil)
    let json = #"{"anthropicAPIKey":"file-key","silenceMs":500,"unknownKey":1}"#.data(using: .utf8)
    let d = try AppConfig.load(from: json, environment: ["ANTHROPIC_API_KEY": "env-key"])
    #expect(d.anthropicAPIKey == "env-key"); #expect(d.silenceMs == 500)
}

@Test func requestBodyMatchesConstraints() throws {
    let ctx = IntentContext(frontmostApp: "Safari", mode: .command, labeledElements: [(3, "Back"), (7, "Reload")])
    let data = try ClaudeRequestBuilder(model: "claude-opus-5-5").body(transcript: "go back", context: ctx)
    let obj = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(obj["model"] as? String == "claude-opus-5-5")
    #expect(obj["max_tokens"] as? Int == 1024)
    #expect(obj["fallbacks"] as? String == "default")
    let oc = try #require(obj["output_config"] as? [String: Any])
    #expect(oc["effort"] as? String == "low")
    let fmt = try #require(oc["format"] as? [String: Any])
    #expect(fmt["type"] as? String == "json_schema")
    #expect(fmt["schema"] != nil)
    #expect(obj["temperature"] == nil); #expect(obj["thinking"] == nil); #expect(obj["tool_choice"] == nil)
    let msgs = try #require(obj["messages"] as? [[String: Any]])
    #expect(msgs.count == 1)
    let text = try #require(msgs[0]["content"] as? String)
    #expect(text.contains("Safari")); #expect(text.contains("7: Reload")); #expect(text.hasSuffix("go back"))
    let h = ClaudeRequestBuilder.headers("k")
    #expect(h["x-api-key"] == "k"); #expect(h["anthropic-version"] == "2026-10-21"); #expect(h["anthropic-beta"] == "server-side-fallback-2026-07-01")
}

@Test func schemaHasNoRecursionAndClosesObjects() throws {
    let data = try JSONSerialization.data(withJSONObject: IntentSchema.actionsJSONSchema)
    let s = String(decoding: data, as: UTF8.self)
    #expect(!s.contains("$ref"))
    #expect(s.contains("\"additionalProperties\":false"))
    #expect(!s.contains("minimum")); #expect(!s.contains("maxLength"))
}

func response(_ json: String, stop: String = "end_turn") -> Data {
    #"{"id":"msg_1","type":"message","role":"assistant","model":"claude-opus-5-5","stop_reason":"\#(stop)","content":[{"type":"text","text":\#(json)}],"usage":{"input_tokens":1,"output_tokens":1}}"#.data(using: .utf8)!
}

@Test func decodesEveryKind() throws {
    let body = #""{\"actions\":[{\"kind\":\"press_key\",\"key\":\"f\",\"modifiers\":[\"control\",\"command\"]},{\"kind\":\"click\",\"target_kind\":\"label\",\"target_number\":7,\"button\":\"left\",\"count\":1},{\"kind\":\"click\",\"target_kind\":\"element\",\"target_name\":\"Reload\"},{\"kind\":\"move_cursor\",\"target_kind\":\"relative\",\"dx\":10,\"dy\":-5},{\"kind\":\"scroll\",\"direction\":\"down\",\"amount\":3},{\"kind\":\"type_text\",\"text\":\"hi\"},{\"kind\":\"set_mode\",\"mode\":\"dictation\"},{\"kind\":\"open_app\",\"app_name\":\"Notes\"},{\"kind\":\"zoom_grid\",\"target_number\":12},{\"kind\":\"ignore\"}]}""#
    let actions = try IntentDecoder.actions(fromResponse: response(body))
    #expect(actions == [
        .pressKey(KeyChord(.f, [.control, .command])),
        .click(.numbered(7), button: .left, count: 1),
        .click(.element(named: "Reload"), button: .left, count: 1),
        .moveCursor(.relative(dx: 10, dy: -5)),
        .scroll(.down, amount: 3),
        .typeText("hi"),
        .setMode(.dictation),
        .openApp("Notes"),
        .zoomGrid(12),
        .ignore,
    ])
}

@Test func unknownKindYieldsNoActions() throws {
    let body = #""{\"actions\":[{\"kind\":\"launch_missiles\"},{\"kind\":\"press_key\"},{\"kind\":\"click\",\"target_kind\":\"label\"}]}""#
    #expect(try IntentDecoder.actions(fromResponse: response(body)) == [])
    #expect(try IntentDecoder.actions(fromResponse: response(#""{\"actions\":[]}""#)) == [])
}

@Test func refusalYieldsNoActions() {
    #expect(throws: IntentDecodeError.refusal) {
        try IntentDecoder.actions(fromResponse: response(#""{\"actions\":[]}""#, stop: "refusal"))
    }
    #expect(throws: IntentDecodeError.self) {
        try IntentDecoder.actions(fromResponse: "not json".data(using: .utf8)!)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter "IntentTests|AppConfigTests"`
Expected: compile errors for the undefined types.

- [ ] **Step 3: Implement `AppConfig`, `IntentSchema`, `ClaudeRequestBuilder`, `IntentDecoder`**

`IntentSchema.systemPrompt` describes each `kind` and its fields in one line each, then the three rules from spec §10. The user message is: `App: <frontmostApp>\nMode: <mode>\nVisible elements:\n<n>: <title>\n…\n\nRequest: <transcript>`. The decoder reads `stop_reason` first, then the first `content` block with `type == "text"`, parses its `text` as JSON, and maps each object through a `switch kind`; `click` defaults `button` to `left` and `count` to `1`; `press_mouse`/`release_mouse` default to `left`; `show_grid`/`show_labels`/`hide_overlay` take no fields.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter "IntentTests|AppConfigTests"`
Expected: 7 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/NoHandsCore/IntentSchema.swift Sources/NoHandsCore/IntentDecoder.swift Sources/NoHandsCore/AppConfig.swift Tests/NoHandsCoreTests
git commit -m "feat: Claude request builder, structured-output schema, and action decoder"
```

---

### Task 8: Text chunking and CGEvent input synthesis

**Files:**
- Create: `Sources/NoHandsCore/TextChunker.swift`, `Tests/NoHandsCoreTests/TextChunkerTests.swift`, `Sources/NoHandsMac/InputSynthesizer.swift`
- Modify: `Sources/nohands-cli/main.swift` (add `type`, `key`, `click-at`, `move` subcommands)
- Delete: `Sources/NoHandsMac/Placeholder.swift`

**Interfaces:**
- Produces:
  ```swift
  public enum TextChunker {
      /// Splits on Character boundaries so each chunk has ≤ maxUTF16 code units (default 20). Never returns empty chunks.
      public static func chunks(_ text: String, maxUTF16: Int = 20) -> [String]
  }
  public protocol InputSynthesizing: Sendable {
      func type(_ text: String) throws
      func press(_ chord: KeyChord) throws
      func moveMouse(to point: CGPoint) throws
      func click(at point: CGPoint, button: MouseButton, count: Int) throws
      func mouseDown(_ button: MouseButton, at point: CGPoint) throws
      func mouseUp(_ button: MouseButton, at point: CGPoint) throws
      func scroll(_ direction: Direction, lines: Int) throws
      func currentMouseLocation() -> CGPoint                    // CG coordinates
  }
  public struct CGEventInputSynthesizer: InputSynthesizing { public init() }
  ```

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import NoHandsCore

@Test func chunksByUTF16Budget() {
    let text = String(repeating: "a", count: 45)
    let c = TextChunker.chunks(text)
    #expect(c.map(\.utf16.count) == [20, 20, 5])
    #expect(c.joined() == text)
    #expect(TextChunker.chunks("") == [])
}

@Test func neverSplitsGraphemeClusters() {
    let flag = "🇺🇸"              // 4 UTF-16 units
    let family = "👨‍👩‍👧‍👦"          // 11 UTF-16 units
    let text = String(repeating: "x", count: 18) + flag + family + "é"
    let c = TextChunker.chunks(text)
    #expect(c.joined() == text)
    for chunk in c { #expect(chunk.utf16.count <= 20) }
    #expect(c[0] == String(repeating: "x", count: 18))
    #expect(c[1].hasPrefix(flag))
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter TextChunkerTests`
Expected: compile error, `TextChunker` not defined.

- [ ] **Step 3: Implement `TextChunker`**

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter TextChunkerTests`
Expected: 2 tests pass.

- [ ] **Step 5: Implement `CGEventInputSynthesizer` in `NoHandsMac`**

- `type`: for each chunk, one `CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)` + `keyboardSetUnicodeString`, posted to `.cghidEventTap`, followed by the matching key-up; 1 ms sleep between chunks.
- `press`: key-down then key-up with `event.flags` built from the modifiers (`.maskCommand`, `.maskShift`, `.maskAlternate`, `.maskControl`, `.maskSecondaryFn`).
- `click`: `moveMouse(to:)` then for `i in 1...count` a down/up pair with `mouseEventClickState = i`; event types per button (`.leftMouseDown/Up`, `.rightMouseDown/Up`, `.otherMouseDown/Up` with `mouseButton: .center`).
- `scroll`: `CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: ±lines, wheel2: ±lines, wheel3: 0)` — wheel1 is vertical (positive = up), wheel2 horizontal (positive = left).
- `currentMouseLocation`: `CGEvent(source: nil)!.location`.

- [ ] **Step 6: Add CLI subcommands and verify manually**

`nohands-cli type "<text>"` waits 2 s then types; `nohands-cli key "command shift s"`; `nohands-cli click-at <x> <y>`; `nohands-cli move <x> <y>`. Parse the key spec with `CommandGrammar().parse("press " + spec)`.

Run (with TextEdit focused within the 2 s delay, and Terminal granted Accessibility):
```bash
swift run nohands-cli type "Hello, world 🇺🇸 👨‍👩‍👧‍👦 é"
swift run nohands-cli key "command a"
swift run nohands-cli click-at 400 300
```
Expected: the exact string appears in TextEdit including both emoji; ⌘A selects it; the pointer jumps to (400,300) and clicks.

- [ ] **Step 7: Commit**

```bash
git add Sources Tests
git commit -m "feat: CGEvent input synthesis with grapheme-safe text chunking"
```

---

### Task 9: Microphone, VAD, utterance assembly, Parakeet transcription

**Files:**
- Create: `Sources/NoHandsCore/UtteranceAssembler.swift`, `Sources/NoHandsCore/LatencyTrace.swift`, `Tests/NoHandsCoreTests/UtteranceAssemblerTests.swift`, `Sources/NoHandsMac/MicrophoneCapture.swift`, `Sources/NoHandsMac/VoiceActivity.swift`, `Sources/NoHandsMac/ParakeetTranscriber.swift`
- Modify: `Sources/nohands-cli/main.swift` (add `listen`, `transcribe <wav>`)

**Interfaces:**
- Produces:
  ```swift
  public enum VadEvent: Equatable, Sendable { case speechStart, speechEnd, none }
  public struct UtteranceAssembler: Sendable {
      /// prePadMs: audio kept before speechStart; minSpeechMs: shorter utterances are dropped; maxSpeechMs: forced cut.
      public init(sampleRate: Int = 16_000, prePadMs: Int = 200, minSpeechMs: Int = 250, maxSpeechMs: Int = 15_000)
      /// Feed one chunk and its VAD event; returns a completed utterance (speech + pre-pad) when one ends.
      public mutating func push(_ samples: [Float], event: VadEvent) -> [Float]?
  }
  public struct LatencyTrace: Sendable {
      public var speechEnd: ContinuousClock.Instant?; public var asrDone: ContinuousClock.Instant?; public var actionsDone: ContinuousClock.Instant?
      public init()
      public var summary: String   // "asr=187ms total=412ms"
  }
  // NoHandsMac
  public final class MicrophoneCapture: @unchecked Sendable {
      public init() throws
      /// 16 kHz mono Float32 chunks of exactly 4096 samples (VadManager.chunkSize), delivered on a background queue.
      public func start(_ onChunk: @escaping @Sendable ([Float]) -> Void) throws
      public func stop()
  }
  public actor VoiceActivity {
      public init() async throws                              // FluidAudio VadManager()
      public func process(_ chunk: [Float]) async throws -> VadEvent   // processStreamingChunk, keeps VadStreamState
      public func reset() async
  }
  public protocol Transcribing: Sendable { func transcribe(_ samples: [Float]) async throws -> String }
  public actor ParakeetTranscriber: Transcribing {
      public init(version: String) async throws               // "v2" | "v3" → AsrModels.downloadAndLoad(version:), AsrManager(config: .default), loadModels
      public func transcribe(_ samples: [Float]) async throws -> String   // AsrManager.transcribe(_:source: .microphone).text, trimmed
  }
  ```

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import NoHandsCore

let chunk = [Float](repeating: 0.1, count: 4096)      // 256 ms at 16 kHz
let silence = [Float](repeating: 0, count: 4096)

@Test func assemblesSpeechWithPrePad() {
    var a = UtteranceAssembler(prePadMs: 256)
    #expect(a.push(silence, event: .none) == nil)
    #expect(a.push(chunk, event: .speechStart) == nil)
    #expect(a.push(chunk, event: .none) == nil)
    let u = a.push(chunk, event: .speechEnd)
    #expect(u?.count == 4 * 4096)          // 1 pre-pad chunk + 3 speech chunks
    #expect(u?.first == 0)                 // pre-pad came from the silence chunk
}

@Test func dropsTooShortUtterances() {
    var a = UtteranceAssembler(prePadMs: 0, minSpeechMs: 600)
    _ = a.push(chunk, event: .speechStart)
    #expect(a.push(chunk, event: .speechEnd) == nil)    // 512 ms < 600 ms
}

@Test func forcesCutAtMaxSpeech() {
    var a = UtteranceAssembler(prePadMs: 0, maxSpeechMs: 1000)
    _ = a.push(chunk, event: .speechStart)
    _ = a.push(chunk, event: .none)
    _ = a.push(chunk, event: .none)
    #expect(a.push(chunk, event: .none)?.count == 4 * 4096)   // 1024 ms ≥ 1000 ms
}

@Test func latencySummary() {
    var t = LatencyTrace()
    let now = ContinuousClock.now
    t.speechEnd = now; t.asrDone = now.advanced(by: .milliseconds(187)); t.actionsDone = now.advanced(by: .milliseconds(412))
    #expect(t.summary == "asr=187ms total=412ms")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter UtteranceAssemblerTests`
Expected: compile errors.

- [ ] **Step 3: Implement `UtteranceAssembler` and `LatencyTrace`**

Keep a ring of recent silence chunks sized to `prePadMs`; on `speechStart` move them into the current buffer.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter UtteranceAssemblerTests`
Expected: 4 tests pass.

- [ ] **Step 5: Implement `MicrophoneCapture`, `VoiceActivity`, `ParakeetTranscriber`**

- `MicrophoneCapture`: `AVAudioEngine`, tap on `inputNode` at its native format, `AVAudioConverter` to `AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)`, accumulate into exactly 4096-sample chunks.
- `VoiceActivity`: `VadManager()`; keep `VadStreamState` from `makeStreamState()`; call `processStreamingChunk(chunk, state: state, config: .default, returnSeconds: false, timeResolution: 2)`; map `result.event?.kind` `.speechStart`/`.speechEnd` to `VadEvent`. The `config:` argument is a `VadSegmentationConfig`; build it with `minSilenceDuration = Double(silenceMs) / 1000` so the end-of-speech delay follows the config file.
- `ParakeetTranscriber`: `AsrModels.downloadAndLoad(version: version == "v3" ? .v3 : .v2)`, `AsrManager(config: .default)`, `loadModels(models)`, `transcribe(samples, source: .microphone)`; check the `AudioSource` enum's actual case names in FluidAudio 0.18.x and use the microphone one.

- [ ] **Step 6: Add CLI subcommands and verify manually**

`nohands-cli transcribe <wav>` prints the text and ASR milliseconds. `nohands-cli listen` runs mic → VAD → assembler → ASR and prints one line per utterance: `[asr=187ms total=412ms] click forty two`.

Run:
```bash
say -o /tmp/t.aiff "click forty two" && afconvert -f WAVE -d LEI16@16000 -c 1 /tmp/t.aiff /tmp/t.wav
swift run nohands-cli transcribe /tmp/t.wav
swift run nohands-cli listen       # speak "open safari", "hello world period", then Ctrl-C
```
Expected: first command prints `click forty two` (or `click 42`) with asr under 400 ms after warm-up; `listen` prints each phrase within about half a second of you stopping, with `asr` ≤ 250 ms for short phrases on an M1 Pro. First run downloads models to FluidAudio's cache (hundreds of MB).

- [ ] **Step 7: Commit**

```bash
git add Sources Tests
git commit -m "feat: microphone capture, Silero VAD segmentation, Parakeet transcription"
```

---

### Task 10: Permissions and accessibility element queries

**Files:**
- Create: `Sources/NoHandsMac/Permissions.swift`, `Sources/NoHandsMac/AXQuery.swift`
- Modify: `Sources/nohands-cli/main.swift` (add `elements`, `click "<name>"`)

**Interfaces:**
- Produces:
  ```swift
  public enum Permissions {
      public static func accessibilityGranted(prompt: Bool) -> Bool        // AXIsProcessTrustedWithOptions
      public static func requestMicrophone() async -> Bool                 // AVCaptureDevice.requestAccess(for: .audio)
      public static func openAccessibilitySettings()                       // x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility
  }
  public final class AXQuery: @unchecked Sendable {
      public init()
      public var frontmostAppName: String { get }
      /// Actionable elements of the frontmost app (roles per spec §8), depth ≤ 12, time budget 150 ms, frames in CG coordinates.
      /// Returned ids are valid until the next call to this method.
      public func actionableElements() -> [UIElementInfo]
      public func element(for id: Int) -> AXUIElement?
      public func activate(appNamed name: String) -> Bool                  // NSWorkspace.openApplication by localizedName or bundle name, case-insensitive
  }
  ```

- [ ] **Step 1: Implement `Permissions` and `AXQuery`**

Walk from `AXUIElementCreateApplication(pid)` of `NSWorkspace.shared.frontmostApplication`, reading `kAXChildrenAttribute`, `kAXRoleAttribute`, `kAXPositionAttribute`, `kAXSizeAttribute`, `kAXTitleAttribute`, `kAXDescriptionAttribute`, `kAXValueAttribute` (string values only). Skip elements with zero size or entirely off every screen. Title fallback order: title, description, value. Stop walking when the 150 ms `ContinuousClock` budget is spent; return what was collected.

- [ ] **Step 2: Add CLI subcommands and verify manually**

`nohands-cli elements` prints, after a 3 s delay, `n  role  (x,y wxh)  title` for the frontmost app's elements using `LabelAssigner.assign`. `nohands-cli click "<name>"` finds the element with `LabelAssigner.find` and clicks its center with `CGEventInputSynthesizer`.

Run with Safari in front during the delay:
```bash
swift run nohands-cli elements
swift run nohands-cli click "Reload this page"
```
Expected: dozens of elements including toolbar buttons and page links, numbered from top-left; the second command reloads the page. If `elements` prints nothing, Accessibility is not granted to the terminal; grant it and rerun.

- [ ] **Step 3: Commit**

```bash
git add Sources
git commit -m "feat: accessibility permissions and actionable element queries"
```

---

### Task 11: Overlay windows (grid, labels, transcript HUD)

**Files:**
- Create: `Sources/NoHandsCore/OverlayState.swift`, `Sources/NoHandsMac/OverlayController.swift`
- Modify: `Sources/nohands-cli/main.swift` (add `grid`, `labels`)

**Interfaces:**
- Consumes: `GridModel`, `UIElementInfo`, `CoordinateMapper` (Task 6).
- Produces:
  ```swift
  // NoHandsCore/OverlayState.swift — in Core so Task 12's TargetResolver can read it without AppKit
  public enum OverlayState: Equatable, Sendable { case none, grid(GridModel), labels([Int: UIElementInfo]) }
  // NoHandsMac/OverlayController.swift
  @MainActor public final class OverlayController {
      public init()
      public private(set) var state: OverlayState
      public func showGrid(_ grid: GridModel)
      public func showLabels(_ labels: [Int: UIElementInfo])
      public func hide()
      public func showHUD(_ text: String, duration: Duration = .seconds(1.5))   // bottom-center of the pointer's screen
      public static func screenBoundsCG(containing point: CGPoint) -> CGRect       // NSScreen frame flipped to CG
  }
  ```

- [ ] **Step 1: Implement `OverlayController`**

One borderless `NSPanel` per role (`.nonactivatingPanel`, `level = .screenSaver`, `ignoresMouseEvents = true`, `backgroundColor = .clear`, `isOpaque = false`, `collectionBehavior = [.canJoinAllSpaces, .stationary]`). Grid view draws cell borders at 25 % white and the number centered in each cell (monospaced 14 pt, white with black shadow). Labels view draws a rounded badge at each element's top-left corner. HUD is a dark rounded pill with 18 pt white text that auto-hides after `duration`. All frames go through `CoordinateMapper.toAppKit`.

- [ ] **Step 2: Add CLI subcommands and verify manually**

`nohands-cli grid` shows the 10×8 grid for 4 s, then zooms into cell 35 for 4 s, then shows the HUD "done" and exits. `nohands-cli labels` shows numbered badges for the frontmost app for 5 s.

Run: `swift run nohands-cli grid` and `swift run nohands-cli labels` (with Safari in front).
Expected: cell 1 is top-left, 10 is top-right, 80 bottom-right, numbers legible; the zoomed grid sits exactly inside where cell 35 was; badges sit on top-left corners of buttons and links; nothing steals focus from Safari.

- [ ] **Step 3: Commit**

```bash
git add Sources
git commit -m "feat: grid, label, and HUD overlay windows"
```

---

### Task 12: Action executor

**Files:**
- Create: `Sources/NoHandsCore/TargetResolver.swift`, `Tests/NoHandsCoreTests/TargetResolverTests.swift`, `Sources/NoHandsMac/ActionExecutor.swift`
- Modify: `Sources/nohands-cli/main.swift` (add `run "<phrase>"`)

**Interfaces:**
- Consumes: `InputSynthesizing` (Task 8), `AXQuery` (Task 10), `OverlayController`/`OverlayState` (Task 11), `GridModel`, `LabelAssigner`.
- Produces:
  ```swift
  // NoHandsCore
  public enum TargetResolution: Equatable, Sendable { case point(CGPoint), failure(String) }
  public enum TargetResolver {
      // Two names, not an overload: `.numbered(1)` would be ambiguous between ClickTarget and MoveTarget.
      public static func resolveClick(_ t: ClickTarget, overlay: OverlayState, cursor: CGPoint, elements: [UIElementInfo]) -> TargetResolution
      public static func resolveMove(_ t: MoveTarget, overlay: OverlayState, cursor: CGPoint, elements: [UIElementInfo]) -> TargetResolution
  }
  // NoHandsMac
  @MainActor public final class ActionExecutor {
      public init(input: any InputSynthesizing, ax: AXQuery, overlay: OverlayController, config: AppConfig)
      public var onModeChange: ((Mode) -> Void)?
      /// Executes in order; stops at the first failure and shows it in the HUD. Returns the failure message if any.
      public func execute(_ actions: [Action]) -> String?
  }
  ```

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import CoreGraphics
@testable import NoHandsCore

let grid = GridModel(bounds: CGRect(x: 0, y: 0, width: 1000, height: 800))
let save = UIElementInfo(id: 1, frame: CGRect(x: 100, y: 100, width: 80, height: 30), title: "Save", role: "AXButton")

@Test func numberedResolvesAgainstVisibleOverlay() {
    #expect(TargetResolver.resolveClick(.numbered(1), overlay: .grid(grid), cursor: .zero, elements: []) == .point(CGPoint(x: 50, y: 50)))
    #expect(TargetResolver.resolveClick(.numbered(1), overlay: .labels([1: save]), cursor: .zero, elements: []) == .point(CGPoint(x: 140, y: 115)))
}

@Test func numberedTargetOutOfRangeIsReported() {
    #expect(TargetResolver.resolveClick(.numbered(150), overlay: .grid(grid), cursor: .zero, elements: []) == .failure("no cell 150"))
    #expect(TargetResolver.resolveClick(.numbered(7), overlay: .none, cursor: .zero, elements: []) == .failure("no grid or labels shown"))
    #expect(TargetResolver.resolveClick(.numbered(2), overlay: .labels([1: save]), cursor: .zero, elements: []) == .failure("no label 2"))
}

@Test func elementAndCursorTargets() {
    #expect(TargetResolver.resolveClick(.element(named: "save"), overlay: .none, cursor: .zero, elements: [save]) == .point(CGPoint(x: 140, y: 115)))
    #expect(TargetResolver.resolveClick(.element(named: "quit"), overlay: .none, cursor: .zero, elements: [save]) == .failure("no element named 'quit'"))
    #expect(TargetResolver.resolveClick(.cursor, overlay: .none, cursor: CGPoint(x: 5, y: 6), elements: []) == .point(CGPoint(x: 5, y: 6)))
    #expect(TargetResolver.resolveMove(.relative(dx: -10, dy: 20), overlay: .none, cursor: CGPoint(x: 100, y: 100), elements: []) == .point(CGPoint(x: 90, y: 120)))
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter TargetResolverTests`
Expected: compile error, `TargetResolver` not defined.

- [ ] **Step 3: Implement `TargetResolver` (Core) and `ActionExecutor` (Mac)**

Executor behavior per action: `typeText` → `input.type`; `pressKey` → `input.press`; `click` → resolve, `input.click`, then `overlay.hide()` if a grid or labels were used; `pressMouse`/`releaseMouse` at current cursor; `moveCursor` → resolve, `input.moveMouse`; `scroll` → `input.scroll`; `showGrid` → `GridModel(bounds: OverlayController.screenBoundsCG(containing: cursor), columns: config.gridColumns, rows: config.gridRows)`; `zoomGrid(n)` → requires `.grid` state, else failure "no grid shown"; `showLabels` → `LabelAssigner.assign(ax.actionableElements())`; `hideOverlay`; `setMode` → `onModeChange?`; `openApp` → `ax.activate(appNamed:)` else failure "no app named …"; `ignore` → nothing. Element lookups for `.element(named:)` call `ax.actionableElements()` fresh.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: all tests pass.

- [ ] **Step 5: Add CLI `run "<phrase>"` and verify manually**

`nohands-cli run "<phrase>"` parses with `CommandGrammar`, waits 2 s, executes with a real `ActionExecutor`, prints the actions and any failure.

Run (TextEdit in front): `swift run nohands-cli run "type hello comma world"`; `swift run nohands-cli run "select all"`; `swift run nohands-cli run "grid"` then within 4 s `swift run nohands-cli run "click 35"`.
Expected: text typed; selected; grid shown; click lands in cell 35 and the grid disappears.

- [ ] **Step 6: Commit**

```bash
git add Sources Tests
git commit -m "feat: action executor with late target resolution"
```

---

### Task 13: Claude intent resolver over HTTPS

**Files:**
- Create: `Sources/NoHandsMac/ClaudeIntentResolver.swift`
- Modify: `Sources/nohands-cli/main.swift` (add `resolve "<text>"`)

**Interfaces:**
- Consumes: `ClaudeRequestBuilder`, `IntentDecoder`, `IntentContext`, `AppConfig` (Task 7).
- Produces:
  ```swift
  public enum IntentError: Error { case noAPIKey, network(Error), http(Int, String), decode(IntentDecodeError) }
  public protocol IntentResolving: Sendable { func resolve(_ transcript: String, context: IntentContext) async throws -> [Action] }
  public actor ClaudeIntentResolver: IntentResolving {
      public init(config: AppConfig, session: URLSession = .shared)    // request timeout 4 s
      public func resolve(_ transcript: String, context: IntentContext) async throws -> [Action]
  }
  ```

- [ ] **Step 1: Implement `ClaudeIntentResolver`**

Throw `.noAPIKey` if `config.anthropicAPIKey` is nil. Build `URLRequest` with `ClaudeRequestBuilder.headers` plus `Content-Type: application/json`, `timeoutInterval = 4`. Non-2xx → `.http(status, bodyPrefix)`. Decode with `IntentDecoder.actions(fromResponse:)`, wrapping `IntentDecodeError` in `.decode`.

- [ ] **Step 2: Add CLI subcommand and verify manually**

`nohands-cli resolve "<text>"` prints the decoded actions and elapsed milliseconds, using the real frontmost app and its labeled elements as context.

Run with `ANTHROPIC_API_KEY` set and Safari in front:
```bash
swift run nohands-cli resolve "make this window full screen"
swift run nohands-cli resolve "go back a page"
ANTHROPIC_API_KEY= swift run nohands-cli resolve "anything"
```
Expected: first prints `[pressKey(KeyChord(key: f, modifiers: [control, command]))]`; second prints a `pressKey` ⌘[ or a `click` on the labeled Back button; third prints `error: noAPIKey` when the config file also has no key.

- [ ] **Step 3: Commit**

```bash
git add Sources
git commit -m "feat: Claude intent resolver over the Messages API"
```

---

### Task 14: Voice pipeline, menu-bar app, bundle script, README

**Files:**
- Create: `Sources/NoHandsMac/VoicePipeline.swift`, `Sources/NoHands/AppDelegate.swift`, `Resources/Info.plist`, `Scripts/bundle.sh`
- Modify: `Sources/NoHands/main.swift`, `README.md`

**Interfaces:**
- Consumes: everything above.
- Produces:
  ```swift
  @MainActor public final class VoicePipeline {
      public init(config: AppConfig, transcriber: any Transcribing, resolver: (any IntentResolving)?, executor: ActionExecutor, overlay: OverlayController)
      public var onStatus: ((Mode, String) -> Void)?       // mode + last transcript, for the menu
      public func start() async throws                     // mic → VAD → assembler → ASR → ModeMachine → executor / resolver
      public func stop()
  }
  ```

- [ ] **Step 1: Implement `VoicePipeline`**

Audio chunks arrive on a background queue; hop to the actor/main actor for VAD → assembler → ASR; on each transcript, `overlay.showHUD(transcript)`, `modeMachine.route`, then `.execute` → `executor.execute`, `.resolveWithLLM` → `resolver?.resolve` (if nil, HUD "LLM disabled: no API key") → `executor.execute`, `.ignore` → nothing. Record a `LatencyTrace` per utterance and `print` its summary plus the transcript. Mode changes from the executor's `onModeChange` feed back into `modeMachine`.

- [ ] **Step 2: Implement the menu-bar app**

`main.swift`: `NSApplication.shared`, `setActivationPolicy(.accessory)`, set `AppDelegate`, `run()`. `AppDelegate.applicationDidFinishLaunching`: load `AppConfig` from `~/.config/nohands/config.json` + `ProcessInfo.processInfo.environment`; request mic; check Accessibility with prompt; create `NSStatusItem` with `mic` SF Symbol and title `CMD`/`DICT`/`ZZZ`; menu items: last transcript (disabled), `Pause/Resume Listening`, `Open Accessibility Settings` (shown with a red dot while not granted), `Quit`. Start the pipeline once both permissions are granted; poll Accessibility every 2 s until granted.

- [ ] **Step 3: Write `Resources/Info.plist` and `Scripts/bundle.sh`**

Info.plist keys: `CFBundleIdentifier dev.nohands.app`, `CFBundleName NoHands`, `CFBundleExecutable NoHands`, `CFBundlePackageType APPL`, `CFBundleShortVersionString 0.1.0`, `LSUIElement true`, `LSMinimumSystemVersion 14.0`, `NSMicrophoneUsageDescription "NoHands listens for voice commands and dictation."`. `bundle.sh`: `swift build -c release`, create `build/NoHands.app/Contents/{MacOS,Resources}`, copy the binary and plist, copy any `*.bundle` resource bundles from `.build/release` into `Contents/Resources`, `codesign --force --sign "${CODESIGN_IDENTITY:--}" --deep build/NoHands.app`, print the path.

- [ ] **Step 4: Update `README.md`**

Sections: what it does, requirements, build (`Scripts/bundle.sh`), first-run permissions and the ad-hoc re-grant caveat, config file, the command phrase table (copy spec §6 and §7), CLI subcommands, latency notes.

- [ ] **Step 5: Verify end to end**

Run: `Scripts/bundle.sh && open build/NoHands.app`, then walk the acceptance list in spec §14 steps 1–8.
Expected: every step behaves as written; the console (`log stream --predicate 'process == "NoHands"'` or running the binary directly) shows one latency line per utterance with grammar-path totals ≤ 650 ms.

- [ ] **Step 6: Commit**

```bash
git add Sources Resources Scripts README.md
git commit -m "feat: menu-bar app wiring the voice pipeline, bundle script, README"
```
