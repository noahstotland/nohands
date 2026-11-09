# Security

## Reporting a vulnerability

Report it privately through GitHub private vulnerability reporting: open the repository's **Security** tab and choose **Report a vulnerability**
(<https://github.com/noahstotland/nohands/security/advisories/new>). Do not open a public issue or pull request for a security problem, and do not post API keys, tokens or private transcripts anywhere public.

Include the NoHands version or commit, your macOS version, what you did, what you expected and what happened. A short reproduction helps most.

## What NoHands promises

These are the guarantees the code is meant to keep. A way to break one is a vulnerability.

- **Transcripts and typed text are private.** They are logged with the unified log's private marker (`privacy: .private`, in `Sources/NoHandsMac/PipelineLog.swift`) and sent nowhere except the configured intent backend, which is Claude or a local Ollama model.
- **Ordinary commands never touch the network.** The fast grammar runs on-device. Only a phrase it cannot match goes to the intent backend. The one other network use is the first-run download of the speech models by FluidAudio.
- **The Ollama URL is loopback only.** `ollamaURL` is accepted only as `http` to `127.0.0.1`, `localhost` or `::1`. Anything else falls back to the default (`Sources/NoHandsCore/AppConfig.swift`, `ollamaBaseURL`).
- **Model output is untrusted.** What Claude or the local model returns is decoded by a strict intent decoder (`Sources/NoHandsCore/IntentDecoder.swift`) that does not run actions that fail the schema. A key-chord guard (`ShortcutGuard`) blocks command-W and command-Q unless the spoken request asks for them, and a task has a step limit. Nothing is typed, clicked or opened from model output before this.
- **No global input hooks.** NoHands posts synthesized keyboard and mouse events, and reads on-screen elements from the frontmost app through Accessibility. It does not install an event tap or a global key or mouse monitor, so it cannot capture input meant for other apps.
- **The API key stays out of the repo and logs.** It lives only in `~/.config/nohands/config.json` or the `ANTHROPIC_API_KEY` environment variable. At launch NoHands warns if the config file holds a key and other users can read it (run `chmod 600 ~/.config/nohands/config.json`).

## Known limits

- When the optional agent-desktop harness is in use, text handed to it travels in that child process's arguments and is visible to `ps` while it runs.
- Audio from the microphone is transcribed on the Mac and acted on. Other people talking, or a phone on speaker, can be heard. Say "go to sleep" before a call. See the Privacy section of the [README](README.md).
- NoHands downloads speech models (FluidAudio) and, if you choose a local model, Ollama models. Those come from their publishers and are not checked by NoHands beyond what those tools do.
