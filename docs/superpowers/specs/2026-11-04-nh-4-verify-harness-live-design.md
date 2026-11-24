# Verify the agent-desktop harness live against real windows: Design

**Date:** 2026-11-04
**Status:** Shipped
**Shipped:** in PR #186, with differences: [as-built](../as-built/2026-11-23-agent-desktop-harness-live.md)
**Ticket:** [NH-4](https://github.com/noahstotland/nohands/issues/4)  **Base:** `origin/main` (ff9e08b)
**Related:** [harness design](2026-11-04-agent-desktop-harness-design.md), PR #2, #7 (deferred minors, out of scope)

## Intent

PR #2 merged the agent-desktop harness, but no harness command has ever run against a real window. Every window came back as not exposed (locked screen), so only `desktop-status`, menubar snapshots and the unit suite with recorded output were exercised. This ticket runs the harness live on TextEdit and Chrome, fixes small breakages in the same PR, files tickets for anything bigger, and writes down what happened.

## Goals and non-goals

- **Goals**
  - Live read-only runs: `nohands-cli snapshot TextEdit`, `nohands-cli snapshot "Google Chrome"`, `nohands-cli observe`. For each one, check that the numbered elements, values and states match the screen.
  - Live task runs with Claude: TextEdit "type hello and save it as test" and Chrome "open the Veritasium channel's newest video", with each step log kept.
  - An as-built note, `docs/superpowers/as-built/<date>-agent-desktop-harness-live.md`, with one row per run: command, harness (`agent-desktop` or `native` fallback), outcome, settle times (per step and total) and wall time.
  - Acceptance: at least one TextEdit task ends `done` through agent-desktop. If none does, the note names the exact failure and a ticket exists for it.
  - README harness section updated wherever the live behaviour differs from what it says.
- **Non-goals**
  - The five deferred review minors from PR #2 (#7).
  - Local-model (Ollama) task runs. The ticket says Claude, and the README already says the local model can't do multi-step tasks yet.
  - New harness features, new actions, or prompt changes beyond what a small fix needs.
- **Anti-goals**
  - Claiming a live run passed when it didn't run, or ran on the native fallback.
  - Editing `scripts/intent-eval*.json` expectations.
  - Overwriting or deleting a user file.

## Preconditions (checked first in the build stage; none of them is set up by an agent)

1. The screen is unlocked and the TextEdit and Chrome windows are on the current Space, on screen and not minimized.
2. Accessibility is granted to the process that runs the commands: the T3 Code terminal or app that runs the agent shell. Both `nohands-cli` (`Permissions.accessibilityGranted`) and agent-desktop require it.
3. agent-desktop 1.1.0 is at `~/.nvm/versions/node/v18.18.2/bin/agent-desktop` and `nohands-cli desktop-status` reports `Harness: agent-desktop 1.1.0`.
4. **A Claude API key is reachable by the agent's shell.** When the spec was written, there was no `~/.config/nohands/config.json` and no `ANTHROPIC_API_KEY` in the agent shell. The user has to add the key (the README § Configuration way, `chmod 600`). The agent never creates the file, writes a key, or prints one.
5. No file named `test` (any extension) exists in `~/Documents` or in iCloud Drive's TextEdit folder (`~/Library/Mobile Documents/com~apple~TextEdit/Documents`). If one exists, the save would raise a replace prompt or overwrite the user's file.

## Live runs in the build stage

These run in order. Every run logs its full output to a scratch file, and the as-built note quotes from those logs. Element values the log shows are screen content: only the parts the note needs are copied into it, and nothing that looks like private data.

| # | Command | Touches other apps? |
|---|---|---|
| 0 | `swift build`, then `nohands-cli desktop-status` | No. Read-only |
| 0b | `agent-desktop list-windows` and one `agent-desktop snapshot --app TextEdit -i --compact`: the exposure check | No. Read-only |
| 1 | `open -a TextEdit` (and a new blank document if none is open), then `nohands-cli snapshot TextEdit` | **Yes: launches and activates TextEdit and may open a blank, unsaved document.** Nothing is typed |
| 2 | `open -a "Google Chrome"`, then `nohands-cli snapshot "Google Chrome"` | **Yes: activates Chrome.** Reads its frontmost window (whatever tab is open). Nothing is typed or clicked |
| 3 | `open -a TextEdit`, then `nohands-cli observe` (it reads the frontmost app after 3 s) | **Yes: activates TextEdit.** Read-only after that |
| 4 | `open -a TextEdit`, then `nohands-cli task "type hello and save it as test"` | **Yes: types "hello" into TextEdit, opens the Save sheet, and types "test" and presses Save. That writes a new `test.rtf` (or `.txt`) to TextEdit's default save folder.** It sends the window title, element roles and names and field values to Claude, and each step is a paid API call |
| 5 | `open -a "Google Chrome"`, then `nohands-cli task "open the Veritasium channel's newest video"` | **Yes: clicks and types in Chrome (address bar, YouTube search or channel page), opens the newest video, and the video starts playing with sound.** It sends page titles, the URL and element names and values to Claude. Paid API calls |

- Runs 1–3 count only when the CLI reports the agent-desktop harness. A native result is recorded as a native fallback, with its reason. It is not counted as agent-desktop.
- Every run is a single process with a deadline: snapshots use `agentDesktopSnapshotMs`, and tasks stop at `maxTaskSteps` (12). The agent doesn't touch the keyboard or mouse outside these commands, and doesn't quit or close any app or window.
- Retries: when a run fails because of a small bug fixed in this PR, it runs again once the fix is in. That's at most three attempts per task in total, so the Claude cost and the typing into the user's apps stay bounded. If it still fails after that, the failure is recorded and a ticket is filed.
- When the runs are done, the `test` file stays where TextEdit saved it, and its path goes in the note and the PR. The agent never deletes it. The user removes it.

### If windows come back as not exposed

If `desktop-status`, `list-windows` or the run 0b snapshot shows the locked-screen or hidden-window signatures (`WINDOW_NOT_FOUND`, `APP_NOT_FOUND` for an app that is running, `ACTION_NOT_SUPPORTED` with `window_without_accessibility_element`, or no windows listed), the build stage stops with `BLOCKED:`. The message quotes the agent-desktop output and doesn't guess whether the screen is locked. The same goes for Accessibility not granted (precondition 2) and a missing API key (precondition 4). Nothing is retried in a loop. No fallback result is labelled as passing. Not even run 0 counts as a live harness pass.

If the user then chooses to ship without those runs, every run that didn't happen is listed in the PR under **Manual checks**, with the exact command to run and what to look for, and under `Checks that didn't really run` in `MERGE READY`. It is never listed as passed.

## Code changes expected

- **The step log names the harness (small fix, part of this ticket).** Today `nohands-cli task` prints which harness was loaded but not which one the task actually used. `TaskRunner` switches to native after the first observation when agent-desktop can't read the app (`TaskRunner.swift:96`), and nothing reports that switch. The fix: `TaskRunner` exposes the harness the task ran on (a public read-only property, or the reason with it), and `nohands-cli task` prints `harness: agent-desktop` or `harness: native (fallback: <reason>)` after step 1. A unit test covers the fallback switch with the existing fake harness. That is the one behaviour the acceptance depends on.
- **Fixes for whatever breaks in the live runs**, when they are small (roughly under 100 lines with no new action types and no schema change). Each one comes with a test against recorded agent-desktop output from the live run, saved as a fixture the way the existing unit suite does it. Recorded fixtures are trimmed to what the test needs, with no private values from the screen.
- **Anything larger** gets its own ticket filed with `write-ticket`, with the step log attached (trimmed the same way) and linked from the as-built note.
- No change to `NoHandsCore`'s dependencies, the intent schema, the guards, the grammar or the config keys is planned. If a fix would need one, it is out of scope and gets a ticket.

## Docs

- `docs/superpowers/as-built/<date>-agent-desktop-harness-live.md`: a table of runs (command, harness, outcome, step count, settle per step, total time), then what matched and didn't match the screen for runs 1–3, the failures with their tickets, and the `test` file's path. It also carries the `**Shipped:**`/`**Ticket:**`/`**Spec:**` header lines and a `## Checks that didn't run` section if any did not run.
- README § agent-desktop harness: updated only where the live runs contradict it, for example the fallback triggers, the timings, or what a snapshot lists.
- This spec's header gets the closeout `**Shipped:**` line.

## Testing

- `swift test` stays green with no Accessibility, no microphone and no Ollama. The live runs aren't unit tests and don't go in the suite.
- New tests: the harness-fallback report, and one table-driven test per real bug the live runs turn up.
- The intent fixtures aren't touched. If a prompt fix changes model behaviour, `nohands-cli eval scripts/intent-eval.json` runs, and that needs the key.

## Calls I made

- **The build stage needs the user to add a Claude API key first.** None is reachable from the agent shell today. The agent won't create the config file, so without a key the Claude runs (4, 5) end `BLOCKED:` or become manual checks.
- **Runs 1–5 activate TextEdit and Chrome with `open -a` and act on them while the user may be at the Mac.** The TextEdit task types and saves a new `test` file, and the Chrome task plays a YouTube video with sound. I chose to leave that file in place rather than delete it.
- **The build stage refuses to start the TextEdit task if a `test` file already exists** in `~/Documents` or the iCloud TextEdit folder. This avoids a replace prompt or an overwrite.
- **At most three attempts per task.** This caps API cost and how much the agent types into the user's apps.
- **`nohands-cli task` will print the harness actually used.** The acceptance needs it, and today the switch to native is invisible. I count this as a small fix inside this ticket, not as new scope.
- **What counts as "small enough to fix here"**: under about 100 lines, no new action type, no schema or config change. Everything else gets a ticket.
- **The local model is not run.** The ticket names Claude only.
- **Screen content stays out of the repo.** The as-built note and fixtures quote only the parts of the logs they need, with private values removed.
- **Locked screen, Accessibility missing and no key all end `BLOCKED:` the same way.** There are no retries and no guessing, and runs that didn't happen go to the PR as manual checks.
