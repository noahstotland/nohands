<img src="assets/icon.svg" width="64" height="64" alt="NoHands logo">

# nohands

Control your Mac with your voice and nothing else. Dictate into any app, press shortcuts, move and click the mouse, and give natural-language commands. Speech recognition runs on-device, so ordinary commands never touch the network.

> **Status: work in progress.** Not yet verified on real hardware against real apps.

## How it works

```
mic → Silero VAD → Parakeet speech recognition (on-device)
    → mode machine ─┬─ dictation  → formatter → type text
                    ├─ command    → fast grammar (no network) → actions
                    │                └ unmatched → Claude → actions
                    └─ sleep      → only "wake up" is honored
    → executor: keyboard/mouse events, accessibility lookups, grid and label overlays
```

- **Fast path:** a deterministic grammar matches common commands in under a millisecond.
- **Targeting:** "show numbers" labels clickable elements; "grid" overlays a numbered 10×8 grid. Claude or Ollama is optional.

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

Build from an up-to-date `main` (`scripts/bundle.sh` warns when behind `origin/main`). A menu-bar app (no Dock icon) showing `CMD`, `DICT` or `ZZZ` for the mode.

- **Prompt board.** One row per spoken prompt at the top of the pointer's screen: blue while live (`listening…`, `heard`, `Reading · looking at the screen`, `step n · <intent>`, `✗ <why>`), yellow `held`, green `done`, red `failed`, `dropped` or `skipped (busy)`, grey `stopped` or ignored. Finished rows stay 1.5 s (3 s if failed or dropped); at most four; notices (`NoHands is listening`, `microphone error`) show above. Details: `docs/superpowers/specs/2026-11-08-nh-71-no-hands-rows-design.md`, `docs/superpowers/specs/2026-11-15-nh-118-thinking-progress-design.md`.
- **Status bar.** Bottom right of the pointer's screen, below the corner panel; shows only with something to say (`Dictating`, `Asleep · say wake up`, `Paused`, `Loading speech model…`, a task step, a problem with its fix); hides with the grid or number badges. Off or Bottom Right from the menu (macOS user defaults, not `config.json`). Details: `docs/superpowers/specs/2026-11-07-nh-66-status-bar-overlay-design.md`, `docs/superpowers/specs/2026-11-15-nh-92-status-bar-corner-design.md`.
- **Corner panel.** While a request runs: what you said, the steps (`✓`, `✗`, a dot), a phase line (`Reading`, `Thinking` or `Acting`), `step 3` with no total; the outcome stays 1.5 s (3 s for a failure). Details: `docs/superpowers/specs/2026-11-08-nh-70-corner-overlay-design.md`.
- **Recent commands and View Logs.** The last 50 commands, newest first, as `<what you said> · done|failed|stopped|ignored`; each opens in the NoHands Logs window (handler, steps, Claude calls and tokens: `4 calls · 12,340 in · 48,100 cache read · 3,200 cache write`). Details: `docs/superpowers/specs/2026-11-15-nh-111-view-logs-design.md`.

**First run:**

1. **Microphone:** macOS asks at start; on Don't Allow the menu shows "Microphone denied" with an open-Settings item.
2. **Accessibility:** enable NoHands under System Settings > Privacy & Security > Accessibility; a red "Grant Accessibility…" item shows until granted.
3. **Screen Recording** (optional): with `visionFallback` on and Claude as backend, a red "Grant Screen Recording…" item opens System Settings > Privacy & Security > Screen & System Audio Recording; it often applies after a relaunch. Without it steps run without a picture (`screen recording not granted`).
4. NoHands listens only once Microphone and Accessibility are granted, re-checking Accessibility every few seconds.

**Ad-hoc signature:** every rebuild is a new app to macOS, so re-grant Microphone, Accessibility and Screen Recording each time. A stable identity avoids this:

```bash
CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" scripts/bundle.sh
```

**Start at Login:** a menu item registers a login item and shows a tick; if turned off in Login Items it says `allow in Login Items`. Disabled under `swift run`.

