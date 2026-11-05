# NoHands × agent-desktop: Desktop Harness — Design

**Date:** 2026-11-04  **Status:** approved by the builder's calls (the session ran autonomously; the user's brief was "integrate with agent-desktop so the app has a comprehensive harness"). Decisions marked *(call)* are the builder's and are the ones most worth challenging. Base branch: `fix/local-model-timeout` (commit 98fb068), which already has `open_url`, `move_window` and the local-model deadline keys this design refers to.

## Intent

NoHands drives the Mac from a spoken goal through an observe → act → settle loop (`TaskRunner`). Today the loop sees the screen through a hand-rolled accessibility walk (`AXQuery`: 17 actionable roles, a 150 ms–1 s budget, frames and titles only) and acts through synthesized CGEvents (click at a point, type, press). That gives the model a thin vocabulary: click a numbered element, type, press keys, open an app or URL, move a window. Everything else — set a field's value, pick a dropdown option, check a box, expand a tree, run a menu item by name, click a Dock item, answer a sheet, wait for a window or text to appear, read the clipboard — is either impossible or a fragile chain of clicks and keystrokes executed blind.

[agent-desktop](https://github.com/vercel-labs/agent-desktop) (Vercel Labs, Apache-2.0, Rust, v1.1.0 installed on this Mac) is a computer-use tool built for exactly this loop: it snapshots an app's accessibility tree as JSON with stable qualified refs (`@s8f3k2p9:e5`), acts on refs semantically (AX press, set-value, select, check, expand, scroll-to, focus) with physical delivery as an explicit fallback, reports what it verified (`disposition.delivery`, `post_state`, `surfaces`), and covers the rest of the desktop: launch and close apps, windows, menus and surfaces (menubar, menu, sheet, alert, popover, dock, menu-bar-extras), notifications, clipboard, typed waits (element, text, window, menu, lifecycle event) and batches. "The loop lives in your agent; agent-desktop has no model inside."

This design makes NoHands that agent: agent-desktop becomes the task loop's observation and action backend, the model's action vocabulary grows to cover agent-desktop's command surface, and the loop verifies through agent-desktop's dispositions instead of acting blind. The existing native path stays as the fallback (and as the fast path for grammar commands), so NoHands keeps working with no agent-desktop installed.

## Goals / non-goals / anti-goals

- **Goals**
  - The model can do what agent-desktop can do, in one schema that both backends (Claude, Ollama) share: semantic element actions, menus and surfaces by name, app and window lifecycle, clipboard, notifications, typed waits, drag.
  - Observations come from agent-desktop snapshots (refs, roles, names, values, states), with the open overlay surface (menu, sheet, alert, popover) when one is up, and readings the model asked for (an element value, the clipboard, notifications).
  - Actions on a visible element go through its ref (semantic first, physical fallback only when nothing was delivered), so a click lands on the element, not on a point that has since moved.
  - Graceful degradation: no agent-desktop binary, no permission, or a window agent-desktop cannot read → the native `AXQuery`/CGEvent path, with the same loop and the same HUD.
  - The grammar fast path and dictation are untouched: "click 12", "type hello", "press command s" still cost no process spawn.
  - Diagnostics: a CLI command to print the harness observation, the harness status in the menu, and optional agent-desktop sessions with traces per task.
- **Non-goals (this pass)**
  - Linking the agent-desktop C FFI library or speaking its MCP server (see Approaches).
  - Replacing the number badges ("show numbers") or the grid with agent-desktop data; those stay on `AXQuery`.
  - Screenshots / vision. agent-desktop's `screenshot` exists but the model path is text-only today.
  - Windows / Linux.
- **Anti-goals**
  - Physical input used to "recover" from a headless failure that may have landed (double clicks, double submits). Physical fallback only after `not_delivered`.
  - A task that quits or closes something the user did not ask to quit or close (existing `ShortcutGuard` rule, extended to `close_app`).
  - Blocking the main actor on a child process (HUD freezes, "stop" ignored).

## Constraints

- Swift 6 strict concurrency; SwiftPM only; macOS 14+, Apple Silicon.
- agent-desktop is an external binary the user installs (`npm i -g agent-desktop` or `brew install agent-desktop`). NoHands.app is launched with `open`, so its PATH is `/usr/bin:/bin:/usr/sbin:/sbin`: the binary must be located explicitly. The npm package's `bin/agent-desktop` is a native arm64 Mach-O with its `agent-desktop-macos-helper-darwin-arm64` beside it, so it can be executed directly (no node). Homebrew installs to `/opt/homebrew/bin`.
- agent-desktop needs the Accessibility grant for the process that launches it: NoHands.app, which already has it. Screen Recording only for screenshots (unused).
- Measured on this Mac (M1 Pro): `version` 25 ms, `snapshot --app X -i --compact` 160–340 ms, `find --surface menubar` 235 ms, `list-windows` 175–700 ms, a 3-entry `batch` 590 ms. A per-call spawn is affordable inside the task loop (which already polls observations every 250 ms during settle) but not on the grammar fast path.
- Every agent-desktop response is one JSON envelope `{version:"2.6", ok, command, data | error{code, message, suggestion?, details?, disposition{delivery, retry}}}`. Exit codes 0/1/2.
- agent-desktop names a window by `--app <display name>`; several windows → `AMBIGUOUS_TARGET` with `details.candidates[{id, title, is_focused, visible}]` to retry with `--window-id`. A window that is off-screen, minimized, or on another Space → `ACTION_NOT_SUPPORTED` (`window_without_accessibility_element`); a locked screen → `WINDOW_NOT_FOUND`/`APP_NOT_FOUND`. These are the native-fallback triggers.
- Snapshot node: `{ref_id?, role, name?, value?, states?[], available_actions?[], bounds?{x,y,width,height}, native_id?, children?[], subtree_truncated?}`; top level `{app, snapshot_id, ref_count, complete, truncated?, nodes_observed?, window{id,title}?, tree}`. Bounds are screen coordinates with a top-left origin (same as NoHands' CG frames).
- Menu items: `find --surface menubar --name X --exact --first` returns `{match{ref_id, role, name, path[], states}, snapshot_id}`; disabled items carry `states:["disabled"]`.

## Approaches

1. **Shell out to the `agent-desktop` CLI, one JSON envelope per call** *(chosen)*. A small process runner with a deadline and cancellation; argv built from a typed `DesktopCommand`; envelope decoding and snapshot flattening are pure Swift and unit-tested against recorded output. The CLI is the documented, versioned surface (`"version":"2.6"` envelopes, `skills get` guidance compiled into the binary), `batch` amortizes spawns when it matters, and sessions/traces come for free. Cost: ~160–340 ms per call, a child process per action.
2. **Link `libagent_desktop_ffi.dylib`.** In-process, no spawn. Rejected for now: the C API is thinly documented (`ad_init`, `ad_adapter_create`, …), the dylib would have to be vendored or found at runtime and loaded with `dlopen`, SwiftPM has no clean story for a binary the user installs with npm, and a crash in the adapter takes the voice app down with it. The CLI runner is a seam: an FFI harness can conform to the same `DesktopHarness` protocol later.
3. **Speak MCP to `agent-desktop mcp` over stdio.** One long-lived child, JSON-RPC, tools named `desktop_<command>`. Same command set as the CLI with more plumbing (framing, a supervisor for the child, restart on crash), and NoHands does not use Claude tool-use anyway — both backends get a JSON schema and the Ollama path must stay constrained-decoding friendly. Rejected.
4. **Keep the native harness and only copy agent-desktop's ideas** (stable refs, semantic AX actions). Rejected: that is re-implementing a 15k-star tool's macOS adapter, and loses menus, surfaces, waits, notifications and the verification model.

## Design

### Vocabulary

- **Harness**: what the task loop observes and acts through. Two implementations: `native` (today's `AXQuery` + CGEvents) and `agentDesktop`.
- **Ref**: agent-desktop's qualified element id. NoHands keeps numbering elements 1…N for the model (numbers are what the user can also say) and maps number → ref at execution time, exactly as `.label(n)` maps to a frame today.
- **Reading**: text the model asked for in the previous step (an element's value, the clipboard, the notification list), delivered in the next observation.

### Layers

```
NoHandsCore (pure, tested)
  DesktopCommand        typed command → argv (and --session/--headed/--timeout-ms flags)
  DesktopEnvelope       JSON envelope decoder: ok/data/error, disposition, surfaces, candidates
  DesktopSnapshot       tree → flat numbered elements (ref, role, name, value, states, frame)
  Action (+ new cases)  IntentSchema / IntentDecoder / ActionSummary / ShortcutGuard / prompt
NoHandsMac
  AgentDesktopLocator   finds the binary (config path, env, brew, npm/nvm, PATH)
  AgentDesktopClient    runs argv with a deadline; cancellation kills the child
  DesktopHarness        protocol: snapshot / find / act / read; AgentDesktopHarness conforms
  ScreenObserver        elements from the harness when it has them, else AXQuery
  ActionExecutor        routes ref-bearing and harness-only actions; physical fallback
  TaskRunner            optional session per task; readings and surfaces flow into observations
NoHands / nohands-cli   menu status line; `desktop-status`, `snapshot`; `observe`/`task` use the harness
```

### Locating and checking the binary

`AgentDesktopLocator.find(config:environment:)` returns the first executable among: `config.agentDesktopPath`; `$AGENT_DESKTOP_BIN`; `/opt/homebrew/bin`, `/usr/local/bin`, `~/.bun/bin`, `~/.volta/bin`, `~/.npm-global/bin`, `~/.local/bin`, every `~/.nvm/versions/node/*/bin` (newest version first); then each `PATH` entry. At startup (and on `nohands-cli desktop-status`) the app runs `version` and `status` once: the menu shows `Harness: agent-desktop 1.1.0` or `Harness: native (agent-desktop not found)` / `(accessibility not granted to NoHands)`. `desktopHarness: auto` picks agent-desktop when both checks pass. The check is repeated when the menu is opened, so installing agent-desktop needs no restart. *(call)*

### Process runner

`AgentDesktopClient.run(_ argv: [String], deadline: Duration) async -> DesktopEnvelope`: spawns the binary via `Process` off the main actor, captures stdout, kills the child at the deadline (`TIMEOUT` envelope synthesized with `not_delivered`/`retry: safe` semantics only when the command is an observation; an action that timed out is reported `delivery: unknown`, `retry: unsafe`), and kills it on task cancellation. stdin is `/dev/null`. agent-desktop 1.1.0 has no `--stdin`: text for `type`, `set-value`, `select` and `clipboard-set` is passed in argv, so it is visible to `ps` for the life of the child (~200 ms); the README says so. Environment: inherit, plus `AGENT_DESKTOP_SESSION` when a session is active. Default deadline `agentDesktopTimeoutMs` (8000). Snapshots pass a fixed `--timeout-ms` of 3000 (`agentDesktopSnapshotMs`, 500…10000), never one derived from the remaining settle budget: the last observation of a settle is the one the model sees, and it must not be the one most likely to time out.

### Observation

`ScreenObserver.observe` with an agent-desktop harness:

1. `app` and `windowTitle`, `url` as today (NSWorkspace / `AXQuery`): cheap and reliable, and `AXQuery.webURL` keeps the Chromium exposure trick.
2. `snapshot --app <app> -i --compact --include-bounds --max-depth 25 --timeout-ms <agentDesktopSnapshotMs>`. On `AMBIGUOUS_TARGET`, retry with the `is_focused` candidate's `--window-id` (else the first visible). On any other error (`WINDOW_NOT_FOUND`, `ACTION_NOT_SUPPORTED`, `PERM_DENIED`, `TIMEOUT`, process failure) the observer falls back to the native walk for this observation (elements without refs). **The harness kind is chosen once per task**, at the first observation: if that snapshot succeeds the whole task is prompted as `Harness: agent-desktop`, otherwise as native. It never flips mid-task, because on the local backend a system-prompt change invalidates Ollama's prompt cache (a 3–20 s prefill on an M1 Pro) and the model's few-shot context would change under it. A mid-task native observation in an agent-desktop task simply lists elements without refs; a ref-only action on one of them fails with "needs agent-desktop" and the model reacts. *(call)*
3. If the previous step's action results listed open surfaces (`data.surfaces`), or the harness's last `list-surfaces` says a menu/sheet/alert/popover is open, snapshot that surface (`--surface sheet` etc.) and list its elements first, under a `Surface: sheet` line. While a surface is open the window elements behind it are the wrong target (agent-desktop rule), so the window list is omitted in that observation.
4. Flatten depth-first. An element is listed when it has a ref and (a name, or a value, or an editable role: textfield, textarea, searchfield, combobox). Numbering is depth-first order (what agent-desktop drills by), capped at `maxObservedElements` / `localMaxObservedElements`. Each `UIElementInfo` keeps `frame` (from bounds) so the grid, badges and CGEvent fallbacks still work, and gains `ref: String?`.
5. Prompt line per element: `12 [checkbox] Enable notifications (checked)`, `7 [textfield] Search = "cats"`, `3 [button] Save (disabled)`. States kept: checked, selected, disabled, expanded, collapsed, focused, offscreen. Values are sanitized and cut at 60 characters; secure fields show no value (agent-desktop redacts them). Values of listed elements go to the model every step, like titles do today: the model cannot choose between `set_value` and `type_into`, or see what it already typed, without them. The privacy section covers this.
6. `readings` from the previous step are appended as `Read: <label>: <text>` lines (each cut at 300 characters).
7. Other windows of the frontmost app (titles, from the `AMBIGUOUS_TARGET` candidates or a `list-windows --app` when the model asked to focus a window) are listed as `Windows: …` only when there are several. *(call: not every step, `list-windows` costs up to 700 ms.)*

`Settle.same` compares the element lists as today; refs are excluded from the comparison (a re-snapshot mints new ids).

### Actions

New `Action` cases (all target `ElementTarget`: `.label(n)` or `.named(name)` unless noted). Schema `kind` in parentheses.

| Action | agent-desktop | Native fallback |
|---|---|---|
| `setValue(target, text)` (`set_value`) | `set-value @ref <text>` | click centre, ⌘A, type |
| `typeInto(target, text)` (`type_into`) | `type @ref <text>` | click centre, type |
| `clearField(target)` (`clear`) | `clear @ref` | click centre, ⌘A, delete |
| `selectOption(target, option)` (`select`) | `select @ref <option>` | fails: "needs agent-desktop" |
| `setChecked(target, Bool?)` (`check` / `uncheck` / `toggle`) | `check` / `uncheck` / `toggle` | click centre |
| `setExpanded(target, Bool)` (`expand` / `collapse`) | `expand` / `collapse` | click centre |
| `focusElement(target)` (`focus`) | `focus @ref` | click centre |
| `scrollTo(target)` (`scroll_to`) | `scroll-to @ref` | fails |
| `scrollIn(target, direction, amount)` (`scroll_element`) | `scroll @ref --direction --amount` | move cursor to centre, wheel |
| `click(.label, …)` (existing) | `click` / `right-click` / `--headed double-click` on the ref | CGEvent at centre |
| `drag(from: MoveTarget, to: MoveTarget)` (`drag`) | `--headed drag --from/--to` (refs or `--from-xy/--to-xy`) | mouse down, move, up |
| `clickIn(surface, name)` (`click_in`) | `find --surface <s> --name --exact --first` (then non-exact) → `click` | fails |
| `menuItem(name)` (`menu_item`) | `clickIn(.menubar, name)`; `File > Save As…` matches the last segment and prefers a `path` containing the earlier ones | fails |
| `closeApp(name)` (`close_app`) | `close-app` | activate + ⌘Q |
| `windowAction(minimize/maximize/restore, app?)` (`window`) | `minimize` / `maximize` / `restore --app` | activate + ⌘M / zoom via AX |
| `focusWindow(app?, title?)` (`window`, `window_action: focus`) | `focus-window --app --title` | activate app |
| `clipboardSet(text)` (`clipboard_set`) | `clipboard-set <text>` | NSPasteboard |
| `readClipboard` (`read_clipboard`) | `clipboard-get` → reading | NSPasteboard |
| `readValue(target)` (`read_value`) | `get @ref --property value` (then `text`) → reading | AX value of the element |
| `readNotifications` (`read_notifications`) | `--headed list-notifications` → readings | fails |
| `dismissNotifications(app?)` (`dismiss_notifications`) | `--headed dismiss-all-notifications` | fails |
| `waitFor(condition, timeoutMs)` (`wait` with `wait_for`) | `wait --text / --window / --event / --menu / --menu-closed / --element @ref --predicate` | `wait(ms:)` of the timeout, capped at 5 s |

Existing kinds are unchanged in meaning. `open_app`, `open_url`, `move_window`, `press_key`, `type_text`, mouse and grid actions keep their native implementations (they are the grammar fast path and already wait for windows). `click` on a `.label` whose element has a ref goes through agent-desktop; a `.label` from the badge overlay (no ref) or a `.numbered` grid cell stays on CGEvents.

**Physical fallback rule.** A harness action that fails with `error.disposition.delivery == not_delivered` and a code in {`ACTION_NOT_SUPPORTED`, `POLICY_DENIED`, `ACTION_FAILED` with a `checks[]` report} is retried once with `--headed` when `agentDesktopHeadedFallback` is true (default). If that is also not delivered and the element has a frame, the native CGEvent fallback from the table runs. Any other delivery value is final: the executor reports the step as failed with agent-desktop's message and the model decides from the next observation. `STALE_REF`, `AMBIGUOUS_TARGET` and `SNAPSHOT_NOT_FOUND` are reported as `element changed, look again` so the model re-observes.

**Surfaces.** Every action result's `data.surfaces` is kept on the harness as `openSurfaces` for the next observation.

**Readings.** The executor appends to `readings` during a step; `TaskRunner` passes them into the next `StepRequest` and clears them. `done` with readings shows the first reading in the HUD after the intent. *(call)*

### Schema and prompt

`IntentSchema.kinds` gains the kinds above; new fields: `value` (string), `option` (string), `checked`/`expanded` (handled by kind), `surface` (enum: menubar, menu, sheet, alert, popover, dock, menu_bar_extras), `window_action` (enum: minimize, maximize, restore, focus), `title`, `wait_for` (enum: text, window, event, menu, menu_closed, element), `event` (enum: window_opened, window_closed, app_launched, app_terminated, focus_changed, surface_appeared, surface_dismissed), `timeout_ms`, `from_number`, `from_name`, `from_x`, `from_y` (drag source). Everything stays flat and `additionalProperties: false` so Ollama's constrained decoder keeps working.

`IntentSchema.systemPrompt(harness:)`: the harness-only kinds and their rules are included only when the task's harness is agent-desktop (`Harness: agent-desktop` line in every request of that task). The native prompt is byte-identical to today's. The agent-desktop prompt adds, condensed from `agent-desktop skills get desktop`: prefer `set_value` over clicking and typing; `check`/`uncheck` over `toggle`; `menu_item` over keyboard shortcuts for menu commands and over clicking through menus; answer an open `Surface:` first; use `wait` with `wait_for` instead of a fixed pause; a `FAILED: element changed` means look again, not retry; readings arrive in the next step.

The Ollama few-shot examples gain two harness turns (a menu item; a set_value then click) so the local model has seen the new kinds; the harness turns are only sent with the harness prompt, so the native message list is unchanged. The warm-up body uses the prompt of the harness the app chose at startup (`warmBody(harness:)`), so the first task after a warm-up pays no prefill on either path. *(call)*

### Safety

- `ShortcutGuard` also blocks `close_app` unless the goal contains quit/exit/shut/close (word forms as today), and `window` minimize needs no word (reversible).
- agent-desktop refuses dangerous combos itself; NoHands never passes `--force`.
- `--headed` is only ever added on the fallback path above; `readNotifications`/`dismissNotifications` need it by design and say so in the prompt.
- What leaves the machine on the Claude path grows from titles, roles, the window title and the URL to also include the current values of listed fields (what is typed in a search box or a form), cut at 60 characters. Clipboard text, a full element value and the notification list are sent only in the step after the model explicitly asked to read them. All of it is logged as `<private>`. Text passed to agent-desktop rides in argv for the life of the child process. Sessions' traces redact text fields (agent-desktop's rule); `agentDesktopTrace` is off by default.
- Step cap, repeat detection, stop phrase and the per-step deadline are unchanged. A harness call in flight is killed on stop.

### Configuration (new keys, all optional)

| Key | Default | Range |
|---|---|---|
| `desktopHarness` | `auto` | `auto` / `agentDesktop` / `native` |
| `agentDesktopPath` | nil | absolute path to the binary |
| `agentDesktopTimeoutMs` | 8000 | 1000…60000 |
| `agentDesktopSnapshotMs` | 3000 | 500…10000 |
| `agentDesktopHeadedFallback` | true | |
| `agentDesktopTrace` | false | session per task, `trace export` afterwards |

### CLI and menu

- `nohands-cli desktop-status`: binary path, version, permissions, chosen harness.
- `nohands-cli snapshot [app]`: prints the harness observation as the model sees it (3 s delay like `observe`).
- `nohands-cli observe`, `resolve`, `task`, `run`: use the configured harness.
- Menu: a `Harness: …` status line under the backend line.
- README: an "agent-desktop" section (install, what changes, config keys, privacy).

### Testing

- Core: `DesktopCommand` argv for every command; envelope decoding (ok, error with disposition and candidates, malformed); snapshot flattening against recorded fixtures (the Finder menubar envelope captured on 2026-11-04 and a window envelope trimmed from a real one; captured into `Tests/NoHandsCoreTests/Fixtures` as a plan task); decoder and schema round trips for every new kind; `ActionSummary` names; `ShortcutGuard` for `close_app`; prompt contains/omits harness rules by harness.
- Mac: `FakeHarness` returning canned envelopes; executor routing (ref → harness, no ref → CGEvent), headed fallback only on `not_delivered`, surfaces and readings flowing into the next observation; observer fallback to native on harness errors; locator with a temp directory tree; `TaskRunner` session start/end when tracing is on.
- Live (manual, documented): `nohands-cli snapshot` against TextEdit; `nohands-cli task "open a new TextEdit document and type hello"`; `task "save it as notes"` (menu + sheet).

## Left to the builder

Exact wording of the condensed harness rules; how many bytes of a value to show; whether `Windows:` lists ids; the HUD text for harness failures; `batch` use for `clickIn` (find + click in one spawn) — use it if it is simpler.
