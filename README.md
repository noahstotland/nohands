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
- **Natural language:** anything the grammar can't match goes to Claude, which returns structured actions. This needs an Anthropic API key and is optional.
- **Targeting:** say "show numbers" to label every clickable element in the frontmost app, or "grid" to overlay a numbered 10×8 grid you can zoom into.

## Requirements

- Apple Silicon Mac, macOS 14 or later
- Xcode 16 / Swift 6 toolchain
- Microphone and Accessibility permissions
- Optional: an Anthropic API key for natural-language commands

## Build

```bash
swift build
swift test
```

The first build downloads and compiles [FluidAudio](https://github.com/FluidInference/FluidAudio). Speech models download on first use.

## Run it

```bash
Scripts/bundle.sh && open build/NoHands.app
```

`Scripts/bundle.sh` builds a release binary, assembles `build/NoHands.app` and code-signs it. NoHands is a menu-bar app (no Dock icon); the menu bar shows `CMD`, `DICT` or `ZZZ` for the current mode.

**First run:**

1. **Microphone** — macOS asks when the app starts. If you click Don't Allow, the menu shows "Microphone denied — open Settings".
2. **Accessibility** — needed to type, click and read UI elements. macOS opens a prompt; enable NoHands under System Settings > Privacy & Security > Accessibility. The menu shows a red "Grant Accessibility…" item until it is granted.
3. NoHands starts listening only after both are granted, and re-checks Accessibility every few seconds (and pauses if you revoke it), so no restart is needed. The first launch also downloads the speech models.

**Ad-hoc signature caveat:** by default the app is ad-hoc signed, so macOS treats every rebuild as a new app and you must re-grant Microphone and Accessibility each time (remove the stale NoHands entry in Accessibility first). Set a stable signing identity to avoid this:

```bash
CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" Scripts/bundle.sh
```

**Logs:** each utterance logs one line, `[asr=…ms total=…ms] <transcript> -> <what it did>`, plus warm-up results, warnings and errors, through the unified log:

```bash
log stream --predicate 'subsystem == "dev.nohands.app"'
```

Transcripts are logged as private, so they show as `<private>` unless private data logging is enabled (`sudo log config --mode "private_data:on"`). Running `build/NoHands.app/Contents/MacOS/NoHands` directly from a terminal also prints the full lines to that terminal.

**Claude API key:** shell exports do not reach an app started with `open`. Put the key in `~/.config/nohands/config.json` (see Configuration) and run `chmod 600 ~/.config/nohands/config.json`. Without a key, natural-language commands show "LLM off" and the fast grammar still works.

## Voice commands

| Say | Does |
|---|---|
| `type <words>` | Types the words with spoken punctuation applied |
| `press command shift s` | Presses a key chord |
| `enter`, `tab`, `escape`, `delete`, arrow names | Presses that key |
| `undo`, `redo`, `copy`, `paste`, `cut`, `select all`, `save`, `find` | Standard shortcuts |
| `new tab`, `close tab`, `close window`, `quit app`, `switch app`, `spotlight` | App and window shortcuts |
| `click`, `double click`, `right click`, `middle click` | Clicks at the pointer |
| `click 42` | Clicks label or grid cell 42 |
| `click save` | Clicks the element named "save" |
| `hold click` / `release click` | Press and release the mouse button (drag) |
| `move up 100`, `move to 12` | Moves the pointer |
| `scroll down 10` | Scrolls |
| `grid`, `zoom 35`, `show numbers`, `hide` | Targeting overlays |
| `open safari` | Opens or focuses an app |
| `start dictating` / `stop dictating` | Switch between command and dictation mode |
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
| `parse "<text>"` | Dry run: prints the actions the grammar produces (or "no match -> LLM"); executes nothing |
| `run "<phrase>"...` | Executes grammar phrases in order |
| `resolve "<text>"` | Sends text and the frontmost app's labels to Claude (spends API credit) |
| `listen` | Microphone to VAD to speech recognition, printing transcripts |

## Configuration

Optional file at `~/.config/nohands/config.json`. Every key may be omitted. For the bundled app this file is the way to supply the API key: `ANTHROPIC_API_KEY` in the environment overrides the file, but it only reaches the app when you run the binary from a terminal or set it with `launchctl setenv ANTHROPIC_API_KEY ...`. The file holds a secret, so run `chmod 600 ~/.config/nohands/config.json`; NoHands logs a warning at launch if it contains a key and is readable by other users. Invalid JSON falls back to defaults and is flagged in the menu.

```json
{
  "anthropicAPIKey": "sk-ant-...",
  "intentModel": "claude-opus-5-5",
  "asrModelVersion": "v2",
  "silenceMs": 350,
  "gridColumns": 10,
  "gridRows": 8,
  "moveStepPx": 50,
  "scrollStepLines": 5
}
```

## Privacy

Audio never leaves your machine. Only commands the grammar can't match are sent to Claude, as text: your transcript, the frontmost app's name and the titles of its visible controls. Without an API key nothing is ever sent.

**There is no wake word and no echo cancellation.** Any audio the microphone hears (calls, videos, other people talking, your own speakers) is transcribed and acted on, and in dictation mode it is typed into the focused app. With an API key, phrases the grammar doesn't match are also sent to Claude as text. Say "go to sleep" before leaving the desk or when playing audio; only "wake up" is honored while asleep.

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
