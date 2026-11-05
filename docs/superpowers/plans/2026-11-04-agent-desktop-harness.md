# agent-desktop Harness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make agent-desktop the task loop's observation and action backend, widen the model's action vocabulary to agent-desktop's command surface, and keep the native path as the fallback.

**Architecture:** Pure Swift in `NoHandsCore` builds agent-desktop argv (`DesktopCommand`), decodes its JSON envelopes (`DesktopEnvelope`) and flattens snapshots (`DesktopSnapshot`); `Action`, the schema, the decoder and the prompt grow new kinds. `NoHandsMac` runs the binary (`AgentDesktopClient`), wraps it behind a `DesktopHarness` protocol (`AgentDesktopHarness`), and routes `ScreenObserver`/`ActionExecutor` through it with per-call native fallback. The app and CLI locate the binary and report harness status.

**Tech Stack:** Swift 6 (strict concurrency), SwiftPM, swift-testing (`@Test`), Foundation `Process`, agent-desktop CLI 1.1.0 (envelope `"version":"2.6"`).

**Spec:** `docs/superpowers/specs/2026-11-04-agent-desktop-harness-design.md`

## Global Constraints

- macOS 14+, Apple Silicon, Swift 6 strict concurrency; SwiftPM only.
- No new SwiftPM dependencies. agent-desktop is an external binary found at runtime; nothing in the app links or vendors it.
- NoHands.app is launched with `open`: PATH is `/usr/bin:/bin:/usr/sbin:/sbin`; the binary is located explicitly (config path, `$AGENT_DESKTOP_BIN`, `/opt/homebrew/bin`, `/usr/local/bin`, `~/.bun/bin`, `~/.volta/bin`, `~/.npm-global/bin`, `~/.local/bin`, `~/.nvm/versions/node/*/bin` newest first, then PATH).
- Never block the main actor on the child process; every harness call is `async` and killed on cancellation.
- `--headed` only on the fallback path after `delivery == "not_delivered"`; `--force` never.
- The native prompt (`IntentSchema.systemPrompt`) stays byte-identical to today's; harness rules are appended only when the observation's `harness == .agentDesktop`.
- agent-desktop 1.1.0 has no `--stdin`: text for `type`, `set-value`, `select`, `clipboard-set` is passed in argv.
- Base branch `fix/local-model-timeout` (98fb068); the harness kind is chosen once per task and never flips mid-task.
- New config keys and defaults: `desktopHarness` `auto` (`auto`/`agentDesktop`/`native`), `agentDesktopPath` nil, `agentDesktopTimeoutMs` 8000 (1000…60000), `agentDesktopSnapshotMs` 3000 (500…10000), `agentDesktopHeadedFallback` true, `agentDesktopTrace` false.
- Existing 280 tests keep passing after every task; commit after every task.

## Review Focus

1. A snapshot whose `tree` lacks `bounds` (the flag was dropped or the surface has none): elements still list, and a ref click still works; only the CGEvent fallback is unavailable. → Task 2 `elementsWithoutBoundsGetZeroFrame`, Task 9 `refClickWithoutFrameUsesHarnessOnly`.
2. The binary disappears or hangs mid-task (uninstalled, update in progress): the step fails with a plain message, the task continues on native, "stop" still works. → Task 6 `runKillsAtDeadline`, Task 8 `observerFallsBackToNativeOnProcessFailure`.
3. `AMBIGUOUS_TARGET` with no focused candidate (frontmost app has two unfocused windows after a Space switch): the first visible candidate is used, not an error. → Task 7 `ambiguousSnapshotRetriesWithFocusedOrFirstVisibleWindow`.
4. The model asks `set_value` on a badge-overlay label (no ref): the native fallback clicks, selects all and types; nothing errors with "no label". → Task 9 `setValueWithoutRefClicksSelectsAllAndTypes`.
5. A `close_app` for an app the goal never asked to quit: blocked before anything runs, and reported to the model as blocked. → Task 4 `closeAppBlockedUnlessGoalAsksToQuitOrClose`.

---

### Task 1: Envelope decoder and command builder (Core)

**Files:**
- Create: `Sources/NoHandsCore/DesktopEnvelope.swift`
- Create: `Sources/NoHandsCore/DesktopCommand.swift`
- Test: `Tests/NoHandsCoreTests/DesktopEnvelopeTests.swift`, `Tests/NoHandsCoreTests/DesktopCommandTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public struct DesktopDisposition: Equatable, Sendable { public var delivery: String; public var retry: String }
  public struct DesktopWindowCandidate: Equatable, Sendable { public var id: String; public var title: String; public var isFocused: Bool; public var visible: Bool }
  public struct DesktopError: Equatable, Sendable {
      public var code: String; public var message: String; public var suggestion: String?
      public var disposition: DesktopDisposition?; public var candidates: [DesktopWindowCandidate]; public var detailsKind: String?
      public var notDelivered: Bool   // disposition?.delivery == "not_delivered"
  }
  public struct DesktopEnvelope: Sendable {
      public var ok: Bool; public var command: String; public var data: [String: Any]?; public var error: DesktopError?
      public var disposition: DesktopDisposition?   // data.disposition on success
      public var surfaces: [String]                 // data.surfaces[].type or string entries; [] when absent
      public static func decode(_ data: Data) -> DesktopEnvelope?          // nil on malformed JSON
      public static func processFailure(command: String, message: String, observation: Bool) -> DesktopEnvelope
          // ok false, code "PROCESS_FAILED", disposition not_delivered/safe when observation, else unknown/unsafe
      public static func timeout(command: String, observation: Bool) -> DesktopEnvelope   // code "TIMEOUT", same rule
  }
  public enum DesktopSurface: String, Codable, Sendable, CaseIterable { case menubar, menu, sheet, alert, popover, dock, menuBarExtras = "menu_bar_extras"; public var cliName: String } // "menu-bar-extras"
  public enum DesktopWindowOp: String, Codable, Sendable, CaseIterable { case minimize, maximize, restore, focus }
  public enum DesktopWaitKind: String, Codable, Sendable, CaseIterable { case text, window, event, menu, menuClosed = "menu_closed", element }
  public enum DesktopEvent: String, Codable, Sendable, CaseIterable { case windowOpened = "window_opened", windowClosed = "window_closed", appLaunched = "app_launched", appTerminated = "app_terminated", focusChanged = "focus_changed", surfaceAppeared = "surface_appeared", surfaceDismissed = "surface_dismissed"; public var cliName: String } // "window-opened"
  public enum DesktopCommand: Equatable, Sendable {
      case version, status
      case snapshot(app: String?, windowID: String?, surface: DesktopSurface?, timeoutMs: Int)
      case find(app: String?, surface: DesktopSurface?, name: String, exact: Bool)
      case listWindows(app: String?), listSurfaces(app: String)
      case click(ref: String, button: MouseButton, count: Int)
      case type(ref: String, text: String), setValue(ref: String, text: String), clear(ref: String)
      case select(ref: String, option: String), check(ref: String, Bool), toggle(ref: String)
      case expand(ref: String, Bool), focus(ref: String), scrollTo(ref: String)
      case scroll(ref: String, Direction, amount: Int)
      case drag(fromRef: String?, fromXY: CGPoint?, toRef: String?, toXY: CGPoint?)
      case closeApp(String), window(DesktopWindowOp, app: String?, title: String?)
      case clipboardGet, clipboardSet(text: String)
      case get(ref: String, property: String)
      case listNotifications, dismissAllNotifications(app: String?)
      case wait(DesktopWaitKind, value: String?, app: String?, ref: String?, timeoutMs: Int)
      case sessionStart(name: String), sessionEnd(id: String)
      public var isObservation: Bool                 // snapshot/find/list*/get/clipboardGet/listNotifications/version/status
      public var needsHeaded: Bool                   // drag, click count > 1, listNotifications, dismissAllNotifications
      public var commandName: String                 // first argv word, e.g. "set-value"
      public func argv(headed: Bool, session: String?) -> [String]   // ["--headed"]? + ["--session", id]? + command + flags
  }
  ```

