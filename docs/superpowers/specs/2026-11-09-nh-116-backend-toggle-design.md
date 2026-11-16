# NH-116: Menu toggle between Claude and the local model: Design

**Date:** 2026-11-09  **Ticket:** [NH-116](https://github.com/noahstotland/nohands/issues/116)
**Status:** Shipped
**Shipped:** in PR #117, as specified

## Intent

Switching backends used to mean editing `intentBackend` in `config.json` and restarting. A menu choice replaces that: one pick, saved to the config, in effect for the next command with no restart. The care point is replacing the task runner while the pipeline is live without losing a spoken "stop".

## Non-goals and anti-goals

- Not here: a menu choice for `auto` or `off`, switching mid-task, changing the local model or Ollama URL, applying a newly saved API key without a restart.
- Failure means: "stop" cancels the wrong runner; a switch loses other `config.json` keys or widens permissions; the menu says one backend while commands go to the other; any new path to Ollama off loopback, or text sent to Claude the user did not choose.

## What the code forces

- The runner and its `ScreenObserver` fix the element cap (120 Claude, 40 local) and vision (Claude only), so the whole runner changes, not just the resolver.
- Only `runner?.cancel()` ends a pending screen-capture wait, so the running runner must stay in `runner` until its task ends.
- `runner` can be nil at launch, so it becomes a `var`. A switch during startup, before `pipeline` is set, would be lost.
- Ollama logs only plans, so the ticket's log check needs a per-step line.
- `saveAnthropicKey` always leaves mode 600, but a switch must keep the file's mode.

## Approach

Chosen: replace the whole runner, deferred until no task is running. Cap, vision and deadlines follow the backend, the microphone never stops, and stop works.

Rejected: rebuilding the pipeline (cuts the microphone, cancels a running task).

## How it works

- **Patch (`BackendMenu`, Core):** `merged(existing:choice:)` sets `intentBackend` and nothing else, with the same parse and serialize rules as `ClaudeKeyEntry.merged` (non-object JSON throws; sorted, pretty-printed).
- **Menu:** top item `Model: Claude|Local|Off` from `effectiveBackend`, so `auto` shows what it resolved to. Rows `Claude` and `Local model`, checkmark on the effective one, none when `off`. Claude is disabled with no key (the row says to set one, or to restart if saved this session).
- **Write (`ConfigFile.saveIntentBackend`):** same steps and errors as `saveAnthropicKey` (private folder, refuse symlinks, temp file and rename, nothing changed on failure). An existing file keeps its permission bits; a new file is 600.
- **Live swap (`VoicePipeline`):** `switchBackend` builds a runner as `init` does. With no active task it applies at once; otherwise it waits in `pendingRunner` (newest wins) and applies right after the running task returns. A held command goes to the new backend.
- **Pick (`AppDelegate`):**
  1. Already effective: do nothing, so `auto` is not turned into a fixed value.
  2. Save; on failure show a HUD error and stay on the old backend.
  3. Set `config.intentBackend`, clear `lastClaudeCheck` (and `lastWarm` on local).
  4. `switchBackend` if a pipeline exists; otherwise startup applies it after `pipeline = p`.
  5. Log `intent backend: <name>`, refresh, show `Using Claude from the next command` or the local equivalent.
- **Also:** `warmIfDue` is local-only; `OllamaIntentResolver` logs `ollama: step <n> <ms>ms` (no prompt or transcript); README covers the submenu and that `auto` and `off` stay file-only.

## Tests

- Table tests for `merged`, title and rows, `ConfigFile` in a temp folder (mode kept, symlinks refused, invalid JSON untouched), and `VoicePipeline` with injected runners (idle swap, swap from no runner, mid-task swap keeps stop working and routes the held command to the new runner).
- Manual, in the PR: switch each way live, quit and reopen, bad config files, local with Ollama stopped starts it.

## Calls I made

1. Switching out of `off` is allowed; going back to `off` means editing the file.
2. A running task finishes on the old backend; the HUD says "from the next command".
3. A key saved this session does not enable Claude until a restart.
4. An existing file's mode is kept exactly, even 644, as the ticket says. The folder is still made private (700).
5. Only `intentBackend` applies live, and a switch rewrites `config.json` sorted and pretty-printed.
