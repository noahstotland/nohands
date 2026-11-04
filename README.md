<img src="assets/icon.svg" width="64" height="64" alt="">

# nohands

Control your Mac with your voice and nothing else. Dictate into any app, press shortcuts, move and click the mouse, and give natural-language commands. Speech recognition runs on-device, so ordinary commands never touch the network.

> **Status: work in progress.** The core logic, input synthesis and audio pipeline are built and unit-tested. The menu-bar app, overlays and Claude integration are still being built. Nothing has been run end to end against real apps yet.

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

## Configuration

Optional file at `~/.config/nohands/config.json`. Every key may be omitted, and `ANTHROPIC_API_KEY` in the environment overrides the file.

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

Audio never leaves your machine. Only commands the grammar can't match are sent to Claude, as text: your transcript, the frontmost app's name and the titles of its visible controls.

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