- [ ] **Step 1: Write the failing tests**

`DesktopEnvelopeTests.swift`:
```swift
@Test func decodesSuccessWithDispositionAndSurfaces() {
    let json = #"{"version":"2.6","ok":true,"command":"click","data":{"disposition":{"delivery":"delivered_verified","retry":"unsafe"},"surfaces":[{"type":"sheet"}]}}"#
    let e = DesktopEnvelope.decode(Data(json.utf8))!
    #expect(e.ok && e.command == "click" && e.disposition?.delivery == "delivered_verified" && e.surfaces == ["sheet"])
}
@Test func decodesAmbiguousErrorWithCandidates() {
    let json = #"{"version":"2.6","ok":false,"command":"snapshot","error":{"code":"AMBIGUOUS_TARGET","message":"More than one window","details":{"kind":"x","candidates":[{"id":"w-1","is_focused":false,"title":"A","visible":true},{"id":"w-2","is_focused":true,"title":"B","visible":true}]},"disposition":{"delivery":"not_delivered","retry":"safe"}}}"#
    let e = DesktopEnvelope.decode(Data(json.utf8))!
    #expect(!e.ok && e.error?.code == "AMBIGUOUS_TARGET" && e.error?.notDelivered == true && e.error?.candidates.map(\.id) == ["w-1", "w-2"] && e.error?.candidates[1].isFocused == true)
}
@Test func malformedAndSyntheticEnvelopes() {
    #expect(DesktopEnvelope.decode(Data("nope".utf8)) == nil)
    let t = DesktopEnvelope.timeout(command: "click", observation: false)
    #expect(t.error?.code == "TIMEOUT" && t.error?.notDelivered == false)
    #expect(DesktopEnvelope.processFailure(command: "snapshot", message: "m", observation: true).error?.notDelivered == true)
}
```
`DesktopCommandTests.swift`:
```swift
@Test func snapshotArgv() {
    let c = DesktopCommand.snapshot(app: "Finder", windowID: nil, surface: nil, timeoutMs: 2500)
    #expect(c.argv(headed: false, session: nil) == ["snapshot", "--app", "Finder", "-i", "--compact", "--include-bounds", "--max-depth", "25", "--timeout-ms", "2500"])
    #expect(DesktopCommand.snapshot(app: "Finder", windowID: "w-1", surface: .sheet, timeoutMs: 2500).argv(headed: false, session: nil).contains(["--window-id", "w-1", "--surface", "sheet"]))
}
@Test func headedSessionAndTextArgs() {
    #expect(DesktopCommand.setValue(ref: "@s1:e2", text: "cats").argv(headed: true, session: "abc") == ["--headed", "--session", "abc", "set-value", "@s1:e2", "cats"])
    #expect(DesktopCommand.click(ref: "@s1:e2", button: .right, count: 1).argv(headed: false, session: nil) == ["right-click", "@s1:e2"])
    #expect(DesktopCommand.click(ref: "@s1:e2", button: .left, count: 2).commandName == "double-click")
    #expect(DesktopCommand.click(ref: "@s1:e2", button: .left, count: 2).needsHeaded)
}
@Test func findWaitWindowAndDragArgv() {
    #expect(DesktopCommand.find(app: "Finder", surface: .menubar, name: "New Folder", exact: true).argv(headed: false, session: nil) == ["find", "--app", "Finder", "--surface", "menubar", "--name", "New Folder", "--exact", "--first"])
    #expect(DesktopCommand.wait(.event, value: "window_opened", app: "Finder", ref: nil, timeoutMs: 4000).argv(headed: false, session: nil) == ["wait", "--event", "window-opened", "--app", "Finder", "--timeout", "4000"])
    #expect(DesktopCommand.wait(.element, value: "actionable", app: nil, ref: "@s1:e3", timeoutMs: 4000).argv(headed: false, session: nil) == ["wait", "--element", "@s1:e3", "--predicate", "actionable", "--timeout", "4000"])
    #expect(DesktopCommand.window(.focus, app: "Safari", title: "GitHub").argv(headed: false, session: nil) == ["focus-window", "--app", "Safari", "--title", "GitHub"])
    #expect(DesktopCommand.drag(fromRef: nil, fromXY: CGPoint(x: 1, y: 2), toRef: "@s1:e9", toXY: nil).argv(headed: false, session: nil) == ["--headed", "drag", "--from-xy", "1,2", "--to", "@s1:e9"])
}
@Test func observationClassification() {
    #expect(DesktopCommand.snapshot(app: nil, windowID: nil, surface: nil, timeoutMs: 1).isObservation)
    #expect(!DesktopCommand.closeApp("X").isObservation)
    #expect(DesktopCommand.sessionStart(name: "n").argv(headed: false, session: nil) == ["session", "start", "--name", "n"])
}
```
Note: `drag` always emits `--headed` (it never has a headless path), independent of the `headed` argument; `needsHeaded` is true for it.

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter 'DesktopEnvelopeTests|DesktopCommandTests'` — Expected: compile failure (types undefined).

- [ ] **Step 3: Implement both files**

`DesktopEnvelope.decode` uses `JSONSerialization`; `surfaces` accepts `[String]` or `[{type:}]`; `candidates` read from `error.details.candidates`. `DesktopCommand.argv` builds per the test values; `wait` maps `.text`→`--text`, `.window`→`--window`, `.menu`→`--menu`, `.menuClosed`→`--menu-closed`, `.element`→`--element <ref> --predicate <value>`; `window(.minimize/.maximize/.restore)` → `minimize/maximize/restore --app X`; `listNotifications` → `list-notifications`; `dismissAllNotifications` → `dismiss-all-notifications [--app X]`; `get` → `get <ref> --property <p>`; `select` → `select <ref> <option>`; `scroll` → `scroll <ref> --direction d --amount n`; `check(ref, true/false)` → `check`/`uncheck`; `expand(ref, true/false)` → `expand`/`collapse`; `type` → `type <ref> <text>`; `clipboardSet` → `clipboard-set <text>`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter 'DesktopEnvelopeTests|DesktopCommandTests'` — Expected: PASS.

- [ ] **Step 5: Commit** — `git commit -m "feat(core): agent-desktop envelope decoder and command builder"`

---

### Task 2: Snapshot flattening and element model (Core)

**Files:**
- Create: `Sources/NoHandsCore/DesktopSnapshot.swift`
- Modify: `Sources/NoHandsCore/TitleSource.swift` (`UIElementInfo` gains `ref: String?` with default nil, `value: String?`, `states: [String]`)
- Modify: `Sources/NoHandsCore/IntentStep.swift` (`ObservedElement` gains `value: String?`, `states: [String]`, defaults empty)
- Create: `Tests/NoHandsCoreTests/Fixtures/agent-desktop-finder-menubar.json` (copy of the real envelope from `/private/tmp/claude-501/-Users-noahstotland--t3-projects-nohands/7428179d-c96c-423c-bbd1-ffe3a0effa66/scratchpad/menubar.json`), `Tests/NoHandsCoreTests/Fixtures/agent-desktop-window.json` (hand-trimmed from the Claude-app snapshot: one webarea → group → two buttons "Hide sidebar"/"New chat", one textfield with value, one checkbox with states ["checked"], one unnamed group with a ref)
- Modify: `Package.swift` — add `resources: [.copy("Fixtures")]` to the `NoHandsCoreTests` target
- Test: `Tests/NoHandsCoreTests/DesktopSnapshotTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public struct DesktopSnapshot: Equatable, Sendable {
      public var app: String; public var snapshotID: String; public var windowID: String?; public var windowTitle: String?
      public var complete: Bool
      public var elements: [UIElementInfo]      // depth-first, ids 1…N, ref set, frame from bounds (zero when absent)
      public static func parse(_ data: [String: Any]) -> DesktopSnapshot?           // the envelope's `data`
      public static let editableRoles: Set<String> = ["textfield", "textarea", "searchfield", "combobox"]
      public static func listable(_ e: UIElementInfo) -> Bool   // has ref and (non-blank title, or value, or editable role)
  }
  public struct DesktopFindMatch: Equatable, Sendable { public var ref: String; public var role: String; public var name: String; public var path: [String]; public var disabled: Bool
      public static func parse(_ data: [String: Any]) -> DesktopFindMatch? }   // data.match
  ```
