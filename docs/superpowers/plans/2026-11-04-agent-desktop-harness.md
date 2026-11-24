# agent-desktop Harness Implementation Plan

**Goal:** Make agent-desktop the task loop's observation and action backend, widen the model's action vocabulary to agent-desktop's command surface, and keep the native path as the fallback.

**Architecture:** `NoHandsCore` builds agent-desktop argv (`DesktopCommand`), decodes its JSON envelopes (`DesktopEnvelope`) and flattens snapshots (`DesktopSnapshot`); `Action`, the schema, the decoder and the prompt grow new kinds. `NoHandsMac` runs the binary (`AgentDesktopClient`), wraps it behind a `DesktopHarness` protocol, and routes `ScreenObserver` and `ActionExecutor` through it with per-call native fallback. The app and CLI locate the binary and report status. Stack: agent-desktop CLI 1.1.0 (envelope `"version":"2.6"`).

**Spec:** `docs/superpowers/specs/2026-11-04-agent-desktop-harness-design.md`

## Global Constraints

- No new SwiftPM dependencies: agent-desktop is an external binary found at runtime.
- NoHands.app is launched with `open`, so PATH is `/usr/bin:/bin:/usr/sbin:/sbin`. The binary is located in this order: config path, `$AGENT_DESKTOP_BIN`, `/opt/homebrew/bin`, `/usr/local/bin`, `~/.bun/bin`, `~/.volta/bin`, `~/.npm-global/bin`, `~/.local/bin`, `~/.nvm/versions/node/*/bin` newest first, then PATH.
- Never block the main actor on the child process; every harness call is `async` and killed on cancellation.
- `--headed` only on the fallback path after `delivery == "not_delivered"`; `--force` never.
- The native prompt stays byte-identical; harness rules are appended only when the observation's `harness == .agentDesktop`.
- agent-desktop 1.1.0 has no `--stdin`: text goes in argv.
- The harness kind is chosen once per task and never flips mid-task.
- Config keys: `desktopHarness` `auto` (`auto`/`agentDesktop`/`native`; unknown becomes `auto`), `agentDesktopPath` nil, `agentDesktopTimeoutMs` 8000 (1000...60000, clamped), `agentDesktopSnapshotMs` 3000 (500...10000), `agentDesktopHeadedFallback` true, `agentDesktopTrace` false.

## Review Focus

1. A snapshot without `bounds`: elements still list and a ref click works; only the CGEvent fallback is unavailable.
2. The binary disappears or hangs mid-task: the step fails with a plain message, the task continues on native, "stop" still works.
3. `AMBIGUOUS_TARGET` with no focused candidate: the first visible candidate is used.
4. `set_value` on a badge-overlay label (no ref): native fallback clicks, selects all and types.
5. `close_app` for an app the goal never asked to quit is blocked and reported to the model.

## Tasks

Each task ends with `swift test` green and one conventional commit.

### Task 1: Envelope decoder and command builder (Core)

`DesktopEnvelope.swift`, `DesktopCommand.swift`.

- `DesktopEnvelope` carries `ok`, `command`, `data`, `error` (`code`, `message`, `disposition`, window `candidates`), `disposition` and `surfaces`. `decode` returns nil on malformed JSON. Synthetic `PROCESS_FAILED` and `TIMEOUT` envelopes are `not_delivered`/`safe` for observations, else `unknown`/`unsafe`.
- Enums: `DesktopSurface` (menubar, menu, sheet, alert, popover, dock, menu_bar_extras), `DesktopWindowOp`, `DesktopWaitKind`, `DesktopEvent`, with hyphenated CLI names.
- `DesktopCommand` has one case per agent-desktop command. `isObservation` covers snapshot, find, list, get, clipboard-get, notifications, version, status. `needsHeaded` covers drag, click count > 1 and the notification commands. `argv(headed:session:)` is optional `--headed`, optional `--session`, command, flags. Snapshot argv is `snapshot --app X -i --compact --include-bounds --max-depth 25 --timeout-ms N`. `drag` always emits `--headed`.
- Tests cover envelope decoding, argv and observation classification.

