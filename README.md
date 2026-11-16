<img src="assets/icon.svg" width="64" height="64" alt="NoHands logo">

# NoHands

Control your Mac with your voice and nothing else. Dictate into any app, press shortcuts, move and click the mouse, and give natural-language commands. Speech recognition runs on-device, so ordinary commands never touch the network.

Status: early software, run and measured on an Apple Silicon Mac against real apps. Tasks work best with Claude.

## How it works

```
mic → Silero VAD → Parakeet speech recognition (on-device)
    → mode machine ─┬─ dictation  → formatter → type text
                    ├─ command    → fast grammar (no network) → actions
                    │                └ unmatched → Claude → actions
                    └─ sleep      → only "wake up" is honored
    → executor: keyboard/mouse events, accessibility lookups, grid and label overlays
```

A deterministic grammar matches common commands in under a millisecond. Anything it does not understand runs as a task: the model looks at the frontmost app, picks a step, and repeats until done ([Tasks](docs/tasks.md)). Saying "stop" always halts the task. "show numbers" labels clickable elements and "grid" overlays a numbered grid, so you can click anything by number.

## Requirements

- Apple Silicon Mac, macOS 14 or later
- Xcode 16 / Swift 6 toolchain
- Microphone and Accessibility permissions (plus Screen Recording if you turn on `visionFallback`)
- Optional, for natural-language commands: an Anthropic API key, or a local model through [Ollama](https://ollama.com) (no key, about 2-5 GB of free RAM)

## Install and first run

```bash
scripts/bundle.sh && open build/NoHands.app
```

Build from an up-to-date `main`. The first build downloads and compiles [FluidAudio](https://github.com/FluidInference/FluidAudio), and the speech models download on first use. NoHands is a menu-bar app with no Dock icon. The menu bar shows `CMD`, `DICT` or `ZZZ` for the mode.

1. **Microphone:** macOS asks at start. If you say no, the menu shows "Microphone denied" with an item that opens Settings.
2. **Accessibility:** enable NoHands under System Settings > Privacy & Security > Accessibility. A red "Grant Accessibility…" item shows until you do.
3. **Screen Recording** (optional): only for `visionFallback` with Claude. A red "Grant Screen Recording…" item opens the setting.

NoHands starts listening once Microphone and Accessibility are granted. Every ad-hoc rebuild is a new app to macOS, so you grant them again each time; [Using NoHands](docs/using-nohands.md) shows how to sign with a stable identity to avoid that. It also covers the on-screen panels, Start at Login and logs.

## Try these

Say these, one at a time:

- `open safari`
- `go to youtube.com`
- `show numbers`, then `click 12`
- `scroll down 10`
- `new tab`
- `start dictating`, then some words, then `stop dictating`
- `select the last sentence`
- `play`, `pause`, `volume 40`
- `go to sleep`, then `wake up`
- `stop`

Say something the grammar does not know, such as "show me the weather in Toronto", and the model takes over. All phrases are in [Voice commands](docs/voice-commands.md).

## Claude or a local model

The grammar works with no setup. Natural-language commands need a model: with no Claude key they use the local model, and show `local model not running: start Ollama` until it is set up. Pick one:

- **Claude:** choose **Set Claude API key…** in the menu, paste your key and restart. The default model is `claude-haiku-5-5`.
- **A local model:** run `scripts/setup-local-model.sh`. It installs Ollama with Homebrew if needed, pulls a model sized to your RAM and smoke tests it. Nothing leaves the Mac.

The menu's **Model** item switches between Claude and the local model with no restart. Use Claude for tasks. The local model is slow and has not completed a task in testing. Details are in [Configuration](docs/configuration.md#local-model-no-api-key).

## Configuration

Optional file `~/.config/nohands/config.json`. Every key may be omitted, and changes apply after a restart. Invalid JSON falls back to defaults and is flagged in the menu. The API key can also come from `ANTHROPIC_API_KEY` (this reaches the app only from a terminal). Every key, default and range is in [Configuration](docs/configuration.md).

## Privacy

- Audio never leaves your machine.
- Only commands the grammar can't match go to Claude (or the local model, which stays on your Mac), as text, plus, only with `visionFallback` on, a screenshot of the focused window to Claude.
- Without an API key nothing is sent off the Mac. The local backend talks only to Ollama on `127.0.0.1`.
- There is no wake-word model, so other people or loud playback can be acted on. Say "go to sleep" before leaving the desk or during calls.

The full list of what is sent is in [Privacy](docs/privacy.md).

## More docs

- [Voice commands](docs/voice-commands.md): every phrase
- [Using NoHands](docs/using-nohands.md): panels, permissions, signing, logs
- [Configuration](docs/configuration.md): config keys and the local model
- [App packs](docs/app-packs.md): add voice commands for more apps from a pack file
- [Tasks](docs/tasks.md): how multi-step requests run, guards, the agent-desktop harness
- [CLI tools](docs/cli.md): `nohands-cli` subcommands for trying each piece by hand
- [Privacy](docs/privacy.md)
- [Design spec](docs/superpowers/specs/2026-11-04-nohands-design.md) and [implementation plan](docs/superpowers/plans/2026-11-04-nohands-voice-control.md)

## Contributing

```bash
swift build
swift test
```

`swift test` needs no permissions and no Ollama. Code goes in `Sources/NoHandsCore` (pure logic), `Sources/NoHandsMac` (macOS integration), `Sources/NoHands` (the app) and `Sources/nohands-cli` (dev tool). One ticket is one branch and one PR, commits are conventional (`feat:`, `fix:`, `docs:`), and a new voice phrase goes in [Voice commands](docs/voice-commands.md) in the same PR. Read [CONTRIBUTING.md](CONTRIBUTING.md) for the rest. To report a security problem, see [SECURITY.md](SECURITY.md).

## License

NoHands is under the [Apache License 2.0](LICENSE). Third-party notices are in [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md).

Speech and local models are downloaded at run time and keep their own licences: Parakeet speech models CC-BY-4.0, Silero VAD MIT, Qwen 2.5 7B Apache-2.0. The 3B Qwen model, the low-memory default for the local backend, is research-only and not for commercial use (see THIRD_PARTY_LICENSES.md); set `localModel` to change it.