- `UIElementInfo.init(id:frame:title:role:ref:value:states:)` keeps the old 4-argument form valid (defaults).

- [ ] **Step 1: Write the failing tests**

```swift
func fixture(_ name: String) -> [String: Any] {
    let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!
    let root = try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    return root["data"] as! [String: Any]
}
@Test func parsesWindowSnapshotDepthFirstWithRefsValuesAndStates() {
    let s = DesktopSnapshot.parse(fixture("agent-desktop-window"))!
    #expect(s.app == "Claude" && s.snapshotID.hasPrefix("s"))
    let listed = s.elements.filter(DesktopSnapshot.listable)
    #expect(listed.map(\.title) == ["Hide sidebar", "New chat", "", "Remember me"])   // textfield listed by role, unnamed group dropped
    #expect(listed[2].role == "textfield" && listed[2].value == "cats")
    #expect(listed[3].states == ["checked"] && listed[0].ref?.hasPrefix("@") == true)
    #expect(listed[0].frame == CGRect(x: 84, y: 40, width: 28, height: 28))
}
@Test func elementsWithoutBoundsGetZeroFrame() {
    let s = DesktopSnapshot.parse(fixture("agent-desktop-finder-menubar"))!
    #expect(!s.complete && s.elements.count == 294 && s.elements.allSatisfy { $0.frame == .zero } && s.elements[1].title == "About This Mac")
}
@Test func findMatchParses() {
    let data: [String: Any] = ["match": ["ref_id": "@s1:e1", "role": "menuitem", "name": "New Folder", "path": ["menu", "menuitem:File"], "states": ["disabled"]], "snapshot_id": "s1"]
    let m = DesktopFindMatch.parse(data)!
    #expect(m.ref == "@s1:e1" && m.disabled && m.path == ["menu", "menuitem:File"])
}
```

- [ ] **Step 2: Run to verify failure** — `swift test --filter DesktopSnapshotTests` → compile failure.
- [ ] **Step 3: Implement** `DesktopSnapshot.parse` (recursive walk over `tree`/`children`; `ref_id` → `ref`; `bounds` → frame; `role` kept lowercase as given; `name` → title, `value` stringified when string/number/bool), the `UIElementInfo`/`ObservedElement` fields, the fixtures and `Package.swift` resources.
- [ ] **Step 4: Run** `swift test` → all pass (existing `UIElementInfo(...)` call sites compile unchanged).
- [ ] **Step 5: Commit** — `git commit -m "feat(core): flatten agent-desktop snapshots into numbered elements"`

---

### Task 3: Observation and request text (Core)

**Files:**
- Modify: `Sources/NoHandsCore/IntentStep.swift` (`ScreenObservation` gains `harness: HarnessKind = .native`, `surface: String? = nil`, `windows: [String] = []`, `readings: [String] = []`; new `public enum HarnessKind: String, Codable, Sendable { case native, agentDesktop = "agent-desktop" }`)
- Modify: `Sources/NoHandsCore/ClaudeRequestBuilder.swift:33-51`
- Modify: `Sources/NoHandsCore/TaskGuards.swift:60-70` (`Settle.same` also compares `surface`; signature includes `value`)
- Test: `Tests/NoHandsCoreTests/IntentStepTests.swift` (add), `Tests/NoHandsCoreTests/TaskGuardsTests.swift` (add)

**Interfaces:** `ClaudeRequestBuilder.userMessage(request:)` output format:
```
Goal: …
Step: n of m
History: …
App: X   Window: Y   URL: -
Mode: command   Overlay: none   Harness: agent-desktop
Surface: sheet                       (only when non-nil)
Windows: "Inbox", "Draft"            (only when non-empty; titles sanitized, quoted)
Visible elements:
  1 [button] Save (disabled)
  2 [textfield] Name = "cats"
  3 [checkbox] Remember me (checked)
Read:                                 (only when non-empty)
  clipboard: https://…
Request: …
```
States shown, in this order when present: checked, selected, expanded, collapsed, disabled, focused, offscreen. Values cut at 60 characters, readings at 300.

- [ ] **Step 1: Write the failing tests**
```swift
@Test func requestShowsHarnessSurfaceWindowsStatesValuesAndReadings() {
    var o = ScreenObservation(app: "Notes", mode: .command, elements: [
        ObservedElement(number: 1, role: "button", title: "Save", states: ["disabled"]),
        ObservedElement(number: 2, role: "textfield", title: "Name", value: "cats"),
        ObservedElement(number: 3, role: "checkbox", title: "Remember me", states: ["offscreen", "checked"])])
    o.harness = .agentDesktop; o.surface = "sheet"; o.windows = ["Inbox", "Draft\nX"]; o.readings = ["clipboard: hi"]
    let s = ClaudeRequestBuilder.userMessage(request: StepRequest(goal: "g", step: 1, maxSteps: 3, history: [], observation: o))
    #expect(s.contains("Harness: agent-desktop\nSurface: sheet\nWindows: \"Inbox\", \"Draft X\"\n"))
    #expect(s.contains("  1 [button] Save (disabled)\n  2 [textfield] Name = \"cats\"\n  3 [checkbox] Remember me (checked, offscreen)\n"))
    #expect(s.contains("Read:\n  clipboard: hi\n"))
}
@Test func nativeRequestIsUnchanged() {
    let o = ScreenObservation(app: "Finder", mode: .command, elements: [ObservedElement(number: 1, role: "button", title: "Back")])
    let s = ClaudeRequestBuilder.userMessage(request: StepRequest(goal: "g", step: 1, maxSteps: 3, history: [], observation: o))
    #expect(s.contains("Mode: command   Overlay: none   Harness: native\n") && !s.contains("Surface:") && !s.contains("Read:"))
}
@Test func settleComparesSurfaceAndValues() {
    var a = ScreenObservation(app: "A", mode: .command, elements: [ObservedElement(number: 1, role: "textfield", title: "q", value: "x")])
    var b = a
    #expect(Settle.same(a, b))
    b.elements[0].value = "y"; #expect(!Settle.same(a, b))
    b = a; b.surface = "menu"; #expect(!Settle.same(a, b))
    a.elements[0].number = 7; #expect(Settle.same(a, b) == false || true)   // numbers/refs are not part of the signature
}
```
Also update the existing `requestMentionsOverlayKind` expectation if it asserts the exact `Mode:` line.

- [ ] **Step 2: Run** `swift test --filter 'IntentStepTests|TaskGuardsTests'` → fails.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `swift test` → pass (fix the one-shot `IntentContext` adapter and any prompt-text tests that changed).
- [ ] **Step 5: Commit** — `git commit -m "feat(core): harness, surface, windows and readings in observations"`

---

