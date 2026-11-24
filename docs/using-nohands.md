# Using NoHands

Panels, permissions, signing and logs. Back to the [README](../README.md).

```bash
scripts/bundle.sh && open build/NoHands.app
```

Build from an up-to-date `main` (`scripts/bundle.sh` warns when behind `origin/main`). A menu-bar app (no Dock icon) showing `CMD`, `DICT` or `ZZZ` for the mode.

- **Prompt board.** One row per spoken prompt at the top of the pointer's screen: blue while live (`listening…`, `heard`, `Reading · looking at the screen`, `step n · <intent>`, `✗ <why>`), yellow `held`, green `done`, red `failed`, `dropped` or `skipped (busy)`, grey `stopped` or ignored. Finished rows stay 1.5 s (3 s if failed or dropped); at most four; notices (`NoHands is listening`, `microphone error`) show above. Details: `docs/superpowers/specs/2026-11-08-nh-71-no-hands-rows-design.md`, `docs/superpowers/specs/2026-11-15-nh-118-thinking-progress-design.md`.
- **Status bar.** Bottom right of the pointer's screen, below the corner panel; shows only with something to say (`Dictating`, `Asleep · say wake up`, `Paused`, `Loading speech model…`, a task step, a problem with its fix); hides with the grid or number badges. Off or Bottom Right from the menu (macOS user defaults, not `config.json`). Details: `docs/superpowers/specs/2026-11-07-nh-66-status-bar-overlay-design.md`, `docs/superpowers/specs/2026-11-15-nh-92-status-bar-corner-design.md`.
- **Corner panel.** While a request runs: what you said, the steps (`✓`, `✗`, a dot), a phase line (`Reading`, `Thinking` or `Acting`), `step 3` with no total; the outcome stays 1.5 s (3 s for a failure). Details: `docs/superpowers/specs/2026-11-08-nh-70-corner-overlay-design.md`.
- **Packs.** Voice commands for more apps from pack files. Each installed pack has an On toggle and Remove… (asks first); install one with `nohands-cli pack add <file>`, or browse a registry with Packs > Browse… (also Check for pack updates, or `nohands-cli pack search|install|update`). Details: `docs/app-packs.md`.
- **Recent commands and View Logs.** The last 50 commands, newest first, as `<what you said> · done|failed|stopped|ignored`; each opens in the NoHands Logs window (handler, steps, Claude calls and tokens: `4 calls · 12,340 in · 48,100 cache read · 3,200 cache write`). The submenu also has Clear Log and Keep Command Log (stops recording). Details: `docs/superpowers/specs/2026-11-15-nh-111-view-logs-design.md`.

**First run:**

1. **Microphone:** macOS asks at start; on Don't Allow the menu shows "Microphone denied" with an open-Settings item.
2. **Accessibility:** enable NoHands under System Settings > Privacy & Security > Accessibility; a red "Grant Accessibility…" item shows until granted.
3. **Screen Recording** (optional): with `visionFallback` on and Claude as backend, a red "Grant Screen Recording…" item opens System Settings > Privacy & Security > Screen & System Audio Recording; it often applies after a relaunch. Without it steps run without a picture (`screen recording not granted`).
4. **Automation** (optional): asked only the first time you say a dark-mode phrase (`dark mode`, `light mode` or `toggle dark mode`), for System Events. The row says to allow it and say the phrase again; if you decline, `open automation settings` opens the list.
5. NoHands listens only once Microphone and Accessibility are granted, re-checking Accessibility every few seconds.

**Ad-hoc signature:** every rebuild is a new app to macOS, so re-grant Microphone, Accessibility, Screen Recording and Automation each time (to clear a stale Automation grant: `tccutil reset AppleEvents dev.nohands.app`). A stable identity avoids this:

```bash
CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" scripts/bundle.sh
```

The app is not sandboxed and is signed without the hardened runtime, so it needs no entitlement to send Apple Events. A later build signed with `--options runtime` (for notarization) must pass an entitlements file with `com.apple.security.automation.apple-events` set to true to `codesign`, or a dark-mode phrase fails as denied without a prompt. Under `swift run` there is no app bundle: the Automation prompt names the terminal.

**Speak Feedback:** a submenu with Off, Outcomes and All (the current one ticked). Off, the default, says nothing. Outcomes says how a task, macro or rewrite ended (`Done: open the menu.`, `Stuck: no Raptors game listed.`); All adds the model's questions and `Say yes to …`, and reads out what a task read. It applies at once and is saved to `config.json`. `spoken feedback on`, `spoken feedback all` and `spoken feedback off` do the same by voice. Say `stop` to cut it off, or just give the next command. See [Configuration](configuration.md) and [Privacy](privacy.md).

**Start at Login:** a menu item registers a login item and shows a tick; if turned off in Login Items it says `allow in Login Items`. Disabled under `swift run`.

**Logs:** each utterance logs `[asr=…ms total=…ms sinceVoice=…ms] <transcript> -> <what it did>`, plus `claude: step N <ms>ms cache=<read>/<written> in=<n> out=<n>`, `claude: session calls=<n> in=<n> cache=<read>/<written> out=<n>` (when each Claude task ends, the running total for this app session), `ollama: step N <ms>ms` and `intent backend: claude|local|off` lines:

```bash
log stream --predicate 'subsystem == "dev.nohands.app"'
```

Transcripts log as `<private>` unless private data logging is on (`sudo log config --mode "private_data:on"`); running `build/NoHands.app/Contents/MacOS/NoHands` from a terminal prints full lines.

**Claude API key:** shell exports do not reach an app started with `open`. Choose **Set Claude API key…**, paste, restart; saved to `~/.config/nohands/config.json`. Without a key and with `intentBackend` left at `auto`, natural-language commands use the local model (`local model not running: start Ollama` until it is set up). "LLM off" shows when `intentBackend` is `off`, or `claude` with no key.
