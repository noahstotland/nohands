# NH-111: Keep a log of the last 50 commands and show every step in a View Logs window: Design

**Date:** 2026-11-15  **Ticket:** [NH-111](https://github.com/noahstotland/nohands/issues/111)
**Status:** Draft

## Intent

Today nothing in the app remembers what a command did. A line goes to the unified log and is gone from view once
`log stream` closes, and a task's step trail is dropped when the task ends. This change keeps the newest 50
commands on this Mac, with what ran, each step's result and timing, and the Claude token counts, and shows them from
the menu bar: a short "Recent commands" submenu and a "View Logs" window with the full step-by-step breakdown.

## Goals, non-goals, anti-goals

Goals are the ticket's Scope and Acceptance.

Non-goals, from the ticket: searching, exporting or clearing the log; replaying a command; a token or cost budget;
changing the corner panel, `PipelineLog` or what goes to the unified log. A session token total in the menu is #112.

Anti-goals, which would make this a failure even if it works:

- The log file readable by another user, or its contents sent anywhere (it holds spoken phrases and typed text).
- A corrupt, missing or unwritable log file that stops the pipeline, a task or the app from starting.
- Writing the log on the hot path in a way that delays the next command (the file write is off the main path's
  critical work and never awaited by the pipeline).
- A spoken "stop" that no longer halts a task because recording it is in the way.

## What the code forces

- Every command ends in one of two places in `VoicePipeline`: `process(_:held:)` for grammar commands, rejects and
  ignores, and `runTask(_:runner:)` for anything the model resolves (all model commands, one action or many, run as
  a `TaskRunner` task). `busy(_:)` handles a stop, an answer and held or dropped words while a task runs. These are
  exactly the `PipelineLog.utterance` call sites, so the log is fed next to each of them.
- `TaskStepRecord` has no timestamps. `TaskTrail.begin` and `end` are the only writers, so timing goes there.
  `TaskTrail` is `Equatable` and rides on the overlay's board rows; adding times makes two trails with different
  times unequal, which only means the panel redraws when a step starts or ends, as it already does.
- `ClaudeUsage.from(response:)` is read in `ClaudeIntentResolver.resolve` and `plan` and thrown away. The resolver
  is an actor behind `IntentResolving`, and tasks run one at a time, so the resolver can collect the usage of each
  call and hand it over when the task ends.
- `ConfigFile` already creates `~/.config/nohands/` as `0700` and writes with `0600`, `O_NOFOLLOW` and an atomic
  replace. The log reuses that directory and those rules.

## Design

### Step timing (NoHandsCore)

`TaskStepRecord` gains `startedAt: Date?` and `duration: Duration?`.

- `TaskTrail.begin(number:intent:actions:at:)` sets `startedAt` (`at` defaults to `Date()`; tests pass a fixed date).
- `TaskTrail.end(number:failure:at:)` sets `duration = at - startedAt` and the state, as today. A failed step keeps
  its reason. Ending an unknown number still changes nothing; ending a step twice keeps the first duration.

### The record (NoHandsCore, `CommandLog.swift`)

```swift
public struct CommandLogEntry: Codable, Equatable, Sendable {
    public enum Resolver: String, Codable, Sendable { case grammar, claude, localModel, none }
    public enum Outcome: Codable, Equatable, Sendable { case done, failed(String), stopped, ignored(String) }
    public struct Step: Codable, Equatable, Sendable {
        public let number: Int
        public let action: String        // the step's intent, or the action summary for a grammar command
        public let result: Outcome        // done, failed(reason) or stopped
        public let startedAt: Date?
        public let durationMs: Int?
    }
    public struct Usage: Codable, Equatable, Sendable { calls, inputTokens, cacheReadTokens, cacheWriteTokens }

    public let id: UUID
    public let date: Date
    public let phrase: String
    public let resolver: Resolver
    public let steps: [Step]
    public let outcome: Outcome
    public let durationMs: Int
    public let usage: Usage?          // nil when no Claude call was made
}

public struct CommandLog: Equatable, Sendable {
    public static let limit = 50
    public private(set) var entries: [CommandLogEntry]   // newest first
    public mutating func append(_ entry: CommandLogEntry)  // inserts at the front, drops past `limit`
    public func encoded() throws -> Data
    public static func decode(_ data: Data?) -> CommandLog // nil, empty, corrupt or wrong shape -> empty log
}
```

Pure helpers build entries from what the pipeline has:

- `CommandLogEntry.fromTrail(_ trail: TaskTrail, outcome:)`: one `Step` per trail step, in the order they ran. A step
  still `running` when the task ends takes the task's ending (done, stopped or failed), the same rule the corner panel
  uses.
- A grammar command becomes one step: `action` is `ActionSummary`'s detailed text of the actions (the private,
  detailed form, since the log is private and local), its result is done or failed with the executor's reason.
- `Usage.sum(_ calls: [ClaudeUsage])`: the call count and the summed counts; nil for an empty list.
- `CommandLogText`: the menu line (`<phrase> · <outcome>`, cut like other menu text) and the detail text for one entry
  (time, phrase, resolver, each step with result and timing, outcome and total time, Claude calls and tokens). The
  submenu and the window both use it, so their wording is tested once.