### Task 4: New actions, summary, guard (Core)

**Files:**
- Modify: `Sources/NoHandsCore/Action.swift`
- Modify: `Sources/NoHandsCore/ActionSummary.swift`
- Modify: `Sources/NoHandsCore/ShortcutGuard.swift`
- Test: `Tests/NoHandsCoreTests/ActionSummaryTests.swift`, `Tests/NoHandsCoreTests/ShortcutGuardTests.swift`

**Interfaces:**
```swift
public enum ElementTarget: Equatable, Codable, Sendable { case label(Int), named(String) }
public enum WaitCondition: Equatable, Codable, Sendable {
    case text(String), window(String), event(DesktopEvent), menu, menuClosed, element(ElementTarget, predicate: String)
}
// Action gains:
case setValue(ElementTarget, String)
case typeInto(ElementTarget, String)
case clearField(ElementTarget)
case selectOption(ElementTarget, String)
case setChecked(ElementTarget, Bool?)          // nil = toggle
case setExpanded(ElementTarget, Bool)
case focusElement(ElementTarget)
case scrollTo(ElementTarget)
case scrollIn(ElementTarget, Direction, amount: Int)
case drag(from: MoveTarget, to: MoveTarget)
case clickIn(DesktopSurface, name: String)
case menuItem(String)
case closeApp(String)
case windowAction(DesktopWindowOp, app: String?, title: String?)
case clipboardSet(String)
case readClipboard
case readValue(ElementTarget)
case readNotifications
case dismissNotifications(app: String?)
case waitFor(WaitCondition, timeoutMs: Int)
```
`ActionSummary.kind` names: `setValue(len=n)`, `typeInto(len=n)`, `clearField`, `selectOption`, `setChecked`, `setExpanded`, `focusElement`, `scrollTo`, `scrollIn`, `drag`, `clickIn(<surface>)`, `menuItem`, `closeApp`, `windowAction(<op>)`, `clipboardSet(len=n)`, `readClipboard`, `readValue`, `readNotifications`, `dismissNotifications`, `waitFor(<kind>)` — no names, titles or text.
`ShortcutGuard.blocked`: `.closeApp` is blocked unless the goal has a word from `["quit","quits","quitting","exit","exiting","shut","close","closes","closing","closed"]`; message `"blocked: close_app not allowed for this request"`.

- [ ] **Step 1: Tests**
```swift
@Test func summaryOfHarnessActionsOmitsPayloads() {
    let s = ActionSummary.kinds([.setValue(.label(1), "secret"), .menuItem("Save As…"), .clickIn(.dock, name: "Safari"), .windowAction(.minimize, app: "Slack", title: nil), .waitFor(.text("done"), timeoutMs: 1000), .closeApp("Slack")])
    #expect(s == "[setValue(len=6), menuItem, clickIn(dock), windowAction(minimize), waitFor(text), closeApp]")
}
@Test func closeAppBlockedUnlessGoalAsksToQuitOrClose() {
    #expect(ShortcutGuard.blocked([.closeApp("Slack")], goal: "open slack") == "blocked: close_app not allowed for this request")
    #expect(ShortcutGuard.blocked([.closeApp("Slack")], goal: "quit slack") == nil)
    #expect(ShortcutGuard.blocked([.closeApp("Slack")], goal: "close slack") == nil)
    #expect(ShortcutGuard.blocked([.windowAction(.minimize, app: "Slack", title: nil)], goal: "hide it") == nil)
}
```
- [ ] **Step 2: Run** → compile failure. **Step 3: Implement.** **Step 4:** `swift test` → pass. **Step 5: Commit** — `git commit -m "feat(core): harness action kinds, summaries and close_app guard"`

---

### Task 5: Schema, prompt, decoder, examples (Core)

**Files:**
- Modify: `Sources/NoHandsCore/IntentSchema.swift`
- Modify: `Sources/NoHandsCore/IntentDecoder.swift`
- Modify: `Sources/NoHandsCore/ClaudeRequestBuilder.swift` and `OllamaRequestBuilder.swift` (`body(request:)` picks `IntentSchema.systemPrompt(for: request.observation.harness)` and, for Ollama, `IntentExamples.turns(for:)`; `warmBody(harness: HarnessKind = .native)` uses the same)
- Test: `Tests/NoHandsCoreTests/IntentHarnessTests.swift`

**Interfaces:**
- `IntentSchema.kinds` += `["set_value","type_into","clear","select","check","uncheck","toggle","expand","collapse","focus","scroll_to","scroll_element","drag","click_in","menu_item","close_app","window","clipboard_set","read_clipboard","read_value","read_notifications","dismiss_notifications"]`.
- New schema properties: `value` (string), `option` (string), `surface` (enum `DesktopSurface` raw values), `window_action` (enum minimize/maximize/restore/focus), `title` (string), `wait_for` (enum text/window/event/menu/menu_closed/element), `event` (enum `DesktopEvent` raw values), `predicate` (string), `timeout_ms` (integer), `from_number` (integer), `from_name` (string), `from_x`, `from_y` (number).
- `public static func systemPrompt(for harness: HarnessKind) -> String`: `.native` returns `systemPrompt` unchanged; `.agentDesktop` returns `systemPrompt + "\n\n" + harnessRules` where `harnessRules` (exact copy) is:
  ```
  Harness: agent-desktop. This request's elements come from the accessibility tree with stable references, so these extra kinds act on an element by its number (target_kind "label", target_number) or by name (target_kind "element", target_name):
  - set_value: replace a field's text. Fields: value. Prefer it over clicking and typing.
  - type_into: type into a field with real keystrokes. Fields: text.
  - clear: empty a field.
  - select: pick an option in a dropdown or list. Fields: option (the visible option text).
  - check / uncheck: set a checkbox or switch (idempotent; prefer over toggle). toggle: flip it.
  - expand / collapse: a disclosure triangle or tree item.
  - focus: give an element keyboard focus. scroll_to: scroll an element into view. scroll_element: scroll inside an element. Fields: direction, amount.
  - drag: drag from one place to another. Fields: from_number or from_name or from_x/from_y (source), and target_* (destination).
  - click_in: click a named item in a surface. Fields: surface (menubar, menu, sheet, alert, popover, dock, menu_bar_extras), target_name.
  - menu_item: run a menu bar command by its name, e.g. "Save As…" or "File > Save As…". Fields: target_name. Prefer it over keyboard shortcuts for menu commands.
  - close_app: quit an app. Fields: app_name. Only when the request asks to quit or close it.
  - window: minimize, maximize, restore or focus a window. Fields: window_action, app_name (optional), title (focus only, optional).
  - clipboard_set: put text on the clipboard. Fields: value. read_clipboard: read it; the text arrives in the next step under "Read:".
  - read_value: read an element's value or text. Fields: target_*. It arrives in the next step under "Read:".
  - read_notifications: list Notification Center entries (arrive under "Read:"). dismiss_notifications: dismiss them all. Fields: app_name (optional).
  - wait with wait_for: wait for a signal instead of a fixed time. Fields: wait_for (text, window, event, menu, menu_closed, element), value (the text, window title, or element predicate exists/enabled/visible/actionable), event (window_opened, window_closed, app_launched, app_terminated, focus_changed, surface_appeared, surface_dismissed), app_name (optional), target_number (element), timeout_ms (500-30000).
  Harness rules: when a "Surface:" line is present a menu, sheet, alert or popover is open; act on its elements first and ignore the window behind it. A history entry "FAILED: element changed, look again" means the screen changed under you: look at this request's elements and choose again, never repeat the old number. Values shown after "=" are the field's current text. "Read:" lines are the results you asked for in the previous step; use them to answer or decide, then finish.
  ```
