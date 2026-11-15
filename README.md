<img src="assets/icon.svg" width="64" height="64" alt="NoHands logo">

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
- Microphone and Accessibility permissions (plus Screen Recording if you turn on `visionFallback`)
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

Build from an up-to-date `main`: `scripts/bundle.sh` prints a warning to stderr when the checkout is behind `origin/main`, because features merged since then would be missing from the app.

`scripts/bundle.sh` builds a release binary, assembles `build/NoHands.app` and code-signs it. NoHands is a menu-bar app (no Dock icon); the menu bar shows `CMD`, `DICT` or `ZZZ` for the current mode.

**Prompt board.** Every prompt you speak gets a row at the top of the screen (below the menu bar, on the screen the pointer is on): your words on the left and how it is being serviced on the right, coloured by state. Blue while it is live (`listening…` while you are still speaking, `heard`, then for a task a phase line (`Reading · looking at the screen`, `Thinking · picking the next step`) until the first step starts and `step n · <what the model is doing>` after, with `✗ <why>` after a step that failed), yellow when `held` behind a running task, green when `done` (with the step count for a task), red when it `failed`, was `dropped` or `skipped (busy)`, grey when `stopped` or ignored. Finished rows stay 1.5 seconds (3 seconds when failed or dropped) and fade out; at most four prompts are shown. Notices such as `NoHands is listening` or `microphone error` appear as a line above the prompts.

**Status bar.** A small bar appears when NoHands has something to say, and goes away when it has not: the prompt and its step while a task runs (then `done`, `stopped` or the failure for a few seconds), `Dictating`, `Asleep · say wake up`, `Paused`, `Loading speech model…`, or the problem with its fix (`Needs Accessibility: allow NoHands in System Settings`, `Microphone denied …`, `Error: … · choose Retry in the menu`). Idle in command mode it shows nothing. It is on by default, at the bottom right of the screen the pointer is on, below the corner task panel. The menu's Status Bar item chooses Off or Bottom Right (a stored Top or Bottom from an older version becomes Bottom Right); the choice applies at once and is remembered across launches (macOS user defaults, not `config.json`). The bar ignores clicks and hides while the grid or number badges are showing.

**Corner panel.** While a request runs, a panel at the bottom right of the screen the pointer is on shows what you said, the steps so far (`✓` done, `✗` failed, a dot for the one running), a phase line with a small spinner while it works (`Reading`, `Thinking` or `Acting` with a few plain words, never your text) and the step number, `step 3`, with no total, because NoHands decides one step at a time and cannot know how many remain (the step limit, `maxTaskSteps` or `maxMediaTaskSteps` for a request to play something, is shown only when a task hits it). When the request ends the panel keeps the outcome (`done`, or the failure with what to try next) for 1.5 seconds (3 for a failure), then fades out. Saying "stop" clears it at once. A short command like `scroll down` shows only the phrase and the result. The panel has no setting, ignores clicks, and hides while the grid or number badges are showing.

**First run:**

