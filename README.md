<img src="assets/icon.svg" width="64" height="64" alt="">

# nohands

Control your Mac with your voice and nothing else. Dictate into any app, press shortcuts, move and click the mouse, and give natural-language commands. Speech recognition runs on-device, so ordinary commands never touch the network.

> **Status: work in progress.** The app is wired up end to end (microphone, voice activity detection, speech recognition, command routing, execution, menu-bar UI) but has not yet been verified on real hardware against real apps.

## How it works

```
mic → Silero VAD → Parakeet speech recognition (on-device)
    → mode machine ─┬─ dictation  → formatter → type text
                    ├─ command    → fast grammar (no network) → actions
                    │                └ unmatched → Claude → actions
                    └─ sleep      → only "wake up" is honored
    → executor: keyboard/mouse events, accessibility lookups, grid and label overlays
```

- **Fast path:** a deterministic grammar matches the common commands in under a millisecond.
- **Natural language:** anything the grammar can't match goes to Claude, which returns structured actions. This needs an Anthropic API key or a local Ollama model, and is optional.
- **Targeting:** say "show numbers" to label every clickable element in the frontmost app, or "grid" to overlay a numbered 10×8 grid you can zoom into.

## Requirements

- Apple Silicon Mac, macOS 14 or later
- Xcode 16 / Swift 6 toolchain
- Microphone and Accessibility permissions
- Optional, for natural-language commands: an Anthropic API key, or a local model through [Ollama](https://ollama.com) (no key, about 2-5 GB of free RAM)

## Build

```bash
swift build
swift test
```

The first build downloads and compiles [FluidAudio](https://github.com/FluidInference/FluidAudio). Speech models download on first use.

## Run it

```bash
scripts/bundle.sh && open build/NoHands.app
```

`scripts/bundle.sh` builds a release binary, assembles `build/NoHands.app` and code-signs it. NoHands is a menu-bar app (no Dock icon); the menu bar shows `CMD`, `DICT` or `ZZZ` for the current mode.

**Prompt board.** Every prompt you speak gets a row at the top of the screen (below the menu bar, on the screen the pointer is on): your words on the left and how it is being serviced on the right, coloured by state. Blue while it is live (`listening…` while you are still speaking, `heard`, then `step n · <what the model is doing>` for a task, with `✗ <why>` after a step that failed), yellow when `held` behind a running task, green when `done` (with the step count for a task), red when it `failed`, was `dropped` or `skipped (busy)`, grey when `stopped` or ignored. Finished rows leave after six seconds; at most four prompts are shown. Notices such as `NoHands is listening` or `microphone error` appear as a line above the prompts.

**First run:**

1. **Microphone** — macOS asks when the app starts. If you click Don't Allow, the menu shows "Microphone denied — open Settings".
2. **Accessibility** — needed to type, click and read UI elements. macOS opens a prompt; enable NoHands under System Settings > Privacy & Security > Accessibility. The menu shows a red "Grant Accessibility…" item until it is granted.
3. NoHands starts listening only after both are granted, and re-checks Accessibility every few seconds (and pauses if you revoke it), so no restart is needed. The first launch also downloads the speech models.

**Ad-hoc signature caveat:** by default the app is ad-hoc signed, so macOS treats every rebuild as a new app and you must re-grant Microphone and Accessibility each time (remove the stale NoHands entry in Accessibility first). Set a stable signing identity to avoid this:

```bash
CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" scripts/bundle.sh
```

**Logs:** each utterance logs one line, `[asr=…ms total=…ms] <transcript> -> <what it did>`, plus warm-up results, warnings and errors, through the unified log:

```bash
log stream --predicate 'subsystem == "dev.nohands.app"'
```

Transcripts are logged as private, so they show as `<private>` unless private data logging is enabled (`sudo log config --mode "private_data:on"`). Running `build/NoHands.app/Contents/MacOS/NoHands` directly from a terminal also prints the full lines to that terminal.

**Claude API key:** shell exports do not reach an app started with `open`. Put the key in `~/.config/nohands/config.json` (see Configuration) and run `chmod 600 ~/.config/nohands/config.json`. Without a key, natural-language commands show "LLM off" and the fast grammar still works.

## Local model (no API key)

NoHands can resolve natural-language commands with a model running on your Mac through Ollama, so nothing leaves the machine and it works offline once the model is downloaded.

```bash
scripts/setup-local-model.sh            # picks a model by RAM
scripts/setup-local-model.sh qwen2.5:3b-instruct   # or name one
```

The script installs Ollama with Homebrew if needed, starts it, pulls the model and runs a smoke test. It is safe to re-run. You can also download the model from the NoHands menu. Ollama installed with brew starts at login (`brew services`), so the model server is there after a reboot.

- **Default model:** `qwen2.5:7b-instruct` with 12 GB of RAM or more, otherwise `qwen2.5:3b-instruct`.
- **RAM:** the 7B model needs about 5 GB free, the 3B model about 2 GB.
- **Backend choice:** `intentBackend` is `auto` (default: Claude when an API key is set, otherwise the local model), `claude`, `local` or `off`. Set `localModel` and `ollamaURL` to change the model or server (only `127.0.0.1`, `localhost` or `::1` over `http` is accepted).
- **If it fails:** the prompt's row says `local model not running: start Ollama` or `local model not downloaded: see the NoHands menu`.

## Voice commands

| Say | Does |
|---|---|
| `type <words>` | Types the words with spoken punctuation applied |
| `spell <letters>` | Types letters, NATO words (`kilo`, `x ray`), digits and `space`, `dash`, `dot`, `underscore`, `at sign` as one string with no spaces; `capital` uppercases the next letter (`spell capital kilo nine x ray` types `K9x`). One unknown word types nothing and the row says which |
| `press command shift s` | Presses a key chord |
| `enter`, `tab`, `escape`, `delete`, arrow names | Presses that key |
| `undo`, `redo`, `copy`, `paste`, `cut`, `select all`, `save`, `find` | Standard shortcuts |
| `new tab`, `close tab`, `close window`, `quit app`, `switch app`, `spotlight` | App and window shortcuts; filler words are ignored, so `close the current tab` and `close this window` work too |
| `minimize`, `full screen`, `hide app`, `reload` / `refresh` | Window and app shortcuts |
| `left half`, `right half`, `snap left`, `top left`, `maximize`, `center window` | Moves and resizes the frontmost window on its screen (halves, quarters, thirds); richer phrasing such as `make the window half width and snap to the left side of the screen` goes through the model |
| `go back`, `go forward`, `next tab`, `previous tab` | Browser and tab navigation |
| `go to <site>` | A site name or domain opens in your default browser; other text goes to the address bar, typed and followed by Return |
| `search for <words>` | Searches where you are: the search box of the page or app in front (YouTube, Amazon, GitHub, Finder, Mail…) gets the words and Return; a page without one but with a known results page (YouTube, Google, Amazon, Reddit, Wikipedia…) is navigated to it in the current tab; any other browser page searches from the address bar. In an app with nothing to search, the row says so and nothing is typed. A search box outside the front window is not used, and words that start with a script or browser scheme (`javascript:`, `file:`, `chrome:`), or any other `scheme:text` with no space after the colon, are refused with `can't search for that` |
| `search for <words> on <site>`, `search <site> for <words>` | Opens that site's results page in your default browser, wherever you are |
| `click`, `double click`, `right click`, `middle click` | Clicks at the pointer |
| `click 42` | Clicks label or grid cell 42 |
| `click save` | Clicks the element named "save" |
| `hold click` / `release click` | Press and release the mouse button (drag) |
| `move up 100`, `move to 12` | Moves the pointer |
| `scroll down 10` | Scrolls |
| `grid`, `zoom 35`, `show numbers`, `hide` | Targeting overlays |
| `open safari` | Opens or focuses an app |
| `open youtube`, `open youtube.com`, `open reddit in safari` | Opens a website in your default browser, or in the named one (known site names: YouTube, Gmail, Google, Reddit, GitHub, Wikipedia, Netflix, Amazon and others; any `name.com` works) |
| `start dictating` / `stop dictating` | Switch between command and dictation mode |
| `scratch that` (dictation) | Deletes what your last dictated phrase typed |
| `delete word` (dictation) | Deletes the previous word |
| `go to sleep` / `wake up` | Pause and resume listening |

In dictation mode, say `period`, `comma`, `question mark`, `new line`, `new paragraph`, `open quote` and similar to insert punctuation.

## CLI tools

`nohands-cli` exercises the pieces without the menu-bar app (`swift run nohands-cli <subcommand>`). Subcommands that act on other apps need Accessibility for your terminal and wait a few seconds so you can focus the target app.

| Subcommand | Does |
|---|---|
| `type "<text>"` | Waits 2 s, then types the text |
| `key "<chord>"` | Presses a key chord, e.g. `"command shift s"` |
| `click-at <x> <y>` | Clicks at screen coordinates |
| `move <x> <y>` | Moves the pointer |
| `transcribe <wav>` | Transcribes an audio file and prints timings |
| `vad-test <wav>` | Prints voice-activity events for an audio file |
| `elements` | Lists the frontmost app's actionable elements |
| `click "<name>"` | Clicks the named element |
| `grid` | Shows the 10×8 grid, zooms into cell 35 |
| `labels` | Shows numbered badges on the frontmost app's elements |
| `parse "<text>"` | Dry run: prints the actions the grammar produces (or "no match -> LLM", or "rejected: ..." for a `spell` with an unknown word, e.g. `parse "spell capital kilo nine x ray"`); executes nothing |
| `run "<phrase>"...` | Executes grammar phrases in order |
| `observe` | Prints what the task loop sends the model about the frontmost app: window title, URL and numbered elements with roles |
| `resolve "<text>"` | Dry run: sends text and the frontmost app's labels to the configured backend and prints the step (`intent`, `status`, actions); executes nothing (Claude spends API credit) |
| `task "<goal>"` | Waits 3 s, then runs the goal as a multi-step task on the frontmost app for real, printing each step's intent, actions and settle time, then the outcome; Ctrl-C stops it like "stop", a second Ctrl-C quits at once (status 130); exits 2 when the task ends stuck, failed or stopped |
| `listen` | Microphone to VAD to speech recognition, printing transcripts |
| `desktop-status` | Where the agent-desktop binary was found, its version, what it reports for Accessibility, and the harness in use |
| `snapshot [app]` | Waits 3 s, then prints the task-loop observation of the frontmost (or named) app as agent-desktop sees it: numbered elements with roles, values and states |

## Configuration

Optional file at `~/.config/nohands/config.json`. Every key may be omitted. For the bundled app this file is the way to supply the API key: `ANTHROPIC_API_KEY` in the environment overrides the file, but it only reaches the app when you run the binary from a terminal or set it with `launchctl setenv ANTHROPIC_API_KEY ...`. The file holds a secret, so run `chmod 600 ~/.config/nohands/config.json`; NoHands logs a warning at launch if it contains a key and is readable by other users. Invalid JSON falls back to defaults and is flagged in the menu.

```json
{
  "anthropicAPIKey": "sk-ant-...",
  "intentModel": "claude-opus-5-5",
  "intentEffort": "medium",
  "intentBackend": "auto",
  "localModel": "qwen2.5:7b-instruct",
  "ollamaURL": "http://127.0.0.1:11434",
  "asrModelVersion": "v2",
  "silenceMs": 1000,
  "mergeWindowMs": 500,
  "mergeWindowUnfinishedMs": 1500,
  "gridColumns": 10,
  "gridRows": 8,
  "moveStepPx": 50,
  "scrollStepLines": 5,
  "maxTaskSteps": 12,
  "llmDeadlineMs": 12000,
  "settleMs": 3000,
  "maxObservedElements": 120,
  "localLlmDeadlineMs": 30000,
  "localMaxObservedElements": 40,
  "echoCancellation": true
}
```

**Echo cancellation.** `echoCancellation` (true by default) turns on macOS voice processing on the microphone, which removes what the Mac's own speakers play before NoHands listens. Set it to `false` if an external audio interface does its own processing and the two clash. If macOS refuses voice processing, NoHands keeps listening without it and says so in the log.

**Task loop keys.** `maxTaskSteps` (1 to 30) is how many observe-and-act steps a multi-step request may take. `llmDeadlineMs` (2000 to 60000) is how long each model call may take. `settleMs` (0 to 10000) is the most time, in wall-clock terms and including the time spent reading the screen, to wait for the screen to stop changing after an action (and before the first step only when a Chromium browser's page content was just switched on). `maxObservedElements` (10 to 300) caps how many on-screen elements are sent to the model. When the local model is the backend, `localLlmDeadlineMs` (2000 to 120000, default 30000) and `localMaxObservedElements` (10 to 300, default 40) replace those two: a 7B model on an M1 Pro needs 5 to 20 s per step, and every element costs about 14 prompt tokens.

**Pausing mid-command.** You do not have to say a command in one breath. `silenceMs` is how long you can go quiet before the recognizer closes an utterance (1 s by default). After that, a transcript the fast grammar does not already understand (and every `spell` phrase, so a pause mid-spelling stays one string) is held for `mergeWindowMs` (longer, `mergeWindowUnfinishedMs`, when it ends on a word like "the" or "click" that leaves the command hanging); its row on the prompt board shows `listening…`. If you start speaking again inside that window, the next piece is appended and the whole thing is treated as one request, so "click the … uh, the back button" reaches the model as a single sentence. Set both windows to 0 to act on every utterance at once. A stop phrase ("stop", "cancel", "never mind", also "stop stop" or "um, stop") is never held or merged: it goes through at once, and in command mode it also discards the unfinished words before it. In dictation, "stop dictating" and "command mode" likewise go through on their own instead of being typed as part of the text, and so do "scratch that" and "delete word".

**How the model reads a request.** The transcript comes from speech recognition, so the model is told to first write a one-sentence `intent` (what you meant, with recognition errors, filler and self-corrections resolved) and only then the actions that carry it out. `intentEffort` (`low` … `max`) sets how hard Claude thinks before answering; `medium` is the default, `low` is fastest.

## Multi-step tasks

A request the fast grammar does not understand runs as a task: NoHands looks at the frontmost app (window title, URL and up to `maxObservedElements` numbered on-screen elements; while number badges are shown, the model sees the same numbers as the badges), asks the model for the next step, runs that step's actions, waits up to `settleMs` for the screen to stop changing, and looks again. Each step's answer is a one-sentence `intent`, a `status` (`continue`, `done`, `stuck` or `ignore`) and a few actions; the prompt's row shows `step n · <intent>` (and `✗ <why>` after a step whose actions failed). "Open Veritasium's latest video" becomes: open the channel's Videos tab in the default browser (`open_url`; the browser is named only when you name one), then (after seeing the page) click the first video. Before typing into an app it just opened, NoHands waits for that app to be frontmost and to show a window, so a cold-launched browser does not swallow the keystrokes. The task ends when the model says `done`, says `stuck` (the row shows why), reaches `maxTaskSteps`, or proposes the same actions three times in a row; any held mouse button is released when a task does not finish `done`. If the model answers `ignore` after earlier steps already acted, the row shows `stopped: <intent>`. The finish line ends with the number of steps that ran. As a safety guard in code (not just the prompt), a step that would press command-W is blocked unless your request contains the word close (closes, closing, closed) or shut, and command-Q unless it contains quit (quits, quitting), exit (exiting) or shut. Whole words only, and per key: "close this tab" does not allow quitting the app. Nothing from a blocked step runs and the model is told it was blocked.

**Stopping a task.** Say "stop" (or "cancel", "never mind", "abort", "stop the task"; repeats and fillers such as "stop stop" or "no, stop" count too). It aborts the request or action in flight; the task's row shows `stopped` and the stop's own row `stopping the task`. From the CLI, Ctrl-C stops `nohands-cli task` the same way; a second Ctrl-C quits at once.

**Talking while a task runs.** Anything else you say while a task runs is held, and its row shows `held · runs after this task (say stop to cancel)`. Only the newest utterance is kept: saying something else replaces it, and the replaced utterance's row shows `dropped`. It runs once the task ends, unless it is more than 60 seconds old by then or you said "stop" (which drops it along with the task); either way its row shows `dropped` and nothing from it runs.

**Config.** `maxTaskSteps` (default 12), `llmDeadlineMs` (12000, per model call), `settleMs` (3000) and `maxObservedElements` (120); with the local backend, `localLlmDeadlineMs` (30000) and `localMaxObservedElements` (40) apply instead of the last two. See [Configuration](#configuration).

### agent-desktop harness

With [agent-desktop](https://github.com/vercel-labs/agent-desktop) installed (`npm i -g agent-desktop` or `brew install agent-desktop`, macOS 13+), tasks observe and act through it instead of NoHands' own accessibility walk and synthesized clicks. The menu shows `Harness: agent-desktop <version>` when it is in use and `Harness: native (…)` with the reason when it is not. The harness is picked when NoHands starts listening; the menu re-checks each time it opens and adds `restart NoHands to use it` once an install or a permission grant would change the pick. `nohands-cli desktop-status` prints the same.

What changes with the harness:

- **Observation.** Each step snapshots the frontmost app's accessibility tree through agent-desktop: elements keep stable references, and the model also sees each field's current value (`= "cats"`) and states (checked, selected, disabled, expanded, offscreen). When an action opens a sheet, menu, alert or popover, the next step lists that surface's elements instead of the window's (`Surface: sheet`).
- **Actions on elements** land on the element, not on a point: `click` presses the element semantically, with a real click only when agent-desktop reports it delivered nothing. New model actions: `set_value`, `type_into`, `clear`, `select` (dropdown option), `check`/`uncheck`/`toggle`, `expand`/`collapse`, `focus`, `scroll_to`, `scroll_element`, `drag`.
- **Menus, Dock and dialogs by name.** `menu_item` runs a menu bar command by its name ("Save As…"); `click_in` clicks a named item in a surface (`dock`, `menubar`, `sheet`, `alert`, `popover`, `menu`, `menu_bar_extras`).
- **Apps, windows, clipboard, notifications.** `close_app` (guarded like command-Q: the request must say quit, exit, shut or close), `window` (minimize, maximize, restore, focus by app and title), `clipboard_set`, `read_clipboard`, `read_value`, `read_notifications`, `dismiss_notifications`. What a `read_*` action read arrives in the next step under `Read:`; a task that finishes with a reading shows it on its row.
- **Typed waits.** `wait` with `wait_for` blocks on a signal (text appearing, a window title, a menu opening or closing, an element becoming actionable, or a lifecycle event such as `window_opened`) instead of a fixed pause.

The harness is chosen once per task from its first observation: if agent-desktop cannot read the frontmost app (no window, the window is on another Space or minimized, a locked screen), the whole task runs natively, with the same loop and prompt board. On the local backend such a task uses the native prompt, which is not the prefix the warm-up cached, so its first step pays the full prefill once. Grammar commands ("click 12", "type hello", "press command s") and dictation never go through agent-desktop. Physical input (`--headed`) is used only after agent-desktop says nothing was delivered, so a click or a submit is never doubled.

**Config.** `desktopHarness` (`auto`, default: agent-desktop when found and Accessibility is granted; `agentDesktop`; `native`), `agentDesktopPath` (absolute path; by default `/opt/homebrew/bin`, `/usr/local/bin`, `~/.bun/bin`, `~/.volta/bin`, `~/.npm-global/bin`, `~/.local/bin`, every nvm node version and `PATH` are searched, since an app started with `open` has no shell PATH), `agentDesktopTimeoutMs` (8000 per action), `agentDesktopSnapshotMs` (3000 per snapshot), `agentDesktopHeadedFallback` (true), `agentDesktopTrace` (false: when true each task runs in an agent-desktop session whose trace, with text fields redacted, is under `~/.agent-desktop/sessions`). agent-desktop needs the Accessibility grant for NoHands itself, which NoHands already requires.

**Claude vs. the local model.** Use Claude for multi-step tasks. The local model is not yet proven for them: in the recorded runs with `qwen2.5:7b-instruct`, the cold first request timed out and the warm one answered `ignore`; no task has completed successfully on it so far. It may still handle simple one-step requests. Each step costs the model 5 to 20 s on an M1 Pro (about 2,200 prompt tokens of instructions and examples, plus the screen, decoded at about 14 tokens per second), so the local backend gets its own `localLlmDeadlineMs` (30 s) and sends at most `localMaxObservedElements` (40) elements. While NoHands is listening it warms the model every 20 minutes by running that fixed prefix through Ollama, so it sits in Ollama's prompt cache; the first command after a warm-up skips that part of the wait. Requests that still end with "timed out" mean the machine is short on memory (check swap use) or `localLlmDeadlineMs` needs raising.

## Privacy

Audio never leaves your machine. Only commands the grammar can't match are sent to Claude (or to the local model, which stays on your Mac), as text: your transcript, the frontmost app's name and the titles of its visible controls. Multi-step task steps also send the focused window's title, the page URL (in a browser) and each element's role, to Claude or to the local model alike. With the agent-desktop harness, each listed field's current value (what is typed in a search box or a form, cut at 60 characters) is sent too; clipboard text, a full element value and the notification list are sent only in the step after the model explicitly asked to read them. Text handed to agent-desktop (`set_value`, `type_into`, `clipboard_set`) travels in the child process's arguments, visible to `ps` while it runs. Without an API key nothing is sent off the Mac; with the local backend, text goes only to Ollama on `127.0.0.1`.

**There is no wake word.** Echo cancellation removes what the Mac's own speakers play, but other people talking, a phone on speaker or very loud playback can still be heard, so "go to sleep" is still the safe choice for calls. Any audio the microphone still hears is transcribed and acted on, and in dictation mode it is typed into the focused app. With an API key, phrases the grammar doesn't match are also sent to Claude as text. Say "go to sleep" before leaving the desk or during calls; only "wake up" is honored while asleep.

## Layout

| Path | Contents |
|---|---|
| `Sources/NoHandsCore` | Pure logic: grammar, formatting, modes, geometry, Claude request and response handling |
| `Sources/NoHandsMac` | macOS integration: audio, speech models, input events, accessibility |
| `Sources/NoHands` | The menu-bar app |
| `Sources/nohands-cli` | Command-line tools for testing each piece by hand |
| `docs/superpowers` | Design spec and implementation plan |

## Design

See [the design spec](docs/superpowers/specs/2026-11-04-nohands-design.md) and [the implementation plan](docs/superpowers/plans/2026-11-04-nohands-voice-control.md).