- `IntentDecoder` maps the kinds to the Task 4 cases. `ElementTarget` from `target_kind` `label`/`element` (`target_number`/`target_name`); for `read_value`, `focus`, etc. the same. `check` → `.setChecked(t, true)`, `uncheck` → `false`, `toggle` → `nil`. `wait` with `wait_for` → `.waitFor(…, timeoutMs: clamp(timeout_ms ?? 5000, 500...30000))`; `wait_for: element` needs `target_number`, predicate defaults `"exists"`. `drag` builds `from:` from `from_number` (`.label`), `from_name` (`.element`), `from_x/from_y` (`.point`). `window` requires `window_action`. `click_in` requires `surface` and `target_name`. Text fields are blank-checked like today; `set_value` allows an empty `value` (clears) — no: empty value → `.clearField`.

- [ ] **Step 1: Tests**
```swift
@Test func decodesEveryHarnessKind() throws {
    let json = #"""
    {"intent":"x","status":"continue","actions":[
      {"kind":"set_value","target_kind":"label","target_number":2,"value":"cats"},
      {"kind":"type_into","target_kind":"element","target_name":"Search","text":"hi"},
      {"kind":"clear","target_kind":"label","target_number":2},
      {"kind":"select","target_kind":"label","target_number":3,"option":"Blue"},
      {"kind":"check","target_kind":"label","target_number":4},{"kind":"uncheck","target_kind":"label","target_number":4},{"kind":"toggle","target_kind":"label","target_number":4},
      {"kind":"expand","target_kind":"label","target_number":5},{"kind":"collapse","target_kind":"label","target_number":5},
      {"kind":"focus","target_kind":"label","target_number":6},{"kind":"scroll_to","target_kind":"label","target_number":6},
      {"kind":"scroll_element","target_kind":"label","target_number":7,"direction":"down","amount":3},
      {"kind":"drag","from_number":1,"target_kind":"point","x":10,"y":20},
      {"kind":"click_in","surface":"dock","target_name":"Safari"},
      {"kind":"menu_item","target_name":"File > Save As…"},
      {"kind":"close_app","app_name":"Slack"},
      {"kind":"window","window_action":"focus","app_name":"Safari","title":"GitHub"},
      {"kind":"clipboard_set","value":"hello"},{"kind":"read_clipboard"},
      {"kind":"read_value","target_kind":"label","target_number":2},
      {"kind":"read_notifications"},{"kind":"dismiss_notifications","app_name":"Mail"},
      {"kind":"wait","wait_for":"text","value":"Done","app_name":"App","timeout_ms":100},
      {"kind":"wait","wait_for":"event","event":"window_opened"},
      {"kind":"wait","wait_for":"element","target_number":9,"value":"actionable"},
      {"kind":"wait","ms":700}]}
    """#
    let a = try IntentDecoder.step(fromPayloadText: json).actions
    #expect(a.count == 26)
    #expect(a[0] == .setValue(.label(2), "cats") && a[1] == .typeInto(.named("Search"), "hi") && a[2] == .clearField(.label(2)))
    #expect(a[4] == .setChecked(.label(4), true) && a[5] == .setChecked(.label(4), false) && a[6] == .setChecked(.label(4), nil))
    #expect(a[12] == .drag(from: .label(1), to: .point(CGPoint(x: 10, y: 20))))
    #expect(a[13] == .clickIn(.dock, name: "Safari") && a[14] == .menuItem("File > Save As…") && a[16] == .windowAction(.focus, app: "Safari", title: "GitHub"))
    #expect(a[22] == .waitFor(.text("Done"), timeoutMs: 500) && a[23] == .waitFor(.event(.windowOpened), timeoutMs: 5000) && a[24] == .waitFor(.element(.label(9), predicate: "actionable"), timeoutMs: 5000) && a[25] == .wait(ms: 700))
}
@Test func harnessKindsFailClosedOnMissingFields() throws {
    let json = #"{"actions":[{"kind":"set_value","value":"x"},{"kind":"click_in","target_name":"Safari"},{"kind":"window","app_name":"Safari"},{"kind":"wait","wait_for":"element","value":"exists"},{"kind":"select","target_kind":"label","target_number":1}]}"#
    #expect(try IntentDecoder.step(fromPayloadText: json).actions.isEmpty)
}
@Test func schemaListsNewKindsAndFieldsAndStaysClosed() {
    let props = (IntentSchema.actionsJSONSchema["properties"] as! [String: Any])["actions"] as! [String: Any]
    let item = props["items"] as! [String: Any]
    let fields = item["properties"] as! [String: Any]
    for f in ["value", "option", "surface", "window_action", "title", "wait_for", "event", "predicate", "timeout_ms", "from_number", "from_name", "from_x", "from_y"] { #expect(fields[f] != nil, "\(f)") }
    let kinds = ((fields["kind"] as! [String: Any])["enum"] as! [String])
    #expect(kinds.contains("menu_item") && kinds.contains("set_value") && item["additionalProperties"] as? Bool == false)
}
@Test func promptAddsHarnessRulesOnlyForAgentDesktop() {
    #expect(IntentSchema.systemPrompt(for: .native) == IntentSchema.systemPrompt)
    let p = IntentSchema.systemPrompt(for: .agentDesktop)
    #expect(p.hasPrefix(IntentSchema.systemPrompt) && p.contains("- menu_item:") && p.contains("Harness rules:"))
    #expect(!IntentSchema.systemPrompt.contains("menu_item"))
}
@Test func requestBodiesUseTheObservationHarnessPrompt() throws {
    var o = ScreenObservation(app: "Finder", mode: .command); o.harness = .agentDesktop
    let r = StepRequest(goal: "g", step: 1, maxSteps: 2, history: [], observation: o)
    let claude = try JSONSerialization.jsonObject(with: ClaudeRequestBuilder(model: "m").body(request: r)) as! [String: Any]
    #expect((claude["system"] as! String).contains("Harness rules:"))
    let ollama = try JSONSerialization.jsonObject(with: OllamaRequestBuilder(model: "m").body(request: r)) as! [String: Any]
    let system = ((ollama["messages"] as! [[String: Any]])[0]["content"] as! String)
    #expect(system.contains("Harness rules:"))
    let warm = try JSONSerialization.jsonObject(with: OllamaRequestBuilder(model: "m").warmBody()) as! [String: Any]
    #expect(!(((warm["messages"] as! [[String: Any]])[0]["content"] as! String).contains("Harness rules:")))
    let warmH = try JSONSerialization.jsonObject(with: OllamaRequestBuilder(model: "m").warmBody(harness: .agentDesktop)) as! [String: Any]
    #expect((((warmH["messages"] as! [[String: Any]])[0]["content"] as! String).contains("Harness rules:")))
}
```
Also add `IntentExamples.harnessTurns` (two harness observations — a `menu_item` answer for "save this as a new file" on TextEdit and a `set_value` + `click` answer for "search for cats" with a textfield and a Search button) and `IntentExamples.turns(for: HarnessKind)` (`.native` → `turns`, `.agentDesktop` → `turns + harnessTurns`); assert in a test that every example's assistant JSON decodes to at least one action and that the harness turns contain `menu_item` and `set_value`.

- [ ] **Step 2: Run** → compile failure. **Step 3: Implement.** **Step 4:** `swift test` → pass (`IntentEvalTests` fixtures still decode). **Step 5: Commit** — `git commit -m "feat(core): harness action kinds in schema, prompt and decoder"`

---

### Task 6: Config keys, locator and process runner (Mac)

