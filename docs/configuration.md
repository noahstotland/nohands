# Configuration

Every setting, with defaults and ranges. Back to the [README](../README.md). Task behaviour is in [Tasks](tasks.md); data handling is in [Privacy](privacy.md).

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
| `followUpWindowMs` | `30000` | 0 to 120000; `0` turns follow-ups off |
| `vocabulary` | `[]` | up to 200 entries; see Vocabulary |
| `macros` | `{}` | up to 50 macros of 20 steps; see Macros |

The agent-desktop keys are under [agent-desktop harness keys](#agent-desktop-harness-keys).

- **API key.** `ANTHROPIC_API_KEY` overrides the file but reaches the app only from a terminal or after `launchctl setenv ANTHROPIC_API_KEY ...`. The menu's key item writes the file with mode 600 (folder 700; by hand `chmod 600 ~/.config/nohands/config.json`) and refuses a symlink or invalid JSON; the Model item does the same for `intentBackend` but keeps an existing file's mode (a new file is 600). The key is never shown again. A launch warning is logged if others can read a file holding a key. Open config.json… creates `{}` if missing, never edits an existing file.
- **Claude line in the menu** reads the config alone: `Claude: key set (config.json)`, `Claude: no key, using the local model`, `Claude: not used (intentBackend = local)`. Check Claude connection sends a one-token request: `Claude: connected at 14:32` or `Claude: key rejected at 14:32, check anthropicAPIKey`. Details: `docs/superpowers/specs/2026-11-09-nh-103-claude-status-menu-design.md`.
- **Session total:** once Claude has made a call, a second line shows the running total for this app session, e.g. `Claude this session: 14 calls, 31k in, 9k cached, 2k out` ("in" is fresh input including cache writes, "cached" is cache reads). It counts every call that got a reply, including the connection check and stopped tasks, resets when NoHands restarts (not on config reload or backend change), and holds counts only, never text. Details: `docs/superpowers/specs/2026-11-15-nh-112-token-usage-design.md`.
- **Echo cancellation.** `echoCancellation` removes what the Mac's speakers play (macOS voice processing); set `false` if an external audio interface clashes.
- **Attention word.** `attentionWord` (empty = off): command mode acts only on utterances starting with it (`computer, new tab` works, `new tab` alone does nothing). More than three words, or a stop phrase, counts as off. `stop`, `wake up` and the dictation escapes (`stop dictating`, `command mode`) work with or without it. Details: `docs/superpowers/specs/2026-11-05-nh-12-attention-word-design.md`.
- **Vocabulary.** `vocabulary` lists words the recognizer mishears; every transcript has each misheard spelling swapped for the right one before anything acts on it:

  ```json
  "vocabulary": [
    { "hear": "raptures", "say": "Raptors" },
    { "hear": ["stream east", "streem east"], "say": "StreamEast" }
  ]
  ```

  `hear` is a string or a list of up to five-word spellings; `say` is up to 100 characters. Whole words only, any case (`raptures` does not touch `enraptured`); the longest spelling wins, then the first entry; punctuation between the words of a spelling stops a match, and punctuation around a word is kept (`raptures,` becomes `Raptors,`). Dictation types `say` as written. Entries with no `say` or `hear`, or with `stop`, `cancel`, `never mind`, `abort` or `halt` in either, are skipped, and a stop, or a mode phrase such as `wake up` or `stop dictating`, is never rewritten (nor is a rewrite made that would form a stop). A `vocabulary` that is not a list counts as one skipped entry. Past 200 entries the rest are skipped. Do not list your `attentionWord` as a `hear` spelling: it would be rewritten and addressed commands would stop working. A launch log line gives the count skipped, never the words. Read at launch; restart to apply changes. `nohands-cli transcribe` and `parse` show the raw text. Details: `docs/superpowers/specs/2026-11-16-nh-56-custom-vocabulary-design.md`.
- **Macros.** `macros` names a sequence you say often; say the name and NoHands runs the steps in order, as if you had said each one, and stops at the first that fails:

  ```json
  "macros": {
    "night game": ["open chrome", "go to streameast.app", "find raptors", "click"]
  }
  ```

  A step is a phrase written as you would say it, without the attention word, and may be a model request ("play the newest video") as well as a command. The name must be the whole utterance (`night game please` is not a match) and, with `attentionWord` set, starts with it (`computer, night game`); in dictation it is typed. Everything runs on one row (`step 2 of 4 · go to …`); saying `stop` ends it at that step. After a command step there is a 500 ms pause so the app can come forward. A model step is an ordinary task, so it reads and sets the follow-up memory. A macro is skipped whole (never half run) when its name is empty, over six words, has `stop`, `cancel`, `never mind`, `abort` or `halt` in it, is a phrase NoHands already understands (`go back`), or repeats another name after case and punctuation are ignored; or when it has no steps, over 20, or a step that is empty, over 200 characters, has a stop word, is a mode or release phrase (`start dictating`, `go to sleep`, `wake up`) or is another macro's name. Past 50 macros the rest are skipped (kept in name order). A `macros` that is not an object counts as one skipped macro. A launch log line gives the count skipped, never the names. The vocabulary fixes the spoken name, not the steps: write the steps spelled right. Read at launch; restart to apply changes. Details: `docs/superpowers/specs/2026-11-16-nh-57-voice-macros-design.md`.
- **Task loop keys.** `maxMediaTaskSteps` replaces `maxTaskSteps` for a request to play or watch. `llmDeadlineMs`: per model call. `settleMs`: the most wait for the screen to settle after an action. `maxObservedElements`: elements sent to the model. The local model uses `localLlmDeadlineMs` and `localMaxObservedElements` instead.
- **Pausing mid-command.** `silenceMs` closes an utterance. A complete command and a stop phrase close after `earlySilenceMs` (one 256 ms chunk), so a pause of 350 ms or more inside acts on the first part ("click twenty … three" clicks 20); open-ended commands (`type …`, `open …`, `go to …`, `search for …`, `click <name>`, `play`, `skip ahead …`, `volume …`), unparsed speech, dictation and sleep keep `silenceMs`. Speech the grammar does not understand is then held `mergeWindowMs` (`mergeWindowUnfinishedMs` if it starts with `spell` or ends on a word like "the"), row `listening…`, later speech appended. A stop phrase (see Stopping; also "um, stop") is never held or merged: it goes through at once, and in command mode it discards the unfinished words before it. Details: `docs/superpowers/specs/2026-11-08-nh-36-early-grammar-endpointing-design.md`.
- **How the model reads a request.** A one-sentence `intent`, then the actions. `intentEffort` sets how hard Claude thinks; `low` is fastest. `claude-haiku-5-5` at `low` is chosen for cost; for more, set `"intentModel": "claude-opus-5-5"` and `"intentEffort": "medium"`. No server-side fallback on Haiku.

## agent-desktop harness keys

How the harness works is in [Tasks](tasks.md#agent-desktop-harness).

| Key | Default | Meaning |
|---|---|---|
| `desktopHarness` | `auto` | `auto` (agent-desktop when found and Accessibility is granted), `agentDesktop`, `native` |
| `agentDesktopPath` | searched | Absolute path. Search: `/opt/homebrew/bin`, `/usr/local/bin`, `~/.bun/bin`, `~/.volta/bin`, `~/.npm-global/bin`, `~/.local/bin`, every nvm node version, `PATH` |
| `agentDesktopTimeoutMs` | `8000` | Per action |
| `agentDesktopSnapshotMs` | `3000` | Per snapshot |
| `agentDesktopHeadedFallback` | `true` | |
| `agentDesktopTrace` | `false` | When true each task runs in a session whose trace, text fields redacted, is under `~/.agent-desktop/sessions` |

## Local model (no API key)

Ollama on your Mac: nothing leaves the machine; works offline once downloaded.

```bash
scripts/setup-local-model.sh            # picks a model by RAM
scripts/setup-local-model.sh qwen2.5:3b-instruct   # or name one
```

Installs Ollama with Homebrew if needed, starts it, pulls the model, smoke tests; safe to re-run. The menu can also download the model. Ollama from brew starts at login (`brew services`).

- **Default model:** `qwen2.5:7b-instruct` with 12 GB of RAM or more, else `qwen2.5:3b-instruct` (free RAM about 5 GB and 2 GB).
- **Backend:** `intentBackend` is `auto` (Claude when a key is set, else local), `claude`, `local` or `off`. The menu's **Model: …** item switches Claude and local with no restart; the Claude row is greyed out until a key is in effect. `auto` and `off` are file-only. Details: `docs/superpowers/specs/2026-11-09-nh-116-backend-toggle-design.md`.
- **Server:** `localModel` and `ollamaURL` (`127.0.0.1`, `localhost` or `::1` over `http` only).
- **If it fails:** `local model not running: start Ollama` or `local model not downloaded: see the NoHands menu`.
