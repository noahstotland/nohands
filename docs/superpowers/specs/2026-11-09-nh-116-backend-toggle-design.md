# NH-116: Menu toggle between Claude and the local model: Design

**Date:** 2026-11-09  **Ticket:** [NH-116](https://github.com/noahstotland/nohands/issues/116)
**Status:** Shipped
**Shipped:** in PR #117, as specified

## Intent

Today, moving between Claude and the local model means editing `intentBackend` in `config.json` and restarting NoHands. A
menu choice replaces that: one pick, saved to the config, in effect for the next command with no restart.

This is a small change in surface (one submenu, one config write), with one part that needs care: replacing the task
runner while the pipeline is live, without ever losing a spoken "stop".

## Goals, non-goals, anti-goals

Goals are the ticket's Scope and Acceptance.

Non-goals, from the ticket: a menu choice for `auto` or `off`, switching in the middle of a running task, changing the
local model or the Ollama URL from the menu. Also not here: applying a newly saved API key without a restart (NH-94's
rule stays), and re-reading any other setting from `config.json` on a switch.

Anti-goals, which would make this a failure even if it works:

- A spoken "stop" that cancels the wrong runner, so a running task carries on after a switch.
- A switch that loses or corrupts anything else in `config.json`, or widens its permissions.
- The menu saying one backend while commands go to the other.
- Any new path that reaches Ollama off loopback, or sends text to Claude without the user having chosen or configured it.

## What the code forces

- **The resolver is not the only thing tied to the backend.** `VoicePipeline.init` builds one `TaskRunner` from the
  resolver, and the runner and its `ScreenObserver` also fix the element cap (`observedElementCap`: 120 for Claude, 40 for
  local) and whether screenshots are on (`visionEnabled`, Claude only). Swapping only the resolver would send the local
  model 120 elements, or leave Claude without vision. The whole runner has to change.
- **A plain swap breaks "stop".** `busy()` and `stop()` call `runner?.cancel()` on the current property. If `runner` changes
  while a task runs, stop cancels the new, idle runner. `activeTask?.cancel()` still reaches an in-flight model call, but
  only `TaskRunner.cancel()` ends a pending screen-capture wait, so a stop during one would be delayed. The running runner
  has to stay in `runner` until its task ends.
- **`runner` can be nil at launch** (`intentBackend` `off`, or `claude` with no key). Picking a backend from that state has to
  bring it to life, so it becomes a `var`.
- **There is a startup race.** `startPipelineIfReady` picks the resolver, then awaits `probeHarness()` and `p.start()` before
  it sets `pipeline`. A switch in that gap finds no pipeline to update and would be lost.
- **The Claude line can go stale.** `ClaudeStatus.menuLine` prefers `lastClaudeCheck` over the plain line, so after a switch to
  local it would still read `Claude: connected at 14:32`.
- **The log can't show the local backend yet.** `claude: step …` is logged per step, but Ollama logs only plans. The ticket's
  "check in the log" needs a matching step line.
- **`saveAnthropicKey` always leaves the file at mode 600** (a new `mkstemp` file renamed over it). The ticket says the switch
  keeps the file's permissions, so the shared writer needs to take a mode.

## Approaches

1. **Replace the whole runner, deferred until no task is running (chosen).** A few lines in `VoicePipeline`. Element cap, vision
   and deadlines all follow the backend, the microphone never stops, and a running task keeps its runner, so stop works.
2. **Stop and rebuild the whole pipeline with the same transcriber.** The least new logic, but it cuts the microphone during the
   switch, reloads the VAD, and cancels a running task, which the ticket rules out.
3. **A wrapper resolver that forwards to the current backend.** The runner stays put, so stop is safe, but the element cap and
   vision would need the same treatment separately, and a running task would change backend between steps.

## How it works

### Patch and menu logic (`BackendMenu`, NoHandsCore, Foundation only)

- `BackendChoice`: `claude`, `local`.
- `merged(existing: Data?, choice:) throws -> Data` sets `intentBackend` and nothing else, using the same parse and serialize
  rules as `ClaudeKeyEntry.merged` (nil means `{}`; anything that isn't a JSON object throws `invalidJSON`; sorted,
  pretty-printed, trailing newline). The two share one private helper.
- `title(config:)` is the top item: `Model: Claude`, `Model: Local` or `Model: Off`, from `effectiveBackend`, so `auto` shows
  what it resolved to.
- `rows(config:keySavedThisSession:)` returns each submenu row's title, checkmark and enabled flag.

| Row | When | Title | Enabled |
|---|---|---|---|
| Claude | a key is in effect | `Claude` | yes |
| Claude | no key in effect, none saved this session | `Claude (choose Set Claude API key… first)` | no |
| Claude | no key in effect, one saved this session | `Claude (restart NoHands to use the new key)` | no |
| Local | always | `Local model` | yes |

The checkmark follows `effectiveBackend`. With it `off`, neither row is checked.

### Write (`ConfigFile.saveIntentBackend(_:at:)`, NoHandsMac)

Same steps and the same `SaveError` as `saveAnthropicKey`: make the folder private (refusing a symlink), read with
`O_NOFOLLOW`, merge, then `mkstemp`, `fsync` and `rename`, with nothing changed on any failure. One difference: an existing file
keeps its mode (read from the `fstat` already done on the open file, permission bits only), applied with `fchmod` to the temp
file before the rename. A new file is mode 600. `saveAnthropicKey` keeps forcing 600.

### Live swap (`VoicePipeline`)

- `runner` becomes a `var`. The pipeline keeps `harness` from `init`.
- `switchBackend(config:resolver:observer:)` builds a `TaskRunner` the way `init` does (same executor and overlay; screenshots from
  the new config's `visionEnabled`) and passes it to `replaceRunner(_:)`, which is internal so tests can inject a runner.
- `replaceRunner`: with no `activeTask`, set `runner` at once. Otherwise store it in `pendingRunner` (a later switch replaces it).
- In `startTask`, the loop reads `self.runner` for each pending task, and calls `applyPendingRunner()` right after each `runTask`
  returns, when nothing is running. So a held command that follows the task goes to the new backend, and `runner?.cancel()`
  always hits the runner that is running.
- `config` stays a `let`. Its only backend use is the hint for a nil `runner`, and a switch never makes `runner` nil.

### App (`AppDelegate`)

- A `backendItem` with a submenu, built like `statusBarItem`, placed directly before `claudeKeyItem`. `refresh()` sets its title and
  rows. A disabled row has its action removed, since the menu autoenables items that have one.
- Keep the observer's AX query and the harness from pipeline start in properties, so a switch can build a new `ScreenObserver` with
  the new cap.
- A pick, in order:
  1. If the row is already the effective backend, do nothing. Clicking the checked row must not turn `auto` into a fixed value.
  2. `ConfigFile.saveIntentBackend`. On failure show the HUD below and stop, with the app still on the old backend.
  3. Set `config.intentBackend`. Clear `lastClaudeCheck`. On a switch to local, clear `lastWarm`, so it warms as at launch.
  4. If `pipeline` exists, build the resolver from one shared helper (also used by `startPipelineIfReady`) and call `switchBackend`.
  5. Log `intent backend: <name>`, `refresh()`, `refreshLocalModel()`, and show the HUD.
- `refreshLocalModel` already runs only for local, so Ollama check, one launch attempt and warm-up need no new code. A download in
  progress keeps going after a switch to Claude and is shown again on a switch back. `warmIfDue` gets a local-only guard, so a status
  check that lands after a switch away doesn't warm.
- Startup race: `startPipelineIfReady` remembers the backend it built with. Right after `pipeline = p`, if `config.effectiveBackend`
  differs, it calls `switchBackend`.
- `OllamaIntentResolver` logs `ollama: step <n> <ms>ms`, with no prompt or transcript text, matching Claude's line. Both backends log
  the backend name at pipeline start too.

| Result | HUD |
|---|---|
| Switched to Claude | `Using Claude from the next command` |
| Switched to local | `Using the local model from the next command` |
| Invalid JSON | `couldn't switch model: fix config.json, then try again` |
| Symlink | `couldn't switch model: replace the config.json link with a file` |
| Write failed | `couldn't switch model: check ~/.config/nohands` |

### Docs

`README.md`: "Backend choice" and § Configuration describe the Model submenu, that it applies with no restart, that it keeps every
other key but rewrites the file sorted and indented, and that `auto` and `off` stay file-only. "Changes apply after a restart" gets
this exception.

## Tests

- One table-driven test for `merged` in NoHandsCore: no file, `{}`, other keys kept with their types (a key, numbers, booleans), existing
  value replaced, invalid JSON, `[]`, empty file. Output loads through `AppConfig.load` to the chosen backend.
- One table-driven test for `title` and `rows`: every `intentBackend`, with and without a key, with and without a key saved this session.
- One table-driven test in `ConfigFileTests`, in a temp folder: new file is 600, 600 and 640 files keep their mode, the API key survives, a
  symlinked file or folder is refused with the target untouched, invalid JSON is left byte for byte, and no temp files are left.
- One table-driven test in `VoicePipelineTests` with injected runners and fakes (no permissions, no model): a swap when idle reaches the next
  command; a swap from no runner starts working; a swap during a task leaves that task on its runner, a spoken stop still cancels it, and a held
  command then goes to the new one.

Manual checks, listed in the PR:

- Switching each way in the running app, with no restart: the next unmatched command logs `claude: step` or `ollama: step`, and the Claude line and
  local model item match.
- Quit and reopen: the choice holds. `config.json` keeps its other keys and mode.
- A symlinked and an invalid `config.json` show the HUD and change nothing.
- `intentBackend` `off`: the grammar still works and unmatched commands show the same hint until a row is picked.
- Choosing the local model with Ollama stopped starts it, the same as a launch.

## Left to the builder

- Helper names and file placement beyond those above.
- Wording tweaks that stay on one line and keep the next step.

## Calls I made

1. **Switching out of `off` is allowed.** The ticket only says `off` keeps working. `Model: Off` shows, and picking a row turns the backend on and writes
   `claude` or `local`. Going back to `off` means editing the file. The other reading, locking the menu while `off`, makes the item useless for someone
   who set `claude` with no key and later added one.
2. **A task already running finishes on the old backend,** and the HUD says "from the next command". A command held behind that task goes to the new
   backend.
3. **It's a submenu with a checkmark, titled `Model: …`,** like Status Bar. That reads the current state and takes one pick. "Model" is the plain word; the
   existing `LLM` wording stays where it is.
4. **A key saved this session doesn't make Claude selectable until a restart,** and the row says so. NH-94's "applies after a restart" stays.
5. **An existing file's mode is kept exactly, even a loose one like 644,** as the ticket says. The existing launch warning still flags it. The key item still
   tightens to 600.
6. **The folder is still made private (700) on a switch,** like the key item, because it shares that step. Only the file's mode is kept.
7. **Clicking the row already in effect does nothing,** so `auto` stays `auto` until a real change.
8. **Only `intentBackend` is applied live.** Other edits to the file still wait for a restart, though a switch keeps them on disk.
9. **A switch rewrites `config.json` sorted and pretty-printed,** the same as the key item.
10. **A small logging addition,** `ollama: step`, because the ticket's log check has nothing to look at for local steps without it.