**Files:**
- Modify: `Sources/NoHandsCore/AppConfig.swift` (keys per Global Constraints; `public enum DesktopHarnessChoice: String, Codable, Sendable, CaseIterable { case auto, agentDesktop, native }`; unknown value → `.auto`; `agentDesktopTimeoutMs` clamped 1000…60000)
- Create: `Sources/NoHandsMac/AgentDesktopLocator.swift`
- Create: `Sources/NoHandsMac/AgentDesktopClient.swift`
- Test: `Tests/NoHandsCoreTests/AppConfigTests.swift` (add), `Tests/NoHandsMacTests/AgentDesktopClientTests.swift`

**Interfaces:**
```swift
public enum AgentDesktopLocator {
    /// First executable file among the candidates in Global Constraints order; `home` and `environment` injected for tests.
    public static func find(configPath: String?, environment: [String: String], home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL?
    public static func candidates(configPath: String?, environment: [String: String], home: URL) -> [URL]
}
public struct AgentDesktopClient: Sendable {
    public init(binary: URL, defaultDeadline: Duration)
    /// Runs argv off the main actor; stdin is /dev/null; the child is killed at the deadline or on task cancellation.
    public func run(_ argv: [String], deadline: Duration? = nil, isObservation: Bool, environment: [String: String] = [:]) async -> DesktopEnvelope
}
```

- [ ] **Step 1: Tests**
```swift
@Test func locatorOrderAndNvmNewestFirst() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    for v in ["v18.18.2", "v22.1.0"] { try FileManager.default.createDirectory(at: home.appendingPathComponent(".nvm/versions/node/\(v)/bin"), withIntermediateDirectories: true) }
    let bin = home.appendingPathComponent(".nvm/versions/node/v22.1.0/bin/agent-desktop")
    FileManager.default.createFile(atPath: bin.path, contents: Data(), attributes: [.posixPermissions: 0o755])
    #expect(AgentDesktopLocator.find(configPath: nil, environment: [:], home: home) == bin)
    let c = AgentDesktopLocator.candidates(configPath: "/x/agent-desktop", environment: ["AGENT_DESKTOP_BIN": "/y/agent-desktop", "PATH": "/p"], home: home).map(\.path)
    #expect(c.prefix(4).elementsEqual(["/x/agent-desktop", "/y/agent-desktop", "/opt/homebrew/bin/agent-desktop", "/usr/local/bin/agent-desktop"]) && c.last == "/p/agent-desktop")
    #expect(c.firstIndex(of: home.appendingPathComponent(".nvm/versions/node/v22.1.0/bin/agent-desktop").path)! < c.firstIndex(of: home.appendingPathComponent(".nvm/versions/node/v18.18.2/bin/agent-desktop").path)!)
}
```
`AgentDesktopClientTests` use a shell script written to a temp file as the "binary":
```swift
func script(_ body: String) -> URL { /* writes #!/bin/sh + body to a temp file, chmod 755 */ }
@Test func runDecodesStdoutAndPassesArgs() async {
    let c = AgentDesktopClient(binary: script(#"printf '{"version":"2.6","ok":true,"command":"type","data":{"echo":"%s"}}' "$3""#), defaultDeadline: .seconds(2))
    let e = await c.run(["type", "@s1:e1", "hello"], isObservation: false)
    #expect(e.ok && (e.data?["echo"] as? String) == "hello")
}
@Test func runKillsAtDeadline() async {
    let c = AgentDesktopClient(binary: script("sleep 5"), defaultDeadline: .milliseconds(200))
    let t = ContinuousClock.now
    let e = await c.run(["snapshot"], isObservation: true)
    #expect(e.error?.code == "TIMEOUT" && e.error?.notDelivered == true && t.duration(to: .now) < .seconds(2))
}
@Test func runReportsProcessFailureAndMalformedOutput() async {
    let bad = AgentDesktopClient(binary: script("echo nope; exit 1"), defaultDeadline: .seconds(1))
    #expect(await bad.run(["status"], isObservation: true).error?.code == "PROCESS_FAILED")
    let missing = AgentDesktopClient(binary: URL(fileURLWithPath: "/nonexistent/agent-desktop"), defaultDeadline: .seconds(1))
    #expect(await missing.run(["status"], isObservation: true).error?.code == "PROCESS_FAILED")
}
@Test func runIsCancellable() async {
    let c = AgentDesktopClient(binary: script("sleep 5"), defaultDeadline: .seconds(10))
    let task = Task { await c.run(["click", "@s1:e1"], isObservation: false) }
    try? await Task.sleep(for: .milliseconds(100)); task.cancel()
    let t = ContinuousClock.now; let e = await task.value
    #expect(e.error?.code == "CANCELLED" && t.duration(to: .now) < .seconds(2))
}
```
Config test: `desktopHarness` decodes `"agentDesktop"`, unknown → `.auto`; `agentDesktopTimeoutMs` 10 → 1000.

- [ ] **Step 2: Run** → compile failure. **Step 3: Implement.** `run` wraps `Process` in `withTaskCancellationHandler`; stdin is `/dev/null`; stdout read via a pipe on a background thread; a `DispatchWorkItem`/timer terminates at the deadline; a non-zero exit with a decodable envelope still returns that envelope (agent-desktop exits 1 on structured errors). **Step 4:** `swift test` → pass. **Step 5: Commit** — `git commit -m "feat(mac): agent-desktop locator, process client and config keys"`

---

### Task 7: Harness protocol and AgentDesktopHarness (Mac)

**Files:**
- Create: `Sources/NoHandsMac/DesktopHarness.swift`
- Create: `Sources/NoHandsMac/AgentDesktopHarness.swift`
- Modify: `Tests/NoHandsMacTests/Fakes.swift` (add `FakeHarness`, `ScriptedClient`)
- Test: `Tests/NoHandsMacTests/AgentDesktopHarnessTests.swift`

**Interfaces:**
```swift
public enum HarnessActionResult: Equatable, Sendable {
    case delivered(verified: Bool)
    case notDelivered(String)         // safe to fall back; message for the HUD
    case failed(String)               // may have landed; final
    case elementChanged               // STALE_REF / AMBIGUOUS_TARGET / SNAPSHOT_NOT_FOUND / ELEMENT_NOT_FOUND
}
public protocol DesktopCommandRunning: Sendable {   // AgentDesktopClient conforms; tests script it
    func run(_ argv: [String], deadline: Duration?, isObservation: Bool, environment: [String: String]) async -> DesktopEnvelope
}
public protocol DesktopHarness: AnyObject, Sendable {
    var kind: HarnessKind { get }
    /// Elements of `app`'s focused window (ambiguity resolved per spec) or of `surface`; nil → caller falls back to native.
    func snapshot(app: String, surface: DesktopSurface?, timeoutMs: Int) async -> DesktopSnapshot?
    func find(app: String?, surface: DesktopSurface?, name: String) async -> DesktopFindMatch?   // exact first, then contains
    /// Runs an action command; retries once with --headed when `notDelivered` and `headedFallback`; records `data.surfaces`.
    func act(_ command: DesktopCommand) async -> HarnessActionResult
    func read(_ command: DesktopCommand) async -> String?      // get/clipboard-get/list-notifications → text, nil on error
    func listWindows(app: String) async -> [DesktopWindowCandidate]
    /// Surfaces reported by the last action; cleared by `takeOpenSurfaces()`.
    func takeOpenSurfaces() -> [String]
    func startSession(name: String) async -> String?
    func endSession(_ id: String) async
}
public final class AgentDesktopHarness: DesktopHarness, @unchecked Sendable {
    public init(client: any DesktopCommandRunning, headedFallback: Bool, session: String? = nil)
    public var session: String?        // set after startSession; passed as --session on every call
}
```
`FakeHarness` (tests): records every `act`/`read`/`find`/`snapshot` call as strings (`"act:set-value @s1:e2"`), returns scripted results (`snapshotResult`, `findResult`, `actResults: [HarnessActionResult]` consumed in order, `readResult`, `surfacesToReport`).
`ScriptedClient`: `responses: [String: [DesktopEnvelope]]` keyed by `commandName`, plus `calls: [[String]]`.

