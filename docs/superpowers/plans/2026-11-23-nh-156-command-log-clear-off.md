# NH-156 Command log clear and off switch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. Steps use checkbox syntax.

**Goal:** Saturating token sums, a `commandLog` config key, and Clear Log / Keep Command Log menu items.

**Architecture:** Core gets a saturating add and the config key plus its JSON patch helper; `CommandLogStore` gets `isRecording` and `clear()` on its ordered write chain; `AppDelegate` adds two items to the Recent commands submenu.

**Tech Stack:** Swift 6 strict concurrency, SwiftPM, XCTest or swift-testing as the existing tests use.

**Spec:** `docs/superpowers/specs/2026-11-23-nh-156-command-log-clear-off-design.md`

## Global Constraints

- No `@unchecked Sendable`, no `@preconcurrency`; `NoHandsCore` has no AppKit.
- `swift test` runs with no permissions and no Ollama.
- Tests: one table-driven test per rule (`AGENTS.md` § Testing); test lines must not exceed feature lines. No tests for the store or menu.

## Review Focus

- `Int.max` plus a positive count in every sum (`Usage.sum`, `ClaudeUsageTotal.adding`, `menuLine`): clamp, no trap.
- `commandLog` as `"no"`, `1`, `null` or a string: stays `true`, rest of config still loads.
- Clear while a write is queued: file must not reappear with old entries.

---

### Task 1: Saturating sums (core)

**Files:** Modify `Sources/NoHandsCore/CommandLog.swift` (`Usage.sum`), `Sources/NoHandsCore/ClaudeUsage.swift` (`ClaudeUsageTotal.adding`, `menuLine`); Test `Tests/NoHandsCoreTests/CommandLogTests.swift` (or the existing ClaudeUsage test file).

**Interfaces:** Produces `extension Int { func saturatingAdd(_ other: Int) -> Int }` (internal, in `ClaudeUsage.swift`): `addingReportingOverflow`, on overflow `Int.max` if `other > 0` else `Int.min`.

- [ ] Write one table-driven test: `Usage.sum` of two `ClaudeUsage` with counts `Int.max` and `1` gives `Int.max` for all three fields; `ClaudeUsageTotal().adding(...)` twice with `Int.max` input gives `input == Int.max`, and `menuLine` with `input == Int.max`, `cacheWrite == 1` does not trap; small counts still add exactly.
- [ ] Run `swift test --filter <test name>`: fails (traps/crashes).
- [ ] Implement `saturatingAdd` and use it in `Usage.sum` (replace the `reduce` `+`), `ClaudeUsageTotal.adding` (all four counts and `calls`), and `menuLine`'s `input + cacheWrite`.
- [ ] Run the test: passes. Commit `fix(core): saturate token sums (NH-156)`.

### Task 2: `commandLog` config key (core)

**Files:** Modify `Sources/NoHandsCore/AppConfig.swift` (property `commandLog: Bool = true`, CodingKeys case, lenient decode like `routeMemory`), `Sources/NoHandsCore/ClaudeKeyEntry.swift` (`ConfigPatch.merged` value type `Any`/`Bool` overload; existing String callers unchanged), `Sources/NoHandsCore/SpokenFeedback.swift` or a new small `CommandLogMenu.swift`; Test `Tests/NoHandsCoreTests/AppConfigTests.swift`.

**Interfaces:** Produces `public enum CommandLogMenu { public static func merged(existing: Data?, on: Bool) throws -> Data }` writing `commandLog` as a JSON bool via `ConfigPatch`.

- [ ] Write one table test over config JSON: missing → true, `false` → false, `true` → true, `"no"`, `1`, `null` → true, and another key (`silenceMs`) still parsed. Plus one assertion that `CommandLogMenu.merged` on `{"silenceMs":5}` keeps `silenceMs` and decodes `commandLog == false` for `on: false`.
- [ ] Run it: fails (no member).
- [ ] Implement; `commandLog` decode is `(try? c.decodeIfPresent(Bool.self, forKey: .commandLog)) ?? d.commandLog`.
- [ ] Run: passes. Commit `feat(core): commandLog config key (NH-156)`.

### Task 3: Store and menu (mac, no tests)

**Files:** Modify `Sources/NoHandsMac/CommandLogStore.swift`, `Sources/NoHandsMac/ConfigFile.swift`, `Sources/NoHands/AppDelegate.swift`.

**Interfaces:** Produces `CommandLogStore.isRecording: Bool` (default true); `CommandLogStore.clear()`; `ConfigFile.saveCommandLog(_ on: Bool, at url: URL) throws` (like `saveSpeakFeedback`, `keepMode: true`, using `CommandLogMenu.merged`).

- [ ] `append`: `guard isRecording else { return }` first.
- [ ] `clear()`: `log = CommandLog()`, `onChange?()`, then chain on `lastWrite` a detached task that awaits previous and removes the file (`FileManager.removeItem`; ignore not-found, otherwise `PipelineLog.warning("command log: could not delete the log file", detail: "\(error)")`).
- [ ] AppDelegate: set `commandLog.isRecording = config.commandLog` after config loads (and wherever config reloads). In `rebuildRecentMenu`, after entries (or the empty line, which reads "Command log is off" when `!config.commandLog`), add a separator, **Clear Log** (`#selector(clearLog)`, disabled when entries empty), and **Keep Command Log** (`#selector(toggleCommandLog)`, state on when `config.commandLog`). `clearLog` calls `commandLog.clear()`. `toggleCommandLog` flips `config.commandLog`, sets `isRecording`, saves via `ConfigFile.saveCommandLog(_:at: ConfigFile.defaultURL)`; on failure `PipelineLog.warning("couldn't save command log setting", detail:)` and `overlay.showHUD("couldn't save the log setting: check config.json", duration: .seconds(4))`.
- [ ] Run `swift build`: clean, no concurrency warnings.

### Task 4: Docs

**Files:** Modify `docs/configuration.md` (row `commandLog`, `true`; `false` records nothing, existing entries stay until cleared; changes live from the menu), `docs/privacy.md` § Command log (Clear Log in Recent commands deletes the file; Keep Command Log or `commandLog` `false` stops recording; replace "delete the file to clear it").

- [ ] Edit both; commit `docs: command log clear and off (NH-156)`.

### Final

- [ ] Run `swift test` (full), `swift build`; show output. Push the branch.