### Task 2: Snapshot flattening and element model (Core)

`DesktopSnapshot.swift`; `UIElementInfo` gains `ref`, `value`, `states` and `ObservedElement` gains `value`, `states` (old initialisers stay valid); fixtures from a real Finder menubar envelope (294 elements) and a trimmed Claude-app snapshot.

- Elements are flattened depth-first with `ref_id` as `ref` and `bounds` as frame (zero when absent). `listable` keeps elements with a ref and a non-blank title, a value, or an editable role (textfield, textarea, searchfield, combobox).
- `DesktopFindMatch` parses `data.match`.

### Task 3: Observation and request text (Core)

`ScreenObservation` gains `harness`, `surface`, `windows`, `readings`. The request adds `Harness: agent-desktop`, then only when set a `Surface:` line, quoted `Windows:`, element lines with value and states (`2 [textfield] Name = "cats"`, `1 [button] Save (disabled)`), and `Read:` lines. State order: checked, selected, expanded, collapsed, disabled, focused, offscreen. Values are cut at 60 characters, readings at 300. `Settle.same` also compares surface and value, not refs or numbers. Native text changes only to `Harness: native`.

### Task 4: New actions, summary, guard (Core)

- `ElementTarget` is a label number or a name; `WaitCondition` is text, window, event, menu, menuClosed or element with a predicate.
- New `Action` cases cover the kinds listed in Task 5.
- `ActionSummary` carries no names, titles or text, only lengths or the surface, op or wait kind.
- `ShortcutGuard` blocks `close_app` unless the goal has quit, exit, shut or close (any form), with `blocked: close_app not allowed for this request`. `windowAction` is never blocked.

### Task 5: Schema, prompt, decoder, examples (Core)

- New kinds: `set_value`, `type_into`, `clear`, `select`, `check`, `uncheck`, `toggle`, `expand`, `collapse`, `focus`, `scroll_to`, `scroll_element`, `drag`, `click_in`, `menu_item`, `close_app`, `window`, `clipboard_set`, `read_clipboard`, `read_value`, `read_notifications`, `dismiss_notifications`. New properties: `value`, `option`, `surface`, `window_action`, `title`, `wait_for`, `event`, `predicate`, `timeout_ms`, `from_number`, `from_name`, `from_x`, `from_y`. The schema stays closed.
- `systemPrompt(for:)` appends `harnessRules` for agent-desktop: one line per kind with its fields; prefer `set_value` over click-and-type, `check`/`uncheck` over `toggle`, `menu_item` ("File > Save As...") over shortcuts; `close_app` only when asked; `wait` with `wait_for` (`timeout_ms` 500-30000; element predicates exists, enabled, visible, actionable). Closing rules: a `Surface:` line means a menu, sheet, alert or popover is open, so act on it first; `FAILED: element changed, look again` means choose again, never repeat the old number; values after "=" are current text; `Read:` lines are last step's results.
- Decoder: elements by `target_kind` `label` or `element`; `check`, `uncheck`, `toggle` map to `setChecked` true, false, nil. `wait` with `wait_for` clamps `timeout_ms ?? 5000` to 500...30000; element waits need `target_number` and default the predicate to `exists`. `drag` sources from `from_number`, `from_name` or `from_x/from_y`. Missing required fields drop the action (fail closed). An empty `set_value` becomes `.clearField`.
- `IntentExamples.harnessTurns` adds two examples (`menu_item` to save as a new file in TextEdit; `set_value` plus `click` to search for cats).

### Task 6: Config keys, locator and process runner (Mac)

