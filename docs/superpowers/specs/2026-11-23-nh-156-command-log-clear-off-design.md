# NH-156: Clear and off switch for the command log, and token sums that cannot trap: Design

**Date:** 2026-11-23  **Ticket:** [NH-156](https://github.com/noahstotland/nohands/issues/156)
**Status:** Shipped
**Shipped:** in PR #182, as specified

## Intent

The command log (NH-111) keeps the last 50 commands, with what was typed, in
`~/.config/nohands/command-log.json`, and the only way to get rid of it is to delete the file by hand. The user
should be able to clear it from the menu and turn it off. Separately, summing Claude token counts uses `+`, which
traps (crashes the app) if a server-reported count is near `Int.max`. Both came from the #111 security review.

## Goals, non-goals, anti-goals

Goals are the ticket's Scope and Acceptance.

Non-goals (ticket): search or export of the log, a size cap on reading the file. Also: a voice phrase for clearing
or turning off the log (see Calls I made), and changing how the log file is written.

Anti-goals, which would make this a failure even if it works:

- After "Clear Log", the file comes back holding the old entries because a write that was already queued lands
  after the delete.
- With the log off, a command is still added to memory, shown in Recent commands, or written to the file.
- Turning the log off deletes existing entries (the ticket says they stay until cleared).
- Any token sum, the per-command one or the session total, can still trap on overflow.

## What the code forces

- **`CommandLogStore`** (`Sources/NoHandsMac/CommandLogStore.swift`) is `@MainActor`, loads once, and writes each
  append from a detached task chained on `lastWrite`, so writes land in order. A clear has to join the same chain.
- **`AppDelegate`** owns the one store and passes it to the pipeline (`VoicePipeline` calls `commandLog?.append`).
  `onChange` already reloads an open View Logs window.
- **`CommandLog.Usage.sum`** (`Sources/NoHandsCore/CommandLog.swift`) and **`ClaudeUsageTotal.adding`** and its
  `menuLine` (`input + cacheWrite`) (`Sources/NoHandsCore/ClaudeUsage.swift`) are the only token sums.
  `ClaudeUsage.from` reads counts with `NSNumber.intValue`, so a huge server number becomes a huge `Int`.
- **Config toggles that change live** follow `speakFeedback`: a lenient decode in `AppConfig.init(from:)`, a
  `ConfigPatch.merged` helper in core, a `ConfigFile.save…` wrapper in `NoHandsMac`, and a menu item with a check
  mark. `ConfigPatch.merged` takes a `String` value today.

## Design

### Saturating token sums (core)

- Add `Int.saturatingAdd(_:)` (internal to `NoHandsCore`, or a small `TokenMath` enum): `addingReportingOverflow`,
  clamped to `Int.max` (or `Int.min` for a negative overflow).
- Use it in `CommandLog.Usage.sum`, `ClaudeUsageTotal.adding` (all four counts, and `calls`), and in `menuLine`'s
  `input + cacheWrite`.

### Config key (core)

- `AppConfig.commandLog: Bool = true`. Decoded leniently like `routeMemory`: missing or not a bool keeps `true`.
- `CommandLogMenu.merged(existing:on:)` in core writes `commandLog` as a JSON bool through `ConfigPatch`
  (widen `ConfigPatch.merged`'s value to accept a `Bool`; existing callers unchanged).

### Store (mac)

- `CommandLogStore.isRecording: Bool` (set from config at launch and by the menu). When false, `append` returns
  at once: nothing in memory, no `onChange`, no write.
- `CommandLogStore.clear()`: empties the in-memory log, calls `onChange`, and queues a delete of the file on the
  same `lastWrite` chain, so it runs after any write already queued and before any later one. A missing file is
  not an error; any other delete error is logged as a warning (fixed text plus the error) and never surfaces.
- `CommandLog` gets `mutating func removeAll()` (or the store just assigns `CommandLog()`).

### Menu (mac)

- In the Recent commands submenu, under the entries and a separator: **Clear Log** (disabled when the log is
  empty) and **Keep Command Log** (check mark on when `commandLog` is true).
- Clear Log calls `store.clear()`; the submenu rebuilds on next open and an open View Logs window reloads through
  `onChange` and shows "No commands yet".
- Keep Command Log flips `config.commandLog`, sets `store.isRecording`, and saves with
  `ConfigFile.saveCommandLog(_:at:)`. It takes effect at once, no restart. A failed save logs a warning, shows a
  short HUD line ("couldn't save the log setting: check config.json"), and leaves the in-memory setting as chosen
  for this session.
- With the log off and no entries, the empty line reads "Command log is off" instead of "No commands yet".

### Docs

- `docs/configuration.md`: a `commandLog` row (`true`; `false` records nothing, existing entries stay until
  cleared; changes live from the menu).
- `docs/privacy.md` § Command log: Clear Log in the Recent commands menu deletes the file; Keep Command Log or
  `commandLog` `false` stops recording.

## Tests (per `AGENTS.md` § Testing)

- One table test for saturating sums: `Usage.sum` and `ClaudeUsageTotal.adding`/`menuLine` with counts near
  `Int.max` give `Int.max` and do not trap; ordinary counts still add exactly.
- One table test for the `commandLog` key: missing → true, `false` → false, `"no"`/`1`/`null` → true, and the
  rest of the config still loads. Plus `CommandLogMenu.merged` keeps other keys and writes a JSON bool.
- No tests for the store or menu (need the app; manual checks in the PR): clear empties the window and removes the
  file; off records nothing and keeps old entries; on again records.

## Calls I made

- **Clear has no confirmation.** It is a menu click, not a voice command, the data is a 50-entry convenience log,
  and macOS menus with confirmations for this feel heavy. Undo is not offered either.
- **No voice phrase** for clearing or turning off the log. The ticket asks for a menu action; a new phrase would
  touch the grammar and the voice command table. Turning the log off holds no Accessibility state, so the
  "reversible by voice" product rule does not apply.
- **Both menu items live in the Recent commands submenu**, not the View Logs window, so no window layout changes.
  The ticket allows either.
- **The toggle applies live**, like `speakFeedback`, not after a restart like most keys.
- **Saturate, not wrap (`&+`).** A wrapped count would show as a negative number; clamping at `Int.max` keeps the
  display sane.
- **Clear deletes the file** rather than writing an empty one, as the ticket asks; the next recorded command
  creates it again.
- **Off also stops the in-memory list**, so Recent commands shows nothing new while off.

## Touches

None of: data migrations, money, auth, user email. It changes a local private file (deletes it on request).