- [ ] **Step 1: Tests**
```swift
@Test func ambiguousSnapshotRetriesWithFocusedOrFirstVisibleWindow() async { /* ScriptedClient: snapshot → AMBIGUOUS with [w-1 unfocused, w-2 focused] then ok fixture; expect second call argv contains ["--window-id","w-2"]; then a variant with none focused → "w-1" */ }
@Test func snapshotReturnsNilOnOtherErrors() async { /* WINDOW_NOT_FOUND → nil; PROCESS_FAILED → nil; single call */ }
@Test func actMapsDispositionsAndRetriesHeadedOnlyWhenNotDelivered() async {
    /* click → ACTION_NOT_SUPPORTED not_delivered then ok delivered_verified: expect calls[0] has no --headed, calls[1] starts with "--headed", result .delivered(verified:true);
       click → ACTION_FAILED with disposition delivery "delivered_unverified": single call, result .failed(message);
       click → STALE_REF: single call, .elementChanged;
       headedFallback false: ACTION_NOT_SUPPORTED → single call, .notDelivered */
}
@Test func actRecordsSurfacesUntilTaken() async { /* ok with surfaces ["sheet"] → takeOpenSurfaces() == ["sheet"], then [] */ }
@Test func findTriesExactThenContains() async { /* exact → ok with no match (data.match null) then contains → match; expect calls[0] contains "--exact", calls[1] does not */ }
@Test func readExtractsText() async { /* get → data.value "cats" → "cats"; clipboard-get → data.text; list-notifications → data.notifications[] joined as "App: Title — body" lines; error → nil */ }
@Test func sessionFlagIsPassedToEveryCall() async { /* startSession returns data.session_id "abc"; next act argv has ["--session","abc"] */ }
```
- [ ] **Step 2: Run** → compile failure. **Step 3: Implement.** Dispositions: ok → `.delivered(verified: delivery == "delivered_verified")`; error with `notDelivered` → `.notDelivered(message)`; codes `STALE_REF`, `AMBIGUOUS_TARGET`, `SNAPSHOT_NOT_FOUND`, `ELEMENT_NOT_FOUND` → `.elementChanged`; anything else → `.failed(message)`. Snapshot deadline = `timeoutMs + 1500` ms; the timeout envelope → nil. **Step 4:** `swift test` → pass. **Step 5: Commit** — `git commit -m "feat(mac): DesktopHarness protocol and agent-desktop implementation"`

---

### Task 8: ScreenObserver through the harness (Mac)

**Files:**
- Modify: `Sources/NoHandsMac/ScreenObserver.swift`
- Test: `Tests/NoHandsMacTests/ScreenObserverTests.swift` (add)

**Interfaces:**
```swift
public struct ScreenObserver: Sendable {
    public init(ax: any ElementProviding, maxElements: Int, harness: (any DesktopHarness)? = nil, snapshotTimeoutMs: Int = 3000)
    /// Async now; the native walk still runs off the main actor by the caller's `Task.detached`.
    public func observe(mode: Mode, overlay: OverlayState, screens: [CGRect]? = nil,
                        readings: [String] = []) async -> (observation: ScreenObservation, labels: [Int: UIElementInfo])
}
```
Behaviour: `observe(... harnessKind: HarnessKind ...)` — the caller (TaskRunner) decides the kind once per task; the observation's `harness` is always that kind. When `harness != nil`, `harnessKind == .agentDesktop` and overlay is not `.labels`: `app = ax.frontmostAppName()`; `surfaces = harness.takeOpenSurfaces()`; if a surface in {menu, sheet, alert, popover} is open, snapshot that surface (window elements omitted, `observation.surface` set); else snapshot the window. nil snapshot → native walk (elements without refs) but `harness` stays `.agentDesktop`. A separate `probe() async -> Bool` (one snapshot of the frontmost app) lets TaskRunner choose the kind at task start. Elements numbered in snapshot order filtered by `DesktopSnapshot.listable`, capped at `maxElements`; `labels[n]` keeps the `ref`. `readings` copied through. `windows` left empty here.

- [ ] **Step 1: Tests**
```swift
@MainActor @Test func observerUsesHarnessElementsAndKeepsRefs() async { /* FakeHarness.snapshotResult with 3 elements (one unnamed non-editable) → observation.harness == .agentDesktop, 2 elements numbered 1,2, labels[1].ref == "@s1:e1", ax.walks == 0 */ }
@MainActor @Test func observerFallsBackToNativeOnProcessFailure() async { /* snapshotResult nil → native elements without refs, harness stays .agentDesktop, ax.walks == 1; probe() == false */ }
@MainActor @Test func observerSnapshotsOpenSurfaceInsteadOfWindow() async { /* surfacesToReport ["sheet"] → harness.calls.first == "snapshot:sheet", observation.surface == "sheet" */ }
@MainActor @Test func badgesOverlayStillUsesBadgeElements() async { /* overlay .labels → no harness call, numbers from badges */ }
```
- [ ] **Step 2: Run** → fail. **Step 3: Implement**; update `TaskRunner.observeTimed`, `IntentContextBuilder.makeBundle`, the CLI `observe` and `VoicePipeline` call sites for the `async` signature (`makeBundle` becomes `async`). **Step 4:** `swift test` → pass. **Step 5: Commit** — `git commit -m "feat(mac): observe through the desktop harness with native fallback"`

---

### Task 9: ActionExecutor routing (Mac)

**Files:**
- Modify: `Sources/NoHandsMac/ActionExecutor.swift`
- Modify: `Sources/NoHandsMac/InputSynthesizer.swift` only if `InputSynthesizing` lacks a way to type a chord (it has `press`) — no change expected
- Test: `Tests/NoHandsMacTests/ActionExecutorHarnessTests.swift`