**Logs:** each utterance logs `[asr=…ms total=…ms sinceVoice=…ms] <transcript> -> <what it did>`, plus `claude: step N <ms>ms cache=<read>/<written> in=<n> out=<n>`, `claude: session calls=<n> in=<n> cache=<read>/<written> out=<n>` (when each Claude task ends, the running total for this app session), `ollama: step N <ms>ms` and `intent backend: claude|local|off` lines:

```bash
log stream --predicate 'subsystem == "dev.nohands.app"'
```

Transcripts log as `<private>` unless private data logging is on (`sudo log config --mode "private_data:on"`); running `build/NoHands.app/Contents/MacOS/NoHands` from a terminal prints full lines.

**Claude API key:** shell exports do not reach an app started with `open`. Choose **Set Claude API key…**, paste, restart; saved to `~/.config/nohands/config.json`. Without a key, natural-language commands show "LLM off".

## Local model (no API key)

Ollama on your Mac: nothing leaves the machine; works offline once downloaded.

```bash
scripts/setup-local-model.sh            # picks a model by RAM
scripts/setup-local-model.sh qwen2.5:3b-instruct   # or name one
```

Installs Ollama with Homebrew if needed, starts it, pulls the model, smoke tests; safe to re-run. The menu can also download the model. Ollama from brew starts at login (`brew services`). The menu can also download the model.

- **Default model:** `qwen2.5:7b-instruct` with 12 GB of RAM or more, else `qwen2.5:3b-instruct` (free RAM about 5 GB and 2 GB).
- **Backend:** `intentBackend` is `auto` (Claude when a key is set, else local), `claude`, `local` or `off`. The menu's **Model: …** item switches Claude and local with no restart; the Claude row is greyed out until a key is in effect. `auto` and `off` are file-only. Details: `docs/superpowers/specs/2026-11-09-nh-116-backend-toggle-design.md`.
- **Server:** `localModel` and `ollamaURL` (`127.0.0.1`, `localhost` or `::1` over `http` only).
- **If it fails:** `local model not running: start Ollama` or `local model not downloaded: see the NoHands menu`.

## Voice commands

| Say | Does |
|---|---|
| `type <words>` | Types the words, spoken punctuation applied |
| `spell <letters>` | Letters, NATO words (`kilo`, `x ray`), digits, `space`, `dash`, `dot`, `underscore`, `at sign` as one string; `capital` uppercases the next letter (`spell capital kilo nine x ray` types `K9x`) |
| `press command shift s` | Presses a key chord |
| `enter`, `tab`, `escape`, `delete`, arrow names | Presses that key |
| `undo`, `redo`, `copy`, `paste`, `cut`, `select all`, `save`, `find` | Standard shortcuts |
| `new tab`, `close tab`, `close window`, `quit app`, `switch app`, `spotlight` | App and window shortcuts; filler ignored (`close the current tab`, `close this window`) |
| `minimize`, `full screen`, `hide app`, `reload` / `refresh` | Window and app shortcuts |
| `left half`, `right half`, `snap left`, `top left`, `maximize`, `center window` | Moves and resizes the front window; richer phrasing such as `make the window half width and snap to the left side of the screen` goes to the model |
| `go back`, `go forward`, `next tab`, `previous tab` | Browser and tab navigation |
| `tab 3`, `tab number 3`, `switch to tab 3`, `go to tab 3`, `first tab`, `last tab` | Tab 1 to 99; outside a browser `no browser in front` |
| `switch to the YouTube tab`, `go to the YouTube tab`, `open the YouTube tab` | Tab by title; miss: `no tab called …` |
| `close the other tabs`, `close other tabs`, `close all other tabs` | Close Other Tabs menu item; none (Chrome): `no Close Other Tabs menu item in …` |
| `list tabs`, `list the tabs`, `list my tabs` | Board line for a few seconds: `1 YouTube · 2* Inbox · 3 GitHub` |
| `go to <site>` | Site or domain in the default browser; other text goes to the address bar |
| `search for <words>` | The page's or app's search box, else a known results page (YouTube, Google, Amazon, Reddit, Wikipedia…), else the address bar. Refused: `javascript:`, `file:`, `chrome:`, any `scheme:text`: `can't search for that` |
| `search for <words> on <site>`, `search <site> for <words>` | That site's search box if in front, else its results page |
| `is it playing`, `is the video playing`, `is anything playing` | Row says `playing`, `paused` or `none` |
| `click`, `double click`, `right click`, `middle click` | Clicks at the pointer |
| `click 42` | Clicks label or grid cell 42 |
| `click save` | Clicks the element named "save" |
| `click first video`, `click the second result`, `click the 3rd link`, `click last video` | With no exact title, the position among numbered elements (`first` to `tenth`, `1st`, `2nd`, … `last`); too few: `no element named …; say its label number from the list` |
| `hold click` / `release click` | Press and release the button (drag) |
| `move up 100`, `move to 12` | Moves the pointer |
| `scroll down 10` | Scrolls |
| `find <words>` | Scrolls until text or an element with those words shows, pointer left on it; bare `find` is command-F; none: `no match for <words> on this page` |
| `scroll to <words>` | Same as `find <words>`; `scroll to the top` and `scroll to the bottom` go to the model |
| `grid`, `zoom 35`, `show numbers`, `hide` | Targeting overlays |
| `open safari` | Opens or focuses an app |
| `open youtube`, `open youtube.com`, `open reddit in safari` | Website in the default or named browser (any `name.com` works) |
| `start dictating` / `stop dictating` | Switch between command and dictation mode |
| `scratch that` (dictation) | Deletes what your last dictated phrase typed |
| `delete word` (dictation) | Deletes the previous word |
| `go to sleep` / `wake up` | Pause and resume listening |
| `menu <words>` | Presses the front app's menu item through Accessibility, e.g. `menu bookmark this tab`, `menu save as`; none: `no menu item called <words>`; greyed: `menu item <title> is disabled`; the Apple menu is never searched (no `menu shut down`) |

