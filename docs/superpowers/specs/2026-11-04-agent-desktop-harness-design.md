# NoHands × agent-desktop: Desktop Harness — Design

**Date:** 2026-11-04  **Status:** approved by the builder's calls (the session ran autonomously; the user's brief was "integrate with agent-desktop so the app has a comprehensive harness"). Decisions marked *(call)* are the builder's and are the ones most worth challenging. Base branch: `fix/local-model-timeout` (commit 98fb068), which already has `open_url`, `move_window` and the local-model deadline keys this design refers to.

## Intent

The task loop (`TaskRunner`: observe, act, settle) sees the screen through `AXQuery` (frames and titles only) and acts through CGEvents. Setting a field, picking an option, running a menu item by name or reading the clipboard is impossible or a blind click chain.

[agent-desktop](https://github.com/vercel-labs/agent-desktop) (Rust CLI, no model inside) snapshots an app's accessibility tree with stable refs, acts on refs semantically, falls back to physical delivery explicitly, and reports what it verified. It becomes the task loop's observation and action backend. The native path stays as the fallback and the grammar fast path, so NoHands works without it.

## Goals and limits

- One flat schema, shared by Claude and Ollama, covers what agent-desktop can do.
- Actions on a visible element go through its ref, not a point that may have moved.
- No binary, no permission or an unreadable window falls back to the native path.
- Non-goals: replacing number badges or the grid, screenshots, other platforms.
- Physical input only after `not_delivered`, never to recover from a failure that may have landed.
- Never close what the user did not ask to close. Never block the main actor on a child process.

## Constraints

- The user installs the binary (npm or brew); the app's minimal PATH means it is located explicitly.
- Measured on an M1 Pro: `version` 25 ms, snapshot 160 to 340 ms, `list-windows` 175 to 700 ms. A spawn per call is fine in the loop, not on the grammar fast path (which spawns none).
- Every response is one JSON envelope with `ok`, `data` or `error{code, disposition{delivery, retry}}`.
- Off-screen, minimized or other-Space windows return `ACTION_NOT_SUPPORTED`, and a locked screen `WINDOW_NOT_FOUND`. These trigger the native fallback.

## Approaches

- **Shell out to the CLI, one envelope per call** (chosen). Argv from a typed `DesktopCommand`, envelope decoding and snapshot flattening are pure Swift.
- Rejected: the FFI dylib (a crash takes the app down), MCP over stdio (more plumbing), copying the ideas natively (loses menus, waits and verification).

## Design

### Layers

`NoHandsCore` holds the pure parts (`DesktopCommand`, `DesktopEnvelope`, `DesktopSnapshot`, new `Action` cases). `NoHandsMac` holds `AgentDesktopClient`, the `DesktopHarness` protocol, `ScreenObserver` and `ActionExecutor`. Elements stay numbered 1..N; number maps to ref at execution time.

### Locating and running

- The binary is the first executable among `agentDesktopPath`, `$AGENT_DESKTOP_BIN`, the usual brew, npm and nvm bin directories, then `PATH`.
- At startup and on every menu open the app runs `version` and `status`. The menu shows `Harness: agent-desktop <version>` or `Harness: native (agent-desktop not found)` / `(accessibility not granted to NoHands)`. `auto` picks agent-desktop when both pass. *(call)*
- The runner is off the main actor and kills the child at the deadline (`agentDesktopTimeoutMs`) and on cancellation. A timed-out action is `delivery: unknown`, `retry: unsafe`.
- Typed text rides in argv, visible to `ps` for about 200 ms.
- Snapshots use a fixed `agentDesktopSnapshotMs`, never the remaining settle budget, so the last observation of a settle is not the likeliest to time out.

### Observation

- Snapshot depth is 25. On `AMBIGUOUS_TARGET` it retries with the focused window; on any other error that observation falls back to the native walk.
- **The harness kind is chosen once per task** and never flips: a prompt change would invalidate Ollama's prompt cache (3 to 20 s prefill). A native observation mid-task has no refs, and a ref-only action fails with "needs agent-desktop". *(call)*
- An open surface (menu, sheet, alert, popover) is listed first under `Surface: <kind>`; the window behind is omitted.
- An element is listed when it has a ref and a name, value or editable role. Numbering is depth-first, capped at `maxObservedElements` / `localMaxObservedElements`.
- Prompt lines look like `7 [textfield] Search = "cats"`, with states (checked, disabled, expanded, focused, offscreen and so on). Values are cut at 60 characters; secure fields show none. 
- Readings from the last step appear as `Read: <label>: <text>`, cut at 300 characters.
- `Settle.same` ignores refs (a re-snapshot mints new ids).

### Actions

- Element: `set_value`, `type_into`, `clear`, `select`, `check`/`uncheck`/`toggle`, `expand`/`collapse`, `focus`, `scroll_to`, `scroll_element`, `drag`. Fallback is click centre plus keys; `select` and `scroll_to` have none.
- `click_in` (a surface by name) and `menu_item` (menubar; `File > Save As…` matches the last segment and prefers a path containing the earlier ones). No fallback.
- `close_app`, `window`, `clipboard_set`, `read_clipboard`, `read_value`, `read_notifications`, `dismiss_notifications`.
- `wait` with `wait_for` and `timeout_ms`; fallback is a wait capped at 5 s.
- `open_app`, `open_url`, `move_window`, `press_key`, `type_text`, mouse and grid stay native. A `click` on a labelled element with a ref goes through agent-desktop; badge labels and grid cells stay on CGEvents.
- **Physical fallback.** A `not_delivered` failure (`ACTION_NOT_SUPPORTED`, `POLICY_DENIED`, or `ACTION_FAILED` with a checks report) retries once with `--headed` when `agentDesktopHeadedFallback` is on, then the native fallback if the element has a frame. Any other delivery value is final. `STALE_REF`, `AMBIGUOUS_TARGET` and `SNAPSHOT_NOT_FOUND` report "element changed, look again".
- Result `surfaces` and readings carry into the next observation. `done` with readings shows the first in the HUD. *(call)*

### Schema and prompt

- New flat fields (`value`, `option`, `surface`, `wait_for`, `timeout_ms`, `from_*` for drag and others) keep `additionalProperties: false`, so Ollama's constrained decoder works.
- Harness kinds and rules appear only when the task's harness is agent-desktop; the native prompt is byte-identical to before.
- Rules: prefer `set_value` and `menu_item` over clicking.
- Ollama few-shot gains two harness turns, sent only with the harness prompt. Warm-up uses the startup harness's prompt. *(call)*

### Safety

- `ShortcutGuard` blocks `close_app` unless the goal says quit, exit, shut or close. Minimize needs no word. NoHands never passes `--force`.
- On the Claude path, field values (60 characters) now leave the machine with titles and URL. Clipboard text, full values and notifications are sent only the step after the model asked. All is logged `<private>`.
- Step cap, repeat detection, stop phrase and deadline are unchanged. A harness call is killed on stop.

### Configuration

| Key | Default | Range |
|---|---|---|
| `desktopHarness` | `auto` | `auto` / `agentDesktop` / `native` |
| `agentDesktopPath` | nil | absolute path |
| `agentDesktopTimeoutMs` | 8000 | 1000…60000 |
| `agentDesktopSnapshotMs` | 3000 | 500…10000 |
| `agentDesktopHeadedFallback` | true | |
| `agentDesktopTrace` | false | session per task |

### CLI and testing

- `nohands-cli desktop-status` prints binary path, version, permissions and chosen harness. `snapshot [app]` prints the observation as the model sees it. `observe`, `resolve`, `task`, `run` use the configured harness.
- Tests cover argv, envelopes, snapshot flattening on recorded fixtures, schema round trips, prompt gating, and (fake harness) routing and headed fallback only on `not_delivered`.
