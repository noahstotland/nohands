# NH-111: Keep a log of the last 50 commands and show every step in a View Logs window: Design

**Date:** 2026-11-15  **Ticket:** [NH-111](https://github.com/noahstotland/nohands/issues/111)
**Status:** Shipped
**Shipped:** in PR #132, as specified

## Intent

Nothing in the app remembers what a command did, and a task's step trail is dropped when the task ends. Keep the newest 50 commands on this Mac, with what ran, each step's result and timing, and the Claude token counts. Show them from the menu bar: a "Recent commands" submenu and a "View Logs" window with the step-by-step breakdown.

Non-goals: searching, exporting or clearing the log; replay; a cost budget; changes to the corner panel or `PipelineLog`. A session token total is #112.

Anti-goals: the log readable by another user or sent anywhere (it holds spoken phrases); a bad log file stopping the pipeline, a task or launch; a log write that delays or is awaited by the pipeline; recording that stops "stop" from halting a task.

## Design

### Step timing (NoHandsCore)

`TaskStepRecord` gains `startedAt` and `duration`. `TaskTrail.begin` sets the start; `end` sets the duration and keeps a failure reason. Ending an unknown number changes nothing, and ending a step twice keeps the first duration.

### The record (`CommandLog.swift`)

`CommandLogEntry` (Codable) holds `id`, `date`, `phrase`, `resolver` (`grammar`, `claude`, `localModel`, `none`), `steps` (number, action text, result, start, durationMs), `outcome` (`done`, `failed(reason)`, `stopped`, `ignored(reason)`), `durationMs`, and `usage` (calls and input, cache-read, cache-write tokens; nil with no Claude call). `CommandLog` keeps entries newest first, at most 50.

- A task entry has one step per trail step. A step still `running` at the end takes the task's ending.
- A grammar command is one step with the detailed action summary.
- `CommandLogText` builds the menu line and detail text for both the submenu and window.

Decoding is the safety rule: a missing or empty file, invalid JSON, a wrong shape or any bad entry gives an empty log, with no partial salvage. A valid file over 50 is trimmed.

### What gets recorded (NoHandsMac)

- Grammar `.execute`: one step, done or failed. `.reject`: no steps, failed with the message.
- Model task (`runTask`): resolver `claude` or `localModel`, the trail's steps, the outcome (stuck records as failed), and usage.
- Unmatched with LLM off: resolver `none`, ignored with the hint.
- A "stop" is no entry; the stopped task records `stopped`.

Not recorded: ignored speech, answers to a task's question, held, dropped or stale jobs, and dictated text. Mode switches are recorded.

Claude tokens: `IntentResolving.takeUsage()` returns and clears the call usage; `runTask` clears it at start and reads it at the end, so a cancelled task never leaks. Local-model tasks carry no counts.

### Storage (`CommandLogStore`)

- File `~/.config/nohands/command-log.json`; directory `0700`, file `0600`, using `ConfigFile`'s atomic no-follow write.
- A `@MainActor` store loads once at launch and writes from a detached task after each append. A write error is logged with `PipelineLog.warning`; the in-memory log keeps working.
- A corrupt file is overwritten by the next append.

### Menu and window

- **Recent commands** submenu: newest first, one line per entry, or a disabled "No commands yet". Rebuilt in `menuWillOpen`. Choosing an entry opens View Logs on it.
- **View Logs…** opens one reused window: a list (time, phrase, outcome) beside a read-only detail text. It updates live.

## Tests and docs

Table-driven `NoHandsCore` tests cover keep-last-50, decoding, step timing, entries and text. The window, menu and file write are manual checks. `README.md` documents the menu items and the log file.

## Calls I made

- Grammar steps use the detailed summary, because the log is local and owner-only.
- The file sits next to the config, not in Application Support.
- Rejected and unmatched commands are entries, so the user sees why nothing happened.
- A list-plus-detail split, not a long page or popup.