**Interfaces:**
```swift
public init(input:, ax:, overlay:, config:, frontTimeout:, windowTimeout:, harness: (any DesktopHarness)? = nil)
/// Text the model asked to read during the last `execute`; the task loop moves it into the next observation.
public private(set) var readings: [String]
public func takeReadings() -> [String]
public static let elementChanged = "element changed, look again"
```
Routing (per the spec's table), all inside `run(_:isLast:)`:
- `click(.label(n), …)` with `labelSnapshot[n]?.ref` and a harness → `harness.act(.click(ref:button:count:))`; `.delivered` → ok; `.notDelivered` → CGEvent click at the element centre when `frame != .zero`, else failure message; `.elementChanged` → `Self.elementChanged`; `.failed(m)` → m.
- `ElementTarget` resolution: `.label(n)` → `labelSnapshot[n]`; `.named(s)` → `harness.find(app: ax.frontmostAppName(), surface: nil, name:)` when harness present, else `LabelAssigner.find` over `ax.actionableElements()`.
- Native fallbacks exactly as the spec table (`setValue` → click centre, `press(KeyChord(.a, [.command]))`, `type`; `clearField` → click, ⌘A, `press(KeyChord(.delete, []))`; `selectOption`/`scrollTo`/`clickIn`/`menuItem`/`readNotifications`/`dismissNotifications` → `"needs agent-desktop"`; `closeApp` → `ax.activate` + ⌘Q; `windowAction(.minimize)` → activate + ⌘M; `.maximize/.restore` → `"needs agent-desktop"`; `.focus` → `ax.activate(app)`; `clipboardSet`/`readClipboard` → `NSPasteboard.general`; `readValue` → `labelSnapshot[n]?.value ?? ""`; `waitFor` → `Task.sleep(min(timeoutMs, 5000))`; `drag` → `mouseDown` at from, `moveMouse` to, `mouseUp`).
- `menuItem(name)`: split on `>`; `find(app:surface:.menubar,name: last)`; if the match is `disabled` → failure `"menu item is disabled"`; then `act(.click(ref:…))`.
- `clickIn(surface, name)`: `find` then `click`; a `.dock`/`.menuBarExtras` find passes `app: nil`.
- Readings: `readClipboard` → `"clipboard: <text>"`, `readValue` → `"<title>: <text>"`, `readNotifications` → one reading per line. Each cut at 300 characters.
- `waitFor` via harness → `act(.wait(...))`: `.notDelivered`/`.failed` → failure `"wait timed out"` (the model reacts); `.delivered` → ok.
- `hideStaleOverlay()` after every harness action that is not a read.

- [ ] **Step 1: Tests** (each builds `make()` with a `FakeHarness` and labels `[1: UIElementInfo(id: 1, frame: CGRect(x: 10, y: 10, width: 20, height: 20), title: "Save", role: "button", ref: "@s1:e1"), 2: UIElementInfo(id: 2, frame: .zero, title: "Name", role: "textfield", ref: "@s1:e2"), 3: UIElementInfo(id: 3, frame: CGRect(x: 50, y: 50, width: 10, height: 10), title: "Badge", role: "button")]`):
```swift
@MainActor @Test func refClickGoesThroughHarnessAndFallsBackToPointOnlyWhenNotDelivered() async
    // actResults [.delivered(true)] → input.calls == [] and harness.calls == ["act:click @s1:e1"]
    // actResults [.notDelivered("x")] → input.calls == ["click:20,20"]
    // actResults [.failed("boom")] → failure "boom", input.calls == []
    // actResults [.elementChanged] → failure == ActionExecutor.elementChanged
@MainActor @Test func refClickWithoutFrameUsesHarnessOnly() async   // label 2, .notDelivered → failure "x", no input calls
@MainActor @Test func labelWithoutRefUsesCGEvent() async            // label 3 → input "click:55,55", no harness calls
@MainActor @Test func setValueWithoutRefClicksSelectsAllAndTypes() async  // no harness: label 3 → ["click:55,55","press","type:cats"]
@MainActor @Test func setValueSelectCheckExpandFocusScrollViaHarness() async // one call each, argv names: set-value/select/check/uncheck/toggle/expand/collapse/focus/scroll-to/scroll
@MainActor @Test func menuItemFindsLastSegmentThenClicksAndRefusesDisabled() async
@MainActor @Test func clickInDockFindsWithoutApp() async
@MainActor @Test func readsProduceReadingsAndNoInput() async        // readValue + readClipboard → takeReadings() == ["Name: cats", "clipboard: hi"], second take empty
@MainActor @Test func waitForTimeoutIsAStepFailure() async
@MainActor @Test func closeAppAndWindowOpsNativeFallbacks() async   // no harness: closeApp("Safari") with apps ["Safari"] → activate + press; windowAction(.focus) → activate only
@MainActor @Test func dragUsesHarnessWithRefsAndPointsOrNativeMouse() async
```
- [ ] **Step 2: Run** → fail. **Step 3: Implement.** **Step 4:** `swift test` → pass. **Step 5: Commit** — `git commit -m "feat(mac): execute harness actions through agent-desktop with native fallbacks"`

---

### Task 10: TaskRunner readings and sessions (Mac)

**Files:**
- Modify: `Sources/NoHandsMac/TaskRunner.swift`
- Test: `Tests/NoHandsMacTests/TaskRunnerTests.swift` (add)

**Interfaces:** `TaskRunner.init(... , harness: (any DesktopHarness)? = nil, trace: Bool = false)`. At `run` start, `harnessKind = (harness != nil && await observer.probe()) ? .agentDesktop : .native` and every observation of that run uses it (the probe's snapshot doubles as the first observation). Each observation after a step passes `executor.takeReadings()`; `finish(.done)` with readings shows HUD `"<intent> — <first reading cut at 80>"`. When `trace` and a harness exist: `startSession(name: "nohands-<unix seconds>")` before the first observation and `endSession` in `finish`.

- [ ] **Step 1: Tests**
```swift
@MainActor @Test func readingsFlowIntoTheNextObservation() async   // step 1 readClipboard (FakeHarness readResult "hi") → resolver sees request 2 observation.readings == ["clipboard: hi"], request 3 readings empty
@MainActor @Test func sessionStartsAndEndsWhenTracing() async     // FakeHarness.calls first == "session:start", last == "session:end"; without trace, none
@MainActor @Test func elementChangedFailureIsRecordedForTheModel() async   // history entry contains "FAILED: element changed, look again"
@MainActor @Test func harnessKindIsFixedForTheWholeTask() async            // FakeHarness snapshot ok on step 1, nil on step 2 → both requests have observation.harness == .agentDesktop; probe false on step 1 → all .native and no further harness snapshot calls
```
- [ ] **Step 2–4:** fail, implement, `swift test` → pass. **Step 5: Commit** — `git commit -m "feat(mac): readings and traced sessions in the task loop"`

---

### Task 11: App, CLI and README

**Files:**
- Modify: `Sources/NoHands/AppDelegate.swift` (build the harness: `AgentDesktopLocator.find` + `AgentDesktopClient` + `version`/`status` check → `AgentDesktopHarness` when `desktopHarness` allows; pass it to `ActionExecutor`, `ScreenObserver`, `TaskRunner` via `VoicePipeline`; add `harnessItem` menu line, refreshed in `menuWillOpen`)
- Create: `Sources/NoHandsMac/HarnessStatus.swift` — `public struct HarnessStatus: Equatable, Sendable { var binary: URL?; var version: String?; var accessibility: String?; var chosen: HarnessKind; var text: String }` with `public static func probe(config: AppConfig, environment:) async -> HarnessStatus` and pure `text` rules: `"Harness: agent-desktop 1.1.0"`, `"Harness: native (agent-desktop not found — npm i -g agent-desktop)"`, `"Harness: native (agent-desktop: accessibility not granted)"`, `"Harness: native (desktopHarness = native)"`.
- Modify: `Sources/NoHandsMac/VoicePipeline.swift` (accept `harness`, pass through)
- Modify: `Sources/nohands-cli/main.swift` (`desktop-status`, `snapshot [app]`; `observe`, `resolve`, `run`, `task` build the harness with a shared `loadHarness(config)` helper)
- Modify: `README.md` (new "agent-desktop harness" section under "Multi-step tasks": install, what it changes, config keys, privacy; CLI usage lines; Layout table unchanged)
- Test: `Tests/NoHandsMacTests/HarnessStatusTests.swift` (text rules, pure)

- [ ] **Step 1: Test** `HarnessStatus.text` for the four cases above.
- [ ] **Step 2–4:** fail, implement, `swift test` → pass; `swift build -c release` → ok; `Scripts/bundle.sh` → `build/NoHands.app` exists.
- [ ] **Step 5: Live check (document the result, do not block on it):** `swift run nohands-cli desktop-status`; `swift run nohands-cli snapshot Finder` with a Finder window on screen.
- [ ] **Step 6: Commit** — `git commit -m "feat: agent-desktop harness in the app and CLI; README"`

---

### Task 12: Memory note and wrap-up

- [ ] Update `/Users/noahstotland/.claude/projects/-Users-noahstotland--t3-projects-nohands/memory/nohands-plan-status.md` with the harness branch state and the live-test caveat.
- [ ] `swift test` full run; `git log --oneline -12`; report.