Details: `docs/superpowers/specs/2026-11-05-nh-10-spell-command-design.md`, `docs/superpowers/specs/2026-11-15-nh-53-browser-tabs-design.md`, `docs/superpowers/specs/2026-11-05-nh-15-search-on-site-design.md`, `docs/superpowers/specs/2026-11-15-nh-93-ordinal-click-target-design.md`, `docs/superpowers/specs/2026-11-15-nh-44-find-on-page-design.md`.

- With `attentionWord` set, start each command with it: `computer, new tab`.
- In a browser `show numbers` and `click <name>` can take about half a second longer (a second on the first per launch in Chromium).
- In dictation mode, say `period`, `comma`, `question mark`, `new line`, `new paragraph`, `open quote` and similar to insert punctuation.

### Per-app commands

An app can have phrases that work only while it is in front and win on a shared phrase. Leading `open`, `go to` and `a` / `the` are ignored in lookup (`open a new tab`, `go to the new tab`, `new tab` are the same); where the app lacks the phrase, `open <phrase>` (two or more words) runs the global one (`open a new tab` presses command-T). Each app adds its rows below. Details: `docs/superpowers/specs/2026-11-15-nh-76-per-app-commands-design.md`.

| App | Say | Does |
|---|---|---|

## CLI tools

`nohands-cli` exercises the pieces without the menu-bar app (`swift run nohands-cli <subcommand>`). Subcommands acting on other apps need Accessibility for your terminal and wait a few seconds so you can focus the target.