- `AgentDesktopLocator.find` returns the first executable candidate in the order above (`home` and `environment` injected for tests).
- `AgentDesktopClient.run` runs off the main actor with stdin `/dev/null`, kills the child at the deadline (`TIMEOUT`) or on cancellation (`CANCELLED`), and returns a decodable envelope even on a non-zero exit (agent-desktop exits 1 on structured errors). A missing binary or bad output is `PROCESS_FAILED`.
- Tests use a shell script as the fake binary.

### Task 7: Harness protocol and AgentDesktopHarness (Mac)

- `HarnessActionResult`: `delivered(verified:)`, `notDelivered` (safe to fall back), `failed` (may have landed, final), `elementChanged` (`STALE_REF`, `AMBIGUOUS_TARGET`, `SNAPSHOT_NOT_FOUND`, `ELEMENT_NOT_FOUND`).
- `DesktopHarness` offers `snapshot`, `find` (exact, then contains), `act` (retries once with `--headed` when `notDelivered` and the fallback is on; records `data.surfaces`), `read`, `listWindows`, `takeOpenSurfaces`, and sessions (`--session` on every call once set).
- On `AMBIGUOUS_TARGET` a snapshot retries with the focused candidate's `--window-id`, else the first visible. Snapshot deadline is `timeoutMs + 1500` ms. A `delivered_unverified` failure is `.failed`, not retried.

### Task 8: ScreenObserver through the harness (Mac)

- `observe` is now `async`. With a harness, kind `.agentDesktop` and an overlay other than `.labels`, it snapshots the open surface (menu, sheet, alert, popover) if any, else the window. A nil snapshot falls back to the native walk with `harness` still `.agentDesktop`. Elements are filtered by `listable`, capped at `maxElements`, and `labels[n]` keeps the `ref`.
- `probe() async -> Bool` lets `TaskRunner` choose the kind at task start.

### Task 9: ActionExecutor routing (Mac)

- A label click with a ref goes to the harness: `.delivered` is ok; `.notDelivered` falls back to a CGEvent click at the element centre when the frame is non-zero, else fails; `.elementChanged` reports `element changed, look again`; `.failed` reports its message. Labels without a ref use CGEvent.
- Named targets resolve via `harness.find`, else `LabelAssigner.find`.
- Native fallbacks: `setValue` and `clearField` click, select all, then type or delete; `closeApp` activate and command-Q; minimize and focus via activate; clipboard via `NSPasteboard`; `drag` via mouse down, move, up. `selectOption`, `scrollTo`, `clickIn`, `menuItem`, notifications, maximize and restore fail with `needs agent-desktop`.
- `menuItem` splits on `>`, finds the last segment on the menubar surface, and fails with `menu item is disabled` if disabled. Readings (`clipboard: <text>`, `<title>: <text>`) are cut at 300 characters. A failed harness `waitFor` is the step failure `wait timed out`.

### Task 10: TaskRunner readings and sessions (Mac)

- At `run` start the kind is `.agentDesktop` only if a harness exists and `probe()` succeeds; the probe's snapshot doubles as the first observation.
- Readings from `executor.takeReadings()` reach only the next observation. A `done` with readings shows the intent and the first reading cut at 80 characters.
- With `trace`, a session `nohands-<unix seconds>` starts before the first observation and ends in `finish`.

### Task 11: App, CLI and README

- `AppDelegate` builds the harness when `desktopHarness` allows and adds a menu line refreshed in `menuWillOpen`. `HarnessStatus.text` is one of `Harness: agent-desktop 1.1.0`, `Harness: native (agent-desktop not found, npm i -g agent-desktop)`, `Harness: native (agent-desktop: accessibility not granted)`, `Harness: native (desktopHarness = native)`.
- CLI: new `desktop-status` and `snapshot [app]`; `observe`, `resolve`, `run`, `task` share `loadHarness(config)`.
- README gets an "agent-desktop harness" section under "Multi-step tasks": install, what it changes, config keys, privacy.
- Verify with `swift build -c release` and `Scripts/bundle.sh`. A live check of `desktop-status` and `snapshot Finder` is documented, not blocking.