1. **Microphone** — macOS asks when the app starts. If you click Don't Allow, the menu shows "Microphone denied — open Settings".
2. **Accessibility** — needed to type, click and read UI elements. macOS opens a prompt; enable NoHands under System Settings > Privacy & Security > Accessibility. The menu shows a red "Grant Accessibility…" item until it is granted.
3. **Screen Recording** (optional) — needed only when `visionFallback` is on (see [Multi-step tasks](#multi-step-tasks)). The menu shows a red "Grant Screen Recording…" item, only while `visionFallback` is on, the backend is Claude and the permission is missing; it asks macOS and opens System Settings > Privacy & Security > Screen & System Audio Recording, where you enable NoHands. macOS often applies this grant only after the app is relaunched, so quit and reopen NoHands if the item stays after you allowed it. Without the grant, steps that would have a picture run without one and the prompt's row says `screen recording not granted`.
4. NoHands starts listening only after Microphone and Accessibility are granted, and re-checks Accessibility every few seconds (and pauses if you revoke it), so no restart is needed. The first launch also downloads the speech models.

**Ad-hoc signature caveat:** by default the app is ad-hoc signed, so macOS treats every rebuild as a new app and you must re-grant Microphone and Accessibility (and Screen Recording, if you use `visionFallback`) each time (remove the stale NoHands entry in Accessibility first, and likewise in Screen Recording; the new grant may need a relaunch to take effect). Set a stable signing identity to avoid this:

```bash
CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" scripts/bundle.sh
```

**Start at Login:** the menu's Start at Login item registers the app as a login item (System Settings > General > Login Items) and shows a tick while it is on; the state is read from macOS each time the menu opens. If you turned NoHands off in Login Items, the item says `allow in Login Items` and opens that pane. It is disabled when NoHands runs without an app bundle (`swift run`); use `build/NoHands.app`. The login item is tied to the app's path and signature, so a rebuild may need re-ticking or re-approval.

**Logs:** each utterance logs one line, `[asr=…ms total=…ms sinceVoice=…ms] <transcript> -> <what it did>` (`sinceVoice` counts from the last moment you were heard, so it includes the silence wait that `total` leaves out), plus one `claude: step N <ms>ms cache=<read>/<written> in=<n>` line per Claude response and one `ollama: step N <ms>ms` line per local model response (token counts and timing only, no text), an `intent backend: claude|local|off` line at start and on each switch from the Model menu, warm-up results, warnings and errors, through the unified log:

```bash
log stream --predicate 'subsystem == "dev.nohands.app"'
```

Transcripts are logged as private, so they show as `<private>` unless private data logging is enabled (`sudo log config --mode "private_data:on"`). Running `build/NoHands.app/Contents/MacOS/NoHands` directly from a terminal also prints the full lines to that terminal.

**Claude API key:** shell exports do not reach an app started with `open`. Choose **Set Claude API key…** in the menu, paste the key into the masked field and restart NoHands; it is saved to `~/.config/nohands/config.json` (see Configuration) and never shown again. Without a key, natural-language commands show "LLM off" and the fast grammar still works.

## Local model (no API key)

NoHands can resolve natural-language commands with a model running on your Mac through Ollama, so nothing leaves the machine and it works offline once the model is downloaded.

```bash
scripts/setup-local-model.sh            # picks a model by RAM
scripts/setup-local-model.sh qwen2.5:3b-instruct   # or name one
```

The script installs Ollama with Homebrew if needed, starts it, pulls the model and runs a smoke test. It is safe to re-run. You can also download the model from the NoHands menu. Ollama installed with brew starts at login (`brew services`), so the model server is there after a reboot.

- **Default model:** `qwen2.5:7b-instruct` with 12 GB of RAM or more, otherwise `qwen2.5:3b-instruct`.
- **RAM:** the 7B model needs about 5 GB free, the 3B model about 2 GB.
- **Backend choice:** `intentBackend` is `auto` (default: Claude when an API key is set, otherwise the local model), `claude`, `local` or `off`. The menu's **Model: …** item shows which one is in use and switches between Claude and the local model with no restart: pick a row and the next command that needs the model goes to it (a task already running finishes on the old one, and a command held behind it goes to the new one). The pick is saved to `intentBackend` in `config.json`, so it holds across restarts. The Claude row is greyed out until a key is in effect; a key saved from the menu this session applies after a restart. `auto` and `off` are set in the file only: picking the row already in use does nothing, and the menu never writes `off`. Set `localModel` and `ollamaURL` to change the model or server (only `127.0.0.1`, `localhost` or `::1` over `http` is accepted).
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
| `search for <words> on <site>`, `search <site> for <words>` | When that site is the page in front, it is searched there: its search box gets the words and Return, else its results page opens in the same tab. Otherwise its results page opens in your default browser |
| `is it playing`, `is the video playing`, `is anything playing` | Says whether media is playing in the front window (`playing`, `paused`, `none`), on the prompt's row. A Pause or Play button in the window decides; with no such button, sound from any other app on the Mac counts as `playing` |
| `click`, `double click`, `right click`, `middle click` | Clicks at the pointer |
| `click 42` | Clicks label or grid cell 42 |
| `click save` | Clicks the element named "save" |
| `click first video`, `click the second result`, `click the 3rd link`, `click last video` | When no element has exactly that title, a position among the numbered elements: any other word (`video`, `result`, `one`, …) counts the page's links with a title of three or more words (a thumbnail and title link with the same name count once); `link`, `button`, `checkbox`, `tab`, `field`, `box` and `menu item` count elements of that role. Ordinals run `first` to `tenth`, `1st`, `2nd`, … and `last`. With too few matches it fails with `no element named …; say its label number from the list`. Only `click` and `move`; a model step that sends a position is clicked the same way |
| `hold click` / `release click` | Press and release the mouse button (drag) |
| `move up 100`, `move to 12` | Moves the pointer |
| `scroll down 10` | Scrolls |
| `find <words>` | Scrolls the front window until text or an element with those words (a link, button, heading or label; typed field contents never match) is on screen and leaves the pointer on it (when agent-desktop found the match instead of the app's own tree it cannot, so the pointer stays), so `click` opens it. An exact match wins over one that starts with the words, then one that contains them; a leading `the` is ignored. Bare `find` is still command-F. With nothing on the page the row says `no match for <words> on this page`. The model has the same `find` action, which does not move the pointer and lists the match first in its next step (when the find is the step's last action and number badges are not showing) |
| `scroll to <words>` | The same as `find <words>`. `scroll to the top` and `scroll to the bottom` are not finds: they go to the model |
| `grid`, `zoom 35`, `show numbers`, `hide` | Targeting overlays |
| `open safari` | Opens or focuses an app |
| `open youtube`, `open youtube.com`, `open reddit in safari` | Opens a website in your default browser, or in the named one (known site names: YouTube, Gmail, Google, Reddit, GitHub, Wikipedia, Netflix, Amazon and others; any `name.com` works) |
| `start dictating` / `stop dictating` | Switch between command and dictation mode |
| `scratch that` (dictation) | Deletes what your last dictated phrase typed |
| `delete word` (dictation) | Deletes the previous word |
| `go to sleep` / `wake up` | Pause and resume listening |

With `attentionWord` set (see Configuration), start each command with it: `computer, new tab`. Commands without it are ignored.

In a browser, number badges and `click <name>` cover the page's links, buttons and fields as well as the toolbar; `show numbers` and `click <name>` can take up to about half a second longer in a browser than in other apps, and the first one in a Chromium browser such as Chrome (once per launch of the browser) about a second longer while the page's accessibility tree is built.

In dictation mode, say `period`, `comma`, `question mark`, `new line`, `new paragraph`, `open quote` and similar to insert punctuation.

## CLI tools

`nohands-cli` exercises the pieces without the menu-bar app (`swift run nohands-cli <subcommand>`). Subcommands that act on other apps need Accessibility for your terminal and wait a few seconds so you can focus the target app. `task` with `visionFallback` on (see Configuration) also needs Screen Recording for your terminal, and sends pictures of the focused window to Claude on the steps described under Vision fallback.

| Subcommand | Does |
|---|---|
| `type "<text>"` | Waits 2 s, then types the text |
| `key "<chord>"` | Presses a key chord, e.g. `"command shift s"` |
| `click-at <x> <y>` | Clicks at screen coordinates |
| `move <x> <y>` | Moves the pointer |
| `transcribe <wav>` | Transcribes an audio file and prints timings |
| `vad-test <wav>` | Prints voice-activity events for an audio file |
| `endpoint-test <wav>…` | Replays each file through the VAD, the early close and the speech recognizer, and prints the early and full text, whether the early close fired and was accepted, and the milliseconds from the true end of speech to the early text; ends with a summary line |
| `bench <dir>` | Dry-run latency benchmark: replays each `.wav` in the folder through the VAD, early close and speech recognizer, parses the text, and prints per-file lag, recognition and parse times plus p50 and p95 per stage; executes nothing and calls no model backend (the speech models download on first use, so a first run needs the network). Phrase list and a generator script: `Tests/Fixtures/audio/README.md` |
| `elements` | Lists the frontmost app's actionable elements |
| `click "<name>"` | Clicks the named element |
| `grid` | Shows the 10×8 grid, zooms into cell 35 |
| `labels` | Shows numbered badges on the frontmost app's elements |
| `parse "<text>"` | Dry run: prints the actions the grammar produces (or "no match -> LLM", or "rejected: ..." for a `spell` with an unknown word, e.g. `parse "spell capital kilo nine x ray"`); executes nothing |
| `run "<phrase>"...` | Executes grammar phrases in order |
| `observe` | Prints what the task loop sends the model about the frontmost app: window title, URL, a `Media:` line (`playing`, `paused` or `none`) and numbered elements with roles |
| `resolve "<text>"` | Dry run: sends text and the frontmost app's labels to the configured backend and prints the step (`intent`, `status`, actions); executes nothing (Claude spends API credit) |
| `task "<goal>"` | Waits 3 s, then runs the goal as a multi-step task on the frontmost app for real, printing each step's intent, actions and settle time, then the outcome; Ctrl-C stops it like "stop", a second Ctrl-C quits at once (status 130); exits 2 when the task ends stuck, failed or stopped |
| `scenarios [file] [--only name]` | Waits 3 s, then runs each scripted task goal in `scripts/task-scenarios.json` (or `file`) for real, one at a time, and scores it against a fresh screen check rather than the model's word: `pass`, `false-done` (the model said done, the screen disagrees), `unclaimed` (the screen is right but the task did not end done), `fail`, `stopped`, `start-failed` or `not-run`. Prints each scenario's steps and time, then a summary and a markdown table. Exits 0 only when every scenario passes, 2 otherwise (1 for a bad file or `--only` name). It takes over the screen, mouse and keyboard for several minutes and leaves tabs open: close the tabs an earlier run left first. Ctrl-C stops the suite; a second quits at once (130) |
| `listen` | Microphone to VAD to speech recognition, printing transcripts |
| `claude-check` | Sends one small request to Claude with your key (the app's real step request, asking for one token) and prints whether commands will work: connected, key rejected, model not found, request rejected (with the API's message, key hidden), rate limited, unavailable, timed out, no network, or no key (nothing is sent). Exits 0 only when connected. Spends about one step's input tokens |
| `desktop-status` | Where the agent-desktop binary was found, its version, what it reports for Accessibility, and the harness in use |
| `snapshot [app]` | Waits 3 s, then prints the task-loop observation of the frontmost (or named) app as agent-desktop sees it: a `Media:` line and numbered elements with roles, values and states |

## Configuration

Optional file at `~/.config/nohands/config.json`. Every key may be omitted. For the bundled app this file is the way to supply the API key, and the menu's Set Claude API key… (Change Claude API key… once one is saved) writes it for you: `ANTHROPIC_API_KEY` in the environment overrides the file, but it only reaches the app when you run the binary from a terminal or set it with `launchctl setenv ANTHROPIC_API_KEY ...`. The file holds a secret: Set Claude API key… leaves the file mode 600 and the folder mode 700 (to set it by hand, run `chmod 600 ~/.config/nohands/config.json`); NoHands logs a warning at launch if it contains a key and is readable by other users. Invalid JSON falls back to defaults and is flagged in the menu. The menu's Open config.json… creates the file (`{}`, mode 600, in a `~/.config/nohands` folder of mode 700) if it is missing and opens it in your default editor; Open config.json… never changes an existing file. Set Claude API key… keeps every other setting but rewrites the file sorted and indented, and refuses a config.json that is not valid JSON or a symlink (fix it by hand first). The Model item does the same for `intentBackend`, except that it keeps the file's existing mode (a new file is mode 600). Changes apply after a restart, except `intentBackend` set from the Model item, which applies from the next command.

The menu's Claude line says what is set up, from the config alone and with no network traffic: `Claude: key set (config.json)` (or `ANTHROPIC_API_KEY`), `Claude: no key, using the local model`, or `Claude: not used (intentBackend = local)`. Choose Check Claude connection to test it: NoHands sends one small request (the real step request, asking for one token) and the line then reads, for example, `Claude: connected at 14:32` or `Claude: key rejected at 14:32, check anthropicAPIKey`, until you restart or switch model. The check runs only when you choose it, and spends about one request's input tokens. `nohands-cli claude-check` does the same from a terminal and prints the API's full error message when it rejects the request. The key itself is never shown.

```json
{
  "anthropicAPIKey": "sk-ant-...",
  "intentModel": "claude-haiku-5-5",
  "intentEffort": "low",
  "intentBackend": "auto",
  "localModel": "qwen2.5:7b-instruct",
  "ollamaURL": "http://127.0.0.1:11434",
  "asrModelVersion": "v2",
  "silenceMs": 1000,
  "earlySilenceMs": 350,
  "mergeWindowMs": 500,
  "mergeWindowUnfinishedMs": 1500,
  "gridColumns": 10,
  "gridRows": 8,
  "moveStepPx": 50,
  "scrollStepLines": 5,
  "maxTaskSteps": 12,
  "maxMediaTaskSteps": 24,
  "llmDeadlineMs": 12000,
  "settleMs": 3000,
  "maxObservedElements": 120,
  "localLlmDeadlineMs": 30000,
  "localMaxObservedElements": 40,
  "echoCancellation": true,
  "attentionWord": "",
  "visionFallback": false
}
```

**Echo cancellation.** `echoCancellation` (true by default) turns on macOS voice processing on the microphone, which removes what the Mac's own speakers play before NoHands listens. Set it to `false` if an external audio interface does its own processing and the two clash. If macOS refuses voice processing, NoHands keeps listening without it and says so in the log.

**Attention word.** `attentionWord` (empty by default, which means off) makes command mode act only on utterances that start with it: with `"computer"`, `computer, new tab` opens a tab and `new tab` on its own does nothing, with no HUD or row. It can be up to three words; a longer value, or a stop phrase such as "stop", is treated as off. The word is matched in the transcript, not acoustically, so pick a word the recognizer hears reliably and that you don't say in passing; if it mishears the word, the command is silently ignored. `stop` (and `computer, stop`), `wake up` and the dictation escapes (`stop dictating`, `command mode`) work with or without the word. Dictation mode still types everything it hears. Say the word first: "computer, stop" stops, "stop, computer" does not. Don't pick a command phrase such as "start dictating" as the word.

**Task loop keys.** `maxTaskSteps` (1 to 30) is how many observe-and-act steps a multi-step request may take. `maxMediaTaskSteps` (1 to 30, default 24) replaces it for a request to play or watch something (it has a word like play, watch, stream, video, game, match, movie, episode or listen), because stream sites throw overlays and pop-unders before the play button. `llmDeadlineMs` (2000 to 60000) is how long each model call may take. `settleMs` (0 to 10000) is the most time, in wall-clock terms and including the time spent reading the screen, to wait for the screen to stop changing after an action (and before the first step only when a Chromium browser's page content was just switched on). The wait depends on what the step did: none after a `wait` or a read, one short pause after typing or scrolling, and polling up to `settleMs` after a click, a page or app open or Return; `settleMs` is the most it can take. `maxObservedElements` (10 to 300) caps how many on-screen elements are sent to the model. When the local model is the backend, `localLlmDeadlineMs` (2000 to 120000, default 30000) and `localMaxObservedElements` (10 to 300, default 40) replace those two: a 7B model on an M1 Pro needs 5 to 20 s per step, and every element costs about 14 prompt tokens.

**Vision fallback.** `visionFallback` (false by default) lets a task step send a picture of the focused window to Claude when the accessibility tree has failed the model. It works only with Claude as the intent backend (the local model never gets a picture, whatever this key says) and needs the Screen Recording permission. See [Multi-step tasks](#multi-step-tasks) and [Privacy](#privacy).

**Pausing mid-command.** You do not have to say a command in one breath. `silenceMs` is how long you can go quiet before the recognizer closes an utterance (1 s by default). A complete command that is not left open for more words (a key command, a mode change, a numbered click, scroll, move) and a stop phrase are the exception: they close after `earlySilenceMs` of quiet (about 350 ms by default, one 256 ms voice-detector chunk), so "new tab" or "stop" acts well before a full second passes. Commands that carry words you may still be saying (`type …`, `open …`, `go to …`, `search for …`, `click <name>`), anything the grammar does not parse, and anything said while words are already held keep `silenceMs`; dictation and sleep always do. Set `earlySilenceMs` to 0 to turn this off; the catch is that a pause of 350 ms or more inside a closed command acts on the first part ("click twenty … three" clicks 20). After the full silence, a transcript the fast grammar does not already understand is held for `mergeWindowMs` (longer, `mergeWindowUnfinishedMs`, when it starts with `spell`, which the grammar understands but holds so a pause mid-spelling stays one string, or when it ends on a word like "the" or "click" that leaves the command hanging); its row on the prompt board shows `listening…`. If you start speaking again inside that window, the next piece is appended and the whole thing is treated as one request, so "click the … uh, the back button" reaches the model as a single sentence. Set both windows to 0 to act on every utterance at once. A stop phrase ("stop", "cancel", "never mind", also "stop stop" or "um, stop") is never held or merged: it goes through at once, and in command mode it also discards the unfinished words before it. In dictation, "stop dictating" and "command mode" likewise go through on their own instead of being typed as part of the text, and so do "scratch that" and "delete word".

**How the model reads a request.** The transcript comes from speech recognition, so the model is told to first write a one-sentence `intent` (what you meant, with recognition errors, filler and self-corrections resolved) and only then the actions that carry it out. `intentEffort` (`low` … `max`) sets how hard Claude thinks before answering; `low` is the default and the fastest.

The default model is `claude-haiku-5-5` at `low` effort, chosen for cost. For a stronger model, set `"intentModel": "claude-opus-5-5"` and `"intentEffort": "medium"` in `config.json` and restart. Haiku has no server-side fallback, so a request the model declines is not retried on another model; it just fails with the usual "didn't catch that" row.

## Multi-step tasks

A request the fast grammar does not understand runs as a task: NoHands looks at the frontmost app (window title, URL and up to `maxObservedElements` numbered on-screen elements; while number badges are shown, the model sees the same numbers as the badges), asks the model for the next step, runs that step's actions, waits for the screen to stop changing (how long depends on what the step did, and `settleMs` is the most it can take), and looks again. Each step's answer is a one-sentence `intent`, a `status` (`continue`, `done`, `stuck` or `ignore`) and a few actions; the prompt's row shows `step n · <intent>` (and `✗ <why>` after a step whose actions failed). "Open Veritasium's latest video" becomes: open the channel's Videos tab in the default browser (`open_url`; the browser is named only when you name one), then (after seeing the page) click the first video. Before typing into an app it just opened, NoHands waits for that app to be frontmost and to show a window, so a cold-launched browser does not swallow the keystrokes. The task ends when the model says `done`, says `stuck` (the row shows why), reaches the step cap (`maxTaskSteps`, or `maxMediaTaskSteps` for a request to play or watch something), or proposes the same actions three times in a row; any held mouse button is released when a task does not finish `done`. If the model answers `ignore` after earlier steps already acted, the row shows `stopped: <intent>`. A goal to play, watch, turn on or listen to something is done only when the screen shows media playing: after the model says `done`, NoHands looks once more, and if a Play button is still showing it asks the model once more (`not playing yet`), then ends `stuck` if the video still is not playing. The model can also wait for playback (`wait_for` `media_playing`, polled by NoHands every half second), for example through a pre-roll ad. The finish line ends with the number of steps that ran. As a safety guard in code (not just the prompt), a step that would press command-W is blocked unless your request contains the word close (closes, closing, closed) or shut, and command-Q unless it contains quit (quits, quitting), exit (exiting) or shut. Whole words only, and per key: "close this tab" does not allow quitting the app. Nothing from a blocked step runs and the model is told it was blocked. A step that would press a button or menu item named send, delete, remove, discard, pay, buy, purchase, checkout, confirm, submit, publish, post, unsubscribe, transfer, place order or empty trash (a click, cursor move, focus, `set_value`, `select_option`, `type_into` or `set_checked` on it by name or number, where a partial name counts as any button it could find for it (the one with exactly that title, else any whose title contains it), a menu path that contains the word, or Return while that button has focus, which needs the agent-desktop harness to see the focus) is not run until you confirm, unless your request already says that verb (any form, not after "not" or "don't": "send the reply" allows Send, and only Send; "buy a lamp" still asks before Place order). The row shows `step n · say yes to <verb>` for 30 seconds. Say "yes", "confirm" or "do it" (with "please" if you like; when you have set an attention word, start with it, so a "yes" from a TV does not count) and the step runs; any other words, silence, or "stop" ends the task with nothing run, and the row shows `stopped: <verb> not confirmed`. Whole words only ("Sender", "Sent" and "Posts" are not asked about), a yes covers that one step and the verbs it named (a step with both Send and Delete asks `say yes to send and delete`), and the grammar commands you say yourself ("click send") are not asked about. Three more code-level fixes catch slips a small local model makes. A `type_text` that is a whole web address (`http(s)://`, `www.`, or a common ending such as `.com`) is opened as `open_url` instead of typed, and a bare Return right after it is dropped; this does not apply when your request says to type or write text, or when the step first ran `open_app` or `command-l`. A click on an app's menu-bar item, by number or by name, is refused as a failed step unless your request mentions a menu or says the item's own words ("click edit, click copy"), and not while number badges are showing; in a task the menu bar is numbered after the page's elements, and a click by name goes to the page element with that exact title. After two identical steps in a row the model is told to try a different approach, because a third identical step ends the task.

**Site routes.** When a request names YouTube, Google, Wikipedia, Amazon or Reddit, or the page is on one of them, the model also gets a few fixed lines on how to get around that site (for example, the search URL and what to click on the results page), written by NoHands and never taken from the page.

**Planned goals.** A goal that looks multi-step (four or more words, about playing media or naming a website, and not naming a browser or saying "this", "current" or "here") first asks the model once for a short plan, written from your words alone: two to eight steps from a fixed set (open a supported site, search a supported site, click an element by its title, click the first item in the page's content, wait for media to play), each with a check of what the screen should show afterwards. The model picks each site from the list of supported sites (the ones NoHands knows a search page for) and never writes a web address: NoHands builds every address itself, and a plan whose open or search step names any other site, or that does not begin by opening or searching a site, is thrown away. NoHands runs the plan in code and reads each check against the screen, so the model does not have to choose every step from a long element list. Every plan step goes through the same guards, step cap and "stop" as a model step, and a plan whose checks and searches do not name something from your request is thrown away. For a request to play something, NoHands adds a final wait-for-media step when the plan lacks one (a plan already at eight steps is thrown away instead). The prompt's row shows `Thinking · planning the steps` while the plan is being written. If a check misses (after one extra look 1.5 s later), a click finds nothing, or a step fails, the plan ends and the usual step-by-step loop takes over from there with the plan's steps as its History. Other goals run exactly as before. While a plan runs NoHands reads up to 200 elements per step (the lists are not sent to the model); the usual `maxObservedElements` cap applies again once the plan ends.

**Vision fallback (off by default).** Some controls have no accessible name or are not in the element list at all, such as a video player's play button. With `"visionFallback": true`, Claude as the backend and Screen Recording granted, NoHands attaches a JPEG picture of the focused window (not the whole screen; at most 1200 px on the long side) to a step in three cases: the previous step failed because its named target was missing or stale (`no element named …` or `element changed, …`; `no label N` does not count), the model asked for one with the `look` action, or the model answered `stuck` on a step that had no picture (NoHands then looks once and asks again at the same step; this does not use up a step, and a `stuck` that already had a picture ends the task). The prompt's row shows `step n · looking at the screen`, or the reason there is no picture (`screen recording not granted`, `screen capture failed`, or `a menu or sheet is open`, since a single-window picture would leave the menu out); the task goes on without the picture. If the grant is missing when the model answers `stuck`, the task ends and its message names it. `look` takes no fields and changes nothing on screen; its picture arrives with the next step, and number badges on screen are drawn into it with the same numbers as the element list. When the picture is there, the model may click with a picture point: `target_kind` `point` with `x` and `y` in the picture's pixels, (0, 0) at its top-left. NoHands maps the point to the screen. A point is valid only on the step that carries the picture (on any other step with vision on it is refused with `point needs a screenshot: say look first`, which gets a picture on the next step), must be the first action of that step, and only one action in the step may use one (a click, a cursor move, or a drag's start and end). A point outside the picture is refused, and if the window moved or another app came to the front since the picture, nothing runs and the step fails with `element changed`, which gets a fresh picture on the next step. Clicking a window's or tab's close box with a point is not blocked by code: only the prompt tells the model not to close anything the request did not ask to close, so keep `visionFallback` off if you cannot accept that risk. The other guards (command-W and command-Q, tabs the task did not open) still apply to every step.

**Pop-ups and extra tabs.** An ad blocker in your browser is the first line of defence against pop-ups; NoHands closes what gets through. In a browser the model sees a numbered list of windows and tabs and can close a tab or window with `close_tab` and `close_window` (and switch with `select_tab`), but only one the task itself opened since it started: a tab or window that was already open is never closed unless your request says close, and neither is the tab the task navigated to. It dismisses cookie banners and "click to continue" layers with their own close control, waits out countdowns, and sets `done` for a request to play something only when the video is playing. Tabs are read through Accessibility (no extra permission); Chrome and Safari show their tabs, a browser that hides its tab strip is read by windows only. Browser steps send up to 20 tab titles, plus the titles of new tabs and windows, to the configured intent backend like window titles, and never anywhere else.

**Stopping a task.** Say "stop" (or "cancel", "never mind", "abort", "stop the task"; repeats and fillers such as "stop stop" or "no, stop" count too). It aborts the request or action in flight; the task's row shows `stopped` and the stop's own row `stopping the task`. From the CLI, Ctrl-C stops `nohands-cli task` the same way; a second Ctrl-C quits at once.

**Talking while a task runs.** Anything else you say while a task runs is held, and its row shows `held · runs after this task (say stop to cancel)`. Only the newest utterance is kept: saying something else replaces it, and the replaced utterance's row shows `dropped`. It runs once the task ends, unless it is more than 60 seconds old by then or you said "stop" (which drops it along with the task); either way its row shows `dropped` and nothing from it runs.

**Config.** `maxTaskSteps` (default 12), `maxMediaTaskSteps` (24, for requests to play or watch something), `llmDeadlineMs` (12000, per model call), `settleMs` (3000) and `maxObservedElements` (120); with the local backend, `localLlmDeadlineMs` (30000) and `localMaxObservedElements` (40) apply instead of the last two. See [Configuration](#configuration).

### agent-desktop harness

With [agent-desktop](https://github.com/vercel-labs/agent-desktop) installed (`npm i -g agent-desktop` or `brew install agent-desktop`, macOS 13+), tasks observe and act through it instead of NoHands' own accessibility walk and synthesized clicks. The menu shows `Harness: agent-desktop <version>` when it is in use and `Harness: native (…)` with the reason when it is not. The harness is picked when NoHands starts listening; the menu re-checks each time it opens and adds `restart NoHands to use it` once an install or a permission grant would change the pick. `nohands-cli desktop-status` prints the same.

What changes with the harness:

- **Observation.** Each step snapshots the frontmost app's accessibility tree through agent-desktop: elements keep stable references, and the model also sees each field's current value (`= "cats"`) and states (checked, selected, disabled, expanded, offscreen). When an action opens a sheet, menu, alert or popover, the next step lists that surface's elements instead of the window's (`Surface: sheet`).
- **Actions on elements** land on the element, not on a point: `click` presses the element semantically, with a real click only when agent-desktop reports it delivered nothing. New model actions: `set_value`, `type_into`, `clear`, `select` (dropdown option), `check`/`uncheck`/`toggle`, `expand`/`collapse`, `focus`, `scroll_to`, `scroll_element`, `drag`.
- **Menus, Dock and dialogs by name.** `menu_item` runs a menu bar command by its name ("Save As…"); `click_in` clicks a named item in a surface (`dock`, `menubar`, `sheet`, `alert`, `popover`, `menu`, `menu_bar_extras`).
- **Apps, windows, clipboard, notifications.** `close_app` (guarded like command-Q: the request must say quit, exit, shut or close), `window` (minimize, maximize, restore, focus by app and title), `clipboard_set`, `read_clipboard`, `read_value`, `read_notifications`, `dismiss_notifications`. What a `read_*` action read arrives in the next step under `Read:`; a task that finishes with a reading shows it on its row.
- **Typed waits.** `wait` with `wait_for` blocks on a signal (text appearing, a window title, a menu opening or closing, an element becoming actionable, or a lifecycle event such as `window_opened`) instead of a fixed pause. `wait_for` `media_playing` also works without agent-desktop.

The harness is chosen once per task from its first observation: if agent-desktop cannot read the frontmost app (no window, the window is on another Space or minimized, a locked screen), the whole task runs natively, with the same loop and prompt board. On the local backend such a task uses the native prompt, which is not the prefix the warm-up cached, so its first step pays the full prefill once. Grammar commands ("click 12", "type hello", "press command s") and dictation never go through agent-desktop. Physical input (`--headed`) is used only after agent-desktop says nothing was delivered, so a click or a submit is never doubled.

**Config.** `desktopHarness` (`auto`, default: agent-desktop when found and Accessibility is granted; `agentDesktop`; `native`), `agentDesktopPath` (absolute path; by default `/opt/homebrew/bin`, `/usr/local/bin`, `~/.bun/bin`, `~/.volta/bin`, `~/.npm-global/bin`, `~/.local/bin`, every nvm node version and `PATH` are searched, since an app started with `open` has no shell PATH), `agentDesktopTimeoutMs` (8000 per action), `agentDesktopSnapshotMs` (3000 per snapshot), `agentDesktopHeadedFallback` (true), `agentDesktopTrace` (false: when true each task runs in an agent-desktop session whose trace, with text fields redacted, is under `~/.agent-desktop/sessions`). agent-desktop needs the Accessibility grant for NoHands itself, which NoHands already requires.

**Claude vs. the local model.** Switch with the menu's Model item (see [Configuration](#configuration)); no restart is needed. Use Claude for multi-step tasks. The local model is not yet proven for them: in the recorded runs with `qwen2.5:7b-instruct`, the cold first request timed out and the warm one answered `ignore`; no task has completed successfully on it so far. It may still handle simple one-step requests. Each step costs the model 5 to 20 s on an M1 Pro (about 2,200 prompt tokens of instructions and examples, plus the screen, decoded at about 14 tokens per second), so the local backend gets its own `localLlmDeadlineMs` (30 s) and sends at most `localMaxObservedElements` (40) elements. While NoHands is listening it warms the model every 20 minutes by running that fixed prefix through Ollama, so it sits in Ollama's prompt cache; the first command after a warm-up skips that part of the wait. Requests that still end with "timed out" mean the machine is short on memory (check swap use) or `localLlmDeadlineMs` needs raising.

## Privacy

Audio never leaves your machine. Only commands the grammar can't match are sent to Claude (or to the local model, which stays on your Mac), as text: your transcript, the frontmost app's name and the titles of its visible controls. Multi-step task steps also send the focused window's title, the page URL (in a browser) and each element's role, to Claude or to the local model alike. They also send a `Media:` line (`playing`, `paused` or `none`), read from the window's Play or Pause buttons or, when there are none, from whether another app is producing sound; no audio or title is sent. With the agent-desktop harness, each listed field's current value (what is typed in a search box or a form, cut at 60 characters) is sent too; clipboard text, a full element value and the notification list are sent only in the step after the model explicitly asked to read them. Text handed to agent-desktop (`set_value`, `type_into`, `clipboard_set`) travels in the child process's arguments, visible to `ps` while it runs. The plan request for a goal that looks multi-step sends only your transcript. Without an API key nothing is sent off the Mac; with the local backend, text goes only to Ollama on `127.0.0.1`.

**Screenshots.** With `visionFallback` on, pixels leave the Mac only on the task steps described in [Multi-step tasks](#multi-step-tasks) (a failed named target, a `look`, or a `stuck` retry), and only to Claude: the local model is never sent a picture, and nothing is captured when the backend is local or the flag is off. The picture is the focused window only, and shows whatever that window shows, including text, messages and passwords visible in it. It is held in memory for the step, is never saved to disk and is not logged.

**There is no wake-word model.** By default everything the microphone hears is acted on; the optional `attentionWord` makes command mode ignore speech that doesn't start with it. It is matched in the transcript, so audio is still transcribed on the Mac. Echo cancellation removes what the Mac's own speakers play, but other people talking, a phone on speaker or very loud playback can still be heard, so "go to sleep" is still the safe choice for calls. Any audio the microphone still hears is transcribed, acted on unless `attentionWord` filters it out, and in dictation mode it is typed into the focused app. With an API key, phrases the grammar doesn't match are also sent to Claude as text. Say "go to sleep" before leaving the desk or during calls; only "wake up" is honored while asleep.

## Layout

| Path | Contents |
|---|---|
| `Sources/NoHandsCore` | Pure logic: grammar, formatting, modes, geometry, Claude request and response handling |
| `Sources/NoHandsMac` | macOS integration: audio, speech models, input events, accessibility |
| `Sources/NoHands` | The menu-bar app |
| `Sources/nohands-cli` | Command-line tools for testing each piece by hand |
| `docs/superpowers` | Design spec and implementation plan |
| `LICENSE`, `THIRD_PARTY_LICENSES.md` | Apache-2.0 licence and third-party notices |
| `CONTRIBUTING.md`, `SECURITY.md` | How to contribute and how to report a vulnerability |
| `.github` | Issue and PR templates |

## Design

See [the design spec](docs/superpowers/specs/2026-11-04-nohands-design.md) and [the implementation plan](docs/superpowers/plans/2026-11-04-nohands-voice-control.md).

## License

NoHands is under the [Apache License 2.0](LICENSE). Third-party notices are in [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md).

Speech and local models are downloaded at run time and keep their own licences: the Parakeet speech models are CC-BY-4.0, Silero VAD is MIT, and Qwen 2.5 7B is Apache-2.0. The 3B Qwen model, the low-memory default for the local backend, is research-only and not for commercial use; see THIRD_PARTY_LICENSES.md. To change it, set `localModel` in the config file.

To report a security problem, see [SECURITY.md](SECURITY.md). To contribute, see [CONTRIBUTING.md](CONTRIBUTING.md).