| Subcommand | Does |
|---|---|
| `type "<text>"` | Waits 2 s, then types |
| `key "<chord>"` | Presses a chord, e.g. `"command shift s"` |
| `click-at <x> <y>` | Clicks at screen coordinates |
| `move <x> <y>` | Moves the pointer |
| `transcribe <wav>` | Transcribes a file, prints timings |
| `vad-test <wav>` | Prints voice-activity events |
| `endpoint-test <wav>…` | Replays files through VAD, early close and recognizer; prints early and full text and timing |
| `bench <dir>` | Dry-run latency benchmark over each `.wav`: p50 and p95 per stage; no model backend. Phrases: `Tests/Fixtures/audio/README.md` |
| `elements` | Lists the frontmost app's actionable elements |
| `click "<name>"` | Clicks the named element |
| `grid` | Shows the 10×8 grid, zooms into cell 35 |
| `labels` | Shows numbered badges |
| `parse "<text>" [--app <bundle id>]` | Dry run: the grammar's actions, "no match -> LLM", or "rejected: ..." |
| `menu "<words>"` / `menu --list` | After 2 s (3 s for `--list`) presses the frontmost app's named menu item, or lists them |
| `run "<phrase>"...` | Executes grammar phrases in order |
| `observe` | Prints what the task loop sends the model: title, URL, `Media:` line, numbered elements |
| `resolve "<text>"` | Dry run: sends text and labels to the backend, prints the step (`intent`, `status`, actions); spends API credit |
| `task "<goal>"` | Waits 3 s, runs the goal as a task for real, printing each step. Ctrl-C stops it, a second quits (130); exits 2 when stuck, failed or stopped |
| `scenarios [file] [--only name]` | Waits 3 s, runs each goal in `scripts/task-scenarios.json` for real, scored against a fresh screen check: `pass`, `false-done`, `unclaimed`, `fail`, `stopped`, `start-failed`, `not-run`. Exits 0 only when all pass, 2 otherwise (1 for a bad file or name). Takes over screen, mouse and keyboard. Ctrl-C stops; a second quits (130). Details: `docs/superpowers/specs/2026-11-09-nh-49-task-scenarios-design.md` |
| `listen` | Microphone to recognition, printing transcripts |
| `claude-check` | One-token request with your key; prints connected, key rejected, model not found, request rejected, rate limited, unavailable, timed out, no network, or no key. The key is never shown. Exit 0 only when connected |
| `desktop-status` | Where agent-desktop was found, version, Accessibility, harness in use |
| `snapshot [app]` | Waits 3 s, prints the task-loop observation as agent-desktop sees it |

## Configuration

Optional file `~/.config/nohands/config.json`; every key may be omitted. Changes apply after a restart, except `intentBackend` set from the Model item. Invalid JSON falls back to defaults and is flagged in the menu.

| Key | Default | Range / values |
|---|---|---|
| `anthropicAPIKey` | none | `sk-ant-...` |
| `intentModel` | `claude-haiku-5-5` | any Claude model id |
| `intentEffort` | `low` | `low` … `max` |
| `intentBackend` | `auto` | `auto`, `claude`, `local`, `off` |
| `localModel` | `qwen2.5:7b-instruct` | any Ollama model |
| `ollamaURL` | `http://127.0.0.1:11434` | loopback `http` only |
| `asrModelVersion` | `v2` | |
| `silenceMs` | `1000` | |
| `earlySilenceMs` | `350` | `0` turns off |
| `mergeWindowMs` | `500` | `0` acts at once |
| `mergeWindowUnfinishedMs` | `1500` | `0` acts at once |
| `gridColumns` | `10` | |
| `gridRows` | `8` | |
| `moveStepPx` | `50` | |
| `scrollStepLines` | `5` | |
| `maxTaskSteps` | `12` | 1 to 30 |
| `maxMediaTaskSteps` | `24` | 1 to 30 |
| `llmDeadlineMs` | `12000` | 2000 to 60000 |
| `settleMs` | `3000` | 0 to 10000 |
| `maxObservedElements` | `120` | 10 to 300 |
| `localLlmDeadlineMs` | `30000` | 2000 to 120000 |
| `localMaxObservedElements` | `40` | 10 to 300 |
| `echoCancellation` | `true` | |
| `attentionWord` | `""` | up to three words |
| `visionFallback` | `false` | |