Decoding is the safety rule: a missing file, an empty file, invalid JSON, a wrong top-level shape or an entry that
fails to decode gives an empty log (a whole-file decode; no partial salvage). Entries over 50 in a valid file are
trimmed to the newest 50.

### What gets recorded (NoHandsMac)

One entry per command that was meant to do something:

| Ends in | Entry |
|---|---|
| grammar `.execute` | resolver `grammar`, one step, done or failed(reason) |
| grammar `.reject` | resolver `grammar`, no steps, failed(message) |
| model task (`runTask`) | resolver `claude` or `localModel`, the trail's steps, the task outcome (stuck and failed both record as failed with the reason), Claude usage if any |
| unmatched with LLM off | resolver `none`, no steps, ignored(hint) |
| stop phrase while a task runs | not its own entry: the task it stopped records `stopped` |

Not recorded: ignored speech (not addressed, sleeping), answers to a task's question or confirm (they are part of
that task), held jobs (recorded when they run), dropped or stale jobs, and dictation text in dictation mode (that is
typing, not a command; mode switches like "start dictation" are grammar commands and are recorded).

Which model: `VoicePipeline` gets a `resolverKind` set by `AppDelegate` when it builds or switches the resolver
(`claude` or `localModel` from the effective backend).

Claude tokens: `IntentResolving` gains `func takeUsage() async -> [ClaudeUsage]` with a default that returns `[]`.
`ClaudeIntentResolver` appends each call's usage (plan and step calls) and `takeUsage` returns and clears the list.
`runTask` calls it once when the task ends. It also clears at the start of a task so a cancelled earlier task's calls
never leak into the next one.

### Storage (NoHandsMac, `CommandLogStore`)

- File `~/.config/nohands/command-log.json`, directory created `0700` if missing, file written `0600` with the same
  atomic, no-follow write `ConfigFile` uses.
- A `@MainActor` store holds the `CommandLog`, loads it once at launch (`CommandLog.decode`), and after each append
  writes the file from a detached task with a copy of the data. A write error is logged with `PipelineLog.warning`
  and the in-memory log keeps working.
- A file that decoded as empty because it was corrupt is overwritten by the next append (no backup kept).
- The store posts a change callback so the menu and an open window update.

### Menu and window (NoHands, NoHandsMac)

- **Recent commands** submenu under the last-transcript item: newest first, one `CommandLogText` line per entry, or
  one disabled "No commands yet" item. It is rebuilt in `menuWillOpen`. Choosing an entry opens the View Logs window
  scrolled to that entry and selects it.
- **View Logs…** item opens one window (reused if already open): a plain `NSWindow` with a two-pane split, the
  command list on the left (time, phrase, outcome) and the selected command's detail text on the right in a
  read-only, selectable text view. With an empty log it says "No commands yet". It updates live when a command ends.
  Being a menu-bar app, opening it activates the app so the window comes to the front.

Example detail text:

```
3:41:07 PM · "open youtube and play the latest video" · Claude
1. Open youtube.com · done · 3:41:08 PM · 1.2 s
2. Click the first video · failed: no element "first video" · 3:41:11 PM · 0.4 s
3. Click the top result · done · 3:41:14 PM · 0.6 s
Done · 9.8 s
Claude: 4 calls · 12,340 in · 48,100 cache read · 3,200 cache write
```

### Tests (NoHandsCore)

Table-driven, one per rule:

- Keep-last-50: appending 1, 50, 51 and 60 entries keeps the newest 50, newest first.
- Decode: missing, empty, invalid JSON, wrong shape, one bad entry, 60 valid entries (trimmed), round trip.
- Step timing: begin then end sets start and duration; a failed end keeps the reason; an unknown number and a second
  end change nothing.
- Entry from a trail: step order, a still-running step takes the task's ending, usage summed or nil.
- `CommandLogText`: a grammar, a Claude and a failed entry render the resolver, steps, reason and tokens.

No tests for the window, the menu or the file write (manual checks, listed in the PR).

### Docs

`README.md`: a line under the menu description for Recent commands and View Logs, and the log file under
Configuration (where it lives, that it is local only and holds spoken text).

## Calls I made (surprising first)

- Grammar step text uses the detailed action summary (typed text, app and element names), not the payload-free
  `ActionSummary.kinds`. The log is local and owner-only, and the ticket wants "what each one executed".
- The log file goes in `~/.config/nohands/command-log.json` next to the config, owner-only, not in
  `~/Library/Application Support`.
- A corrupt file is replaced by the next write with no backup copy.
- Dictated text in dictation mode is not logged as commands; only commands are (including the mode switches).
- Ignored speech, stray words, answers to a task's question and dropped or stale jobs are not entries; a spoken
  "stop" is not its own entry, the stopped task shows `stopped`.
- A rejected grammar command and an unmatched command with LLM off are entries (failed, ignored with the hint), so
  the user can see why nothing happened.
- Choosing a submenu entry opens View Logs at that entry, rather than a separate detail popup.
- The window is a list plus detail split, not one long scrolling page.
- A model task's stuck ending records as failed with its reason; there is no separate "stuck" outcome.
- Local-model tasks have no token counts (Ollama usage is not read); only Claude calls carry usage.
- The log write happens off the main actor in a detached task and is never awaited by the pipeline.
- Times show in the user's locale clock format; durations in seconds with one decimal.
