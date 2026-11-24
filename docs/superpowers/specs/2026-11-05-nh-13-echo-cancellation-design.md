# NH-13: Echo cancellation on the microphone input — Design

**Date:** 2026-11-05  **Status:** Shipped  **Ticket:** [NH-13](https://github.com/noahstotland/nohands/issues/13)
**Shipped:** in PR #24, with differences: [as-built](../as-built/2026-11-05-nh-13-echo-cancellation.md)

## Intent

A playing video can press keys, because NoHands acts on the Mac's own speaker audio. Turn on Apple's voice processing (echo cancellation) on the input node, so speaker audio is subtracted before VAD and ASR, with no "go to sleep" first.

## Approaches

Use `inputNode.setVoiceProcessingEnabled(true)`: echo cancellation, noise suppression and gain control in one flag. Rejected: our own AEC on a loopback (a big dependency and a new permission), and gating on "audio is playing" (it also blocks commands over a video).

## Design

- **Config:** new key `echoCancellation: Bool = true`. A wrong type invalidates the whole file, as every key does.
- **Capture (`MicrophoneCapture`):** before the tap is installed (the engine must be stopped), enable voice processing on the input node and touch `engine.mainMixerNode` so the output side exists. Set other-audio ducking to the minimum (macOS 14), since the default quiets every other app and NoHands listens all the time.
- **Format:** with several channels the converter takes channel 0, the processed voice.
- **Failure:** if enabling throws or the engine fails to start, log once, turn it off and continue with the plain input. An `echoUnavailable` flag stops later rebuilds retrying.
- **Reporting:** `MicrophoneEvent.echoCancellation(Bool)` is emitted once after the first start and logged, as a warning only when the config asked for it. No HUD change.
- **Docs:** README § Privacy says only the Mac's own output is removed, so other people talking are still heard and "go to sleep" stays right for calls. § Configuration documents the key.

## Testing

Unit: only the config key's default and parse rows. Manual, in the PR, not claimed as passed: a video on the speakers for a minute causes no actions and "new tab" works over it; `asr` median regresses by at most 50 ms; the video's volume does not drop; capture survives a device switch.

Non-goals: input device choice, menu or HUD controls.

## Risks

- No primary source says voice processing removes other apps' audio on macOS. If the manual check fails, the PR says so, the default stays on and a follow-up is filed.
- Gain control and noise suppression may change Parakeet accuracy and latency.

## Calls I made

- **Ducking is set to the minimum.** The default would turn the test video down instead of cancelling it.
- **The default stays true** even if cancellation falls short on a real Mac.
- **Failure is logged, not shown in the HUD.** The app works without it.