The agent-desktop keys are under [agent-desktop harness](#agent-desktop-harness).

- **API key.** `ANTHROPIC_API_KEY` overrides the file but reaches the app only from a terminal or after `launchctl setenv ANTHROPIC_API_KEY ...`. The menu's key item writes the file with mode 600 (folder 700; by hand `chmod 600 ~/.config/nohands/config.json`) and refuses a symlink or invalid JSON; the Model item does the same for `intentBackend` but keeps an existing file's mode (a new file is 600). The key is never shown again. A launch warning is logged if others can read a file holding a key. Open config.json… creates `{}` if missing, never edits an existing file.
- **Claude line in the menu** reads the config alone: `Claude: key set (config.json)`, `Claude: no key, using the local model`, `Claude: not used (intentBackend = local)`. Check Claude connection sends a one-token request: `Claude: connected at 14:32` or `Claude: key rejected at 14:32, check anthropicAPIKey`. Details: `docs/superpowers/specs/2026-11-09-nh-103-claude-status-menu-design.md`.
- **Session total:** once Claude has made a call, a second line shows the running total for this app session, e.g. `Claude this session: 14 calls, 31k in, 9k cached, 2k out` ("in" is fresh input including cache writes, "cached" is cache reads). It counts every call that got a reply, including the connection check and stopped tasks, resets when NoHands restarts (not on config reload or backend change), and holds counts only, never text. Details: `docs/superpowers/specs/2026-11-15-nh-112-token-usage-design.md`.
- **Echo cancellation.** `echoCancellation` removes what the Mac's speakers play (macOS voice processing); set `false` if an external audio interface clashes.
- **Attention word.** `attentionWord` (empty = off): command mode acts only on utterances starting with it (`computer, new tab` works, `new tab` alone does nothing). More than three words, or a stop phrase, counts as off. `stop`, `wake up` and the dictation escapes (`stop dictating`, `command mode`) work with or without it. Details: `docs/superpowers/specs/2026-11-05-nh-12-attention-word-design.md`.
- **Task loop keys.** `maxMediaTaskSteps` replaces `maxTaskSteps` for a request to play or watch. `llmDeadlineMs`: per model call. `settleMs`: the most wait for the screen to settle after an action. `maxObservedElements`: elements sent to the model. The local model uses `localLlmDeadlineMs` and `localMaxObservedElements` instead.
- **Pausing mid-command.** `silenceMs` closes an utterance. A complete command and a stop phrase close after `earlySilenceMs` (one 256 ms chunk), so a pause of 350 ms or more inside acts on the first part ("click twenty … three" clicks 20); open-ended commands (`type …`, `open …`, `go to …`, `search for …`, `click <name>`), unparsed speech, dictation and sleep keep `silenceMs`. Speech the grammar does not understand is then held `mergeWindowMs` (`mergeWindowUnfinishedMs` if it starts with `spell` or ends on a word like "the"), row `listening…`, later speech appended. A stop phrase (see Stopping; also "um, stop") is never held or merged: it goes through at once, and in command mode it discards the unfinished words before it. Details: `docs/superpowers/specs/2026-11-08-nh-36-early-grammar-endpointing-design.md`.
- **How the model reads a request.** A one-sentence `intent`, then the actions. `intentEffort` sets how hard Claude thinks; `low` is fastest. `claude-haiku-5-5` at `low` is chosen for cost; for more, set `"intentModel": "claude-opus-5-5"` and `"intentEffort": "medium"`. No server-side fallback on Haiku.

## Multi-step tasks

A request the grammar does not understand runs as a task: look at the frontmost app (title, URL, up to `maxObservedElements` numbered elements), ask the model for the next step, run it, wait for the screen to settle (`settleMs` at most), repeat. Each answer has an `intent`, a `status` (`continue`, `done`, `stuck`, `ignore` or `ask`) and actions. Details: `docs/superpowers/specs/2026-11-04-task-agent-design.md`.

- **Ending.** On `done`, `stuck`, the step cap (`maxTaskSteps`, `maxMediaTaskSteps` for play or watch), or the same actions three times running. A held mouse button is released unless `done`. `ignore` after earlier steps shows `stopped: <intent>`.
- **Media.** A play, watch or listen goal is done only when media plays: after `done` NoHands looks once more; a visible Play button gets one more model call (`not playing yet`), then `stuck`. `wait_for` `media_playing` polls every half second.
- **Close and quit guard (code).** command-W is blocked unless the request contains close (closes, closing, closed) or shut; command-Q unless quit (quits, quitting), exit (exiting) or shut. Whole words, per key; menu items follow by title ("Close Window" needs a close word, "Quit Safari" a quit word; "Exit Full Screen" is not held). A blocked step runs nothing.
- **Confirmation guard.** A step pressing a button or menu item named send, delete, remove, discard, pay, buy, purchase, checkout, confirm, submit, publish, post, unsubscribe, transfer, place order or empty trash waits unless the request already says that verb. The row shows `step n · say yes to <verb>` for 30 s; "yes", "confirm" or "do it" runs it (with an attention word set, start with it, so a "yes" from a TV does not count); anything else, silence or "stop" ends the task (`stopped: <verb> not confirmed`). A verb after "not" or "don't" in the request does not allow itself. A yes covers one step (`say yes to send and delete`). Grammar commands you say are not asked about. Details: `docs/superpowers/specs/2026-11-15-nh-61-confirm-irreversible-design.md`.
- **Small-model slip fixes (code).** A `type_text` that is a whole web address becomes `open_url`; a click on a menu-bar item fails unless the request mentions a menu or the item's words (off while number badges show). Site routes (YouTube, Google, Wikipedia, Amazon, Reddit) are fixed hints written by NoHands. Details: `docs/superpowers/specs/2026-11-08-nh-90-small-model-slips-design.md`, `docs/superpowers/specs/2026-11-09-nh-45-site-playbooks-design.md`.
- **Questions.** With several matches and no way to choose, the row shows `step n · ? <question>` (cut to 80 characters) and your next words are the answer; 30 s of silence ends it `stuck: no answer`. Details: `docs/superpowers/specs/2026-11-15-nh-47-task-asks-question-design.md`.
- **Reading the page.** Generic links ("Watch", "Play", "Read more") list the 40 characters before them (`3 [link] Watch near: "Raptors vs Celtics 7:30 PM"`). `read_page` returns the window's visible text under `Read:` in the next step only, up to 4,000 characters, untrusted; none: `no text on this page`. Details: `docs/superpowers/specs/2026-11-15-nh-50-read-page-text-design.md`.
- **Planned goals.** A goal of four or more words about playing media or naming a website first gets one model plan of two to eight fixed-set steps (the model never writes a web address), run in code under the same guards and "stop"; a missed check (after 1.5 s) hands over to the step loop. Details: `docs/superpowers/specs/2026-11-08-nh-91-model-written-plans-design.md`.
- **Vision fallback (off by default).** With `"visionFallback": true`, Claude and Screen Recording, a JPEG of the focused window (at most 1200 px long side) is attached when the last step failed on a missing or stale target (`no element named …`, `element changed, …`), the model used `look`, or it answered `stuck` with no picture (`screen capture failed` and `screen recording not granted` show on the row). A close box clicked by point is not blocked by code (only the prompt says not to close anything the request did not ask to close), so keep `visionFallback` off if you cannot accept that risk. A point click happens only on the step that has the picture, as its first action, once per step. Details: `docs/superpowers/specs/2026-11-08-nh-41-vision-fallback-design.md`.
- **Pop-ups and extra tabs.** `close_tab` and `close_window` act only on a tab or window the task opened (never the tab the task navigated to); one that was already open is closed only when the request says close; `select_tab` is never blocked. Up to 20 tab titles go to the intent backend. Details: `docs/superpowers/specs/2026-11-05-nh-42-close-popups-until-video-plays-design.md`.
- **Stopping.** "stop" ("cancel", "never mind", "abort", "stop the task", "stop stop", "no, stop") aborts the request in flight; rows show `stopped` and `stopping the task`. CLI: Ctrl-C.
- **Talking while a task runs.** Other speech is held (`held · runs after this task (say stop to cancel)`); only the newest is kept (the replaced row shows `dropped`); it runs after the task unless over 60 s old or you said "stop".

### agent-desktop harness

With [agent-desktop](https://github.com/vercel-labs/agent-desktop) installed (`npm i -g agent-desktop` or `brew install agent-desktop`, macOS 13+), tasks observe and act through it instead of NoHands' own accessibility walk. The menu shows `Harness: agent-desktop <version>` or `Harness: native (…)` (`restart NoHands to use it` after an install or grant); `nohands-cli desktop-status` prints it. Details: `docs/superpowers/specs/2026-11-04-agent-desktop-harness-design.md`.

- **Observation.** The model sees each field's value (`= "cats"`) and states (checked, selected, disabled, expanded, offscreen); an open sheet or menu is listed next (`Surface: sheet`).
- **Actions** land on the element (a real click only if agent-desktop delivered nothing): `set_value`, `type_into`, `clear`, `select`, `check`/`uncheck`/`toggle`, `expand`/`collapse`, `focus`, `scroll_to`, `scroll_element`, `drag`, `menu_item` (exact title; works without agent-desktop), `click_in` (`dock`, `menubar`, `sheet`, `alert`, `popover`, `menu`, `menu_bar_extras`), `close_app` (request must say quit, exit, shut or close), `window`, `clipboard_set`, `read_clipboard`, `read_value`, `read_notifications`, `dismiss_notifications` (results under `Read:` next step), `wait` with `wait_for`.
- **Fallback.** Chosen once per task; if agent-desktop cannot read the frontmost app (no window, another Space, minimized, locked screen) the task runs natively. Grammar commands and dictation never use it.

| Key | Default | Meaning |
|---|---|---|
| `desktopHarness` | `auto` | `auto` (agent-desktop when found and Accessibility is granted), `agentDesktop`, `native` |
| `agentDesktopPath` | searched | Absolute path. Search: `/opt/homebrew/bin`, `/usr/local/bin`, `~/.bun/bin`, `~/.volta/bin`, `~/.npm-global/bin`, `~/.local/bin`, every nvm node version, `PATH` |
| `agentDesktopTimeoutMs` | `8000` | Per action |
| `agentDesktopSnapshotMs` | `3000` | Per snapshot |
| `agentDesktopHeadedFallback` | `true` | |
| `agentDesktopTrace` | `false` | When true each task runs in a session whose trace, text fields redacted, is under `~/.agent-desktop/sessions` |

**Claude vs. the local model.** Use Claude for tasks: with `qwen2.5:7b-instruct` the cold first request timed out, the warm one answered `ignore`, and no task has completed. A step costs 5 to 20 s on an M1 Pro (about 2,200 prompt tokens), hence `localLlmDeadlineMs` (30 s) and `localMaxObservedElements` (40). NoHands warms the model every 20 minutes while listening.

## Privacy

- Audio never leaves your machine.
- Only commands the grammar can't match go to Claude (or the local model, which stays on your Mac), as text: your transcript, the frontmost app's name and its controls' titles.
- Task steps also send the window title, the page URL (in a browser), each element's role, and a `Media:` line (`playing`, `paused` or `none`) read from Play or Pause buttons or whether another app makes sound.
- With agent-desktop, each listed field's current value (cut at 60 characters) is sent; clipboard text, a full element value and notifications only after the model asked to read them. Text handed to it (`set_value`, `type_into`, `clipboard_set`) is visible to `ps` while it runs.
- The plan request sends only your transcript.
- Without an API key nothing is sent off the Mac; with the local backend, text goes only to Ollama on `127.0.0.1`.
- **Command log.** The last 50 commands go to `~/.config/nohands/command-log.json` (folder mode 700, file mode 600, replaced atomically): what you said and what was typed or clicked. Never sent; delete the file to clear it.
- **Screenshots.** With `visionFallback` on, pixels leave the Mac only on the task steps in [Multi-step tasks](#multi-step-tasks), only to Claude, never the local model; nothing is captured when the backend is local or the flag is off. The picture is the focused window only, so it can show text, messages and passwords. Held in memory, never saved, not logged.
- **There is no wake-word model.** Everything the microphone hears is acted on; `attentionWord` makes command mode ignore speech that doesn't start with it. Other people, a phone on speaker or loud playback can still be acted on or, in dictation mode, typed. Say "go to sleep" before leaving the desk or during calls; only "wake up" is honored while asleep.

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

Speech and local models are downloaded at run time and keep their own licences: Parakeet speech models CC-BY-4.0, Silero VAD MIT, Qwen 2.5 7B Apache-2.0. The 3B Qwen model, the low-memory default for the local backend, is research-only and not for commercial use (see THIRD_PARTY_LICENSES.md); set `localModel` to change it.

To report a security problem, see [SECURITY.md](SECURITY.md). To contribute, see [CONTRIBUTING.md](CONTRIBUTING.md).
