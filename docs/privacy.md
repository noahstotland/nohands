# Privacy

What leaves the Mac and what stays. Back to the [README](../README.md).

- Audio never leaves your machine.
- Only commands the grammar can't match go to Claude (or the local model, which stays on your Mac), as text: your transcript, the frontmost app's name and its controls' titles.
- Task steps also send the window title, the page URL (in a browser), each element's role, and a `Media:` line (`playing`, `paused` or `none`) read from Play or Pause buttons or whether another app makes sound.
- With agent-desktop, each listed field's current value (cut at 60 characters) is sent; clipboard text, a full element value and notifications only after the model asked to read them. Text handed to it (`set_value`, `type_into`, `clipboard_set`) is visible to `ps` while it runs.
- The plan request sends only your transcript.
- Without an API key nothing is sent off the Mac; with the local backend, text goes only to Ollama on `127.0.0.1`.
- **Command log.** The last 50 commands go to `~/.config/nohands/command-log.json` (folder mode 700, file mode 600, replaced atomically): what you said and what was typed or clicked. Never sent; delete the file to clear it.
- **Screenshots.** With `visionFallback` on, pixels leave the Mac only on the task steps in [Multi-step tasks](tasks.md#multi-step-tasks), only to Claude, never the local model; nothing is captured when the backend is local or the flag is off. The picture is the focused window only, so it can show text, messages and passwords. Held in memory, never saved, not logged.
- **There is no wake-word model.** Everything the microphone hears is acted on; `attentionWord` makes command mode ignore speech that doesn't start with it. Other people, a phone on speaker or loud playback can still be acted on or, in dictation mode, typed. Say "go to sleep" before leaving the desk or during calls; only "wake up" is honored while asleep.
