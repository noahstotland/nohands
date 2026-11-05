# NH-13: Echo cancellation on the microphone input — Design

**Date:** 2026-11-05  **Status:** Shipped  **Ticket:** [NH-13](https://github.com/noahstotland/nohands/issues/13)
**Shipped:** in PR #24, with differences: [as-built](../as-built/2026-11-05-nh-13-echo-cancellation.md)

## Intent

NoHands transcribes and acts on audio from the Mac's own speakers, so a playing video can press keys. This
change turns on Apple's voice processing (echo cancellation) on the input node. Speaker audio is then subtracted
before VAD and ASR, and the user no longer has to say "go to sleep" before playing audio.

## Today

- `MicrophoneCapture` (`Sources/NoHandsMac/MicrophoneCapture.swift`) taps `engine.inputNode` in its native
  format, converts to 16 kHz mono and sends exact 4096-sample chunks. It rebuilds the tap on
  `AVAudioEngineConfigurationChange`, with `RestartBackoff`.
- `VoicePipeline` and `nohands-cli listen` both build it with `MicrophoneCapture()`.
- README § Privacy says there is no echo cancellation.

## Approaches

1. **AVAudioEngine voice processing** (`inputNode.setVoiceProcessingEnabled(true)`). Apple's voice-processing
   IO unit: echo cancellation, noise suppression and gain control in one flag. The ticket asks for this. Chosen.
2. **Our own AEC on a loopback of system output** (a process tap or a virtual device, plus WebRTC-style AEC).
   Rejected: a big dependency, a new permission (screen/system audio capture), and out of the ticket's scope.
3. **Gate on "is audio playing"** (pause listening while other apps play sound). Rejected: it also stops the
   user's own commands while a video plays, which the acceptance test needs to work ("new tab" over a video).

## Design

### Config (`NoHandsCore/AppConfig.swift`)

- New key `echoCancellation: Bool = true`, added to `CodingKeys` and decoded with `decodeIfPresent ?? default`
  like the other Bools. A wrong type (e.g. `"yes"`) throws like every other key today, so the file falls back to
  defaults and the menu flags it, as the README describes.
- `AppConfigTests`: add the key to the existing default and parse table rows (default true; `false` parses).

### Capture (`NoHandsMac/MicrophoneCapture.swift`)

- `init(echoCancellation: Bool = true)` keeps the flag.
- In `installTapAndStart`, before reading the input format and installing the tap (so the engine is stopped,
  which voice processing needs), when the flag is on and `inputNode.isVoiceProcessingEnabled` is false:
  - `try input.setVoiceProcessingEnabled(true)`. This also puts the output node in voice-processing mode.
  - Touch `engine.mainMixerNode` so the output node is in the graph, since the voice-processing unit needs a
    running output side to start.
  - Set `input.voiceProcessingOtherAudioDuckingConfiguration` to
    `.init(enableAdvancedDucking: false, duckingLevel: .min)` (macOS 14 API, our floor). The default ducks every
    other app while voice processing runs, and NoHands listens all the time, so videos and music would stay
    quiet.
- Then read `input.outputFormat(forBus: 0)` as today. Voice processing can change the input's channel count and
  sample rate, and the tap already uses the node's current format and the converter is rebuilt when
  `buffer.format` changes, so 16 kHz chunking is kept. If the voice-processing format has more than one channel,
  the converter takes channel 0, the processed voice channel. The plan checks that with `nohands-cli listen`.
- **Failure:** if `setVoiceProcessingEnabled` throws, or the engine fails to start with it on, log once
  (`PipelineLog.warning`-level line via `onEvent`, see below), turn it off
  (`try? setVoiceProcessingEnabled(false)`), and go on with the plain input. A per-instance `echoUnavailable`
  flag (guarded by `lock`) makes later rebuilds skip the attempt, so a config-change rebuild does not retry or
  log again.
- **Reporting:** a new `MicrophoneEvent.echoCancellation(Bool)` is emitted once after the first successful start
  (true = on, false = off because it failed or the config turned it off). `VoicePipeline` already logs non-failure
  events with `PipelineLog.info("[mic] …")`; it logs `.echoCancellation(false)` as a warning only when the config
  asked for it. No HUD or menu text changes.
- **Rebuilds:** on `AVAudioEngineConfigurationChange` (device switch, and possibly turning voice processing on
  itself) the existing path runs again, and the "enable if not enabled" check keeps it idempotent.

### Callers

- `VoicePipeline` builds `MicrophoneCapture(echoCancellation: config.echoCancellation)`.
- `nohands-cli listen` reads `loadConfig()` (already used by other subcommands) and passes the same key, so the
  CLI's `asr` timings show the real setup.

### Docs

- README § Privacy: replace "There is no wake word and no echo cancellation" with: there is no wake word; echo
  cancellation removes what the Mac's own speakers play, but other people talking, a phone on speaker or very
  loud playback can still be heard and acted on, so "go to sleep" is still the safe choice for calls.
- README § Configuration: add `"echoCancellation": true` to the JSON sample and one sentence: what it does,
  that `false` turns it off (for an external interface whose own processing clashes), and that NoHands goes on
  without it if macOS refuses.
- Architecture spec (`2026-11-04-nohands-design.md`): update the capture line if it describes the input chain.

## Testing

- Unit: only the config key (default and parse rows in the existing `AppConfigTests` tables). Voice processing
  needs the microphone, so it is not unit tested (`AGENTS.md` § Testing).
- `swift build` and `swift test` green.
- **Manual, listed in the PR, not claimed as passed** (they need the microphone and speakers):
  1. A video playing through the built-in speakers at normal volume, NoHands in command mode, one minute: no
     actions, and the prompt board shows no rows from the video.
  2. Same video playing: "new tab" in Chrome opens a tab.
  3. `asr` times from `nohands-cli listen` (or the pipeline log) for three short commands with
     `echoCancellation` false, then true. Flag a regression of more than ~50 ms median.
  4. The video's volume does not drop while NoHands listens (ducking check).
  5. Switch the input device (e.g. plug in AirPods) while listening: capture restarts and still produces chunks.
  6. `"echoCancellation": false`: behavior as before, and the log says it is off.

## Non-goals

- Picking a different input device (out of scope in the ticket).
- Our own AEC or a system-audio loopback.
- Menu or HUD controls for the setting.

## Risks

- **Other apps' audio.** Apple documents voice processing as removing "audio coming out of the device". I found
  no primary source that tests audio from *other* apps on macOS. If manual check 1 fails, the PR reports it
  with the default left on (noise suppression still helps) and a follow-up ticket is filed. It is not worked
  around inside this ticket.
- Voice processing adds gain control and noise suppression. That may help or hurt Parakeet accuracy and adds a
  little latency, which manual check 3 measures.

## Calls I made

- **Other apps' audio ducking is turned to the minimum.** The ticket doesn't mention it, but the macOS default
  quiets every other app while voice processing runs. NoHands listens all the time, so without this the video
  in the acceptance test would be turned down rather than cancelled.
- **If voice processing doesn't remove other apps' audio on a real Mac, the default stays true** and a follow-up
  ticket is filed. The acceptance check can't run in an agent session, so the decision is left to the manual
  result.
- **The CLI's `listen` follows the config key too**, so latency measurements match the app.
- **Failure is reported in the log only, not the HUD.** The app still works without it, and product rules keep
  the HUD for failures the user must act on.
- **One new `MicrophoneEvent` case** reports whether it ended up on, so the log answers "is AEC running" without
  a debugger.
- **A bad type for `echoCancellation` invalidates the whole file**, like every other key today, not a silent
  per-key fallback.
- **Gain control and noise suppression stay at Apple's defaults.** The flag bundles them and the ticket doesn't
  ask to tune them.
- **README Privacy keeps advising "go to sleep" for calls and other people talking**, because echo cancellation
  only removes the Mac's own output.
