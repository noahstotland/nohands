# NH-13 Echo Cancellation Implementation Plan

**Goal:** Turn on voice processing (echo cancellation) on the microphone input, behind `echoCancellation` (default true), and keep working without it if macOS refuses.

**Spec:** `docs/superpowers/specs/2026-11-05-nh-13-echo-cancellation-design.md`. Read it first.

**Constraints:** Swift 6 strict concurrency (no new `@unchecked Sendable`; `MicrophoneCapture` already has one). `NoHandsCore` gets only the config key. `swift build` and `swift test` green after each task.

## Task 1: Config key (NoHandsCore)

- `AppConfig.echoCancellation: Bool = true`, in `CodingKeys` and `init(from:)` (`decodeIfPresent ?? default`).
- `AppConfigTests`: extend the default row (true) and one parse row (`{"echoCancellation":false}` gives false; missing key gives true).

## Task 2: Capture (NoHandsMac)

- `MicrophoneEvent.echoCancellation(Bool)` (stays `Sendable, Equatable`).
- `MicrophoneCapture.init(echoCancellation: Bool = true)`; add `echoUnavailable` and `reportedEcho`, both guarded by `lock`.
- In `installTapAndStart`, before reading the input format: if enabled, not `echoUnavailable`, and `!input.isVoiceProcessingEnabled`, call `try input.setVoiceProcessingEnabled(true)`, touch `engine.mainMixerNode`, and set `input.voiceProcessingOtherAudioDuckingConfiguration = .init(enableAdvancedDucking: false, duckingLevel: .min)`. On a throw: mark `echoUnavailable`, `try? input.setVoiceProcessingEnabled(false)`, continue plain.
- If `engine.start()` throws while voice processing is on and it was not already marked unavailable: remove the tap, disable voice processing, mark unavailable, retry the start once without it. A failure without voice processing throws as today.
- If the config flag is off and voice processing is somehow enabled, disable it.
- After the first successful start emit `.echoCancellation(input.isVoiceProcessingEnabled)` once per `start()` session (not per rebuild).
- Chunking path unchanged: tap format is `input.outputFormat(forBus: 0)` read after enabling; converter rebuild on format change already exists. Check `consume` takes channel 0 of a multichannel buffer (AVAudioConverter mixes down; confirm it is not silent for a multichannel voice-processing format, and if unsure convert from channel 0 only).

## Task 3: Callers and docs

- `VoicePipeline`: `MicrophoneCapture(echoCancellation: config.echoCancellation)`; in `onEvent`, log `.echoCancellation(false)` as `PipelineLog.warning` only when `config.echoCancellation` is true, otherwise the existing info line.
- `nohands-cli listen`: `let config = try loadConfig()`; pass the key.
- README: Configuration JSON sample plus one sentence; Privacy paragraph as in the spec. Update the architecture spec only if it describes the input chain.

## Verify

`swift build`, `swift test`. Manual checks (spec § Testing) go in the PR as not run.
