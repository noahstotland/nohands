# NH-60: Spoken feedback: Design

**Date:** 2026-11-16  **Ticket:** [NH-60](https://github.com/noahstotland/nohands/issues/60)
**Status:** Shipped
**Shipped:** in PR #PRNUM, with differences: [as-built](../as-built/2026-11-16-nh-60-spoken-feedback.md)

## Intent

When a video is full screen or the user is across the room, the prompt board can't be seen. NoHands should be able to
say how a task ended ("Done: open the menu", "Stuck: no Raptors game listed"), and, when asked for more, the question
it is waiting on ("Which one, the 7 pm or the 10 pm?") and what it read, out loud.

## Goals, non-goals, anti-goals

Goals are the ticket's Scope and Acceptance, with the changes listed under Calls I made.

Non-goals: reading web pages or documents aloud; a wake word; speaking grammar commands ("go back", "scroll down");
speaking the open-file pick list (NH-58); choosing a voice or rate in config; speech in the `nohands-cli` dev tool.

Anti-goals, which would make this a failure even if it works:

- NoHands hears its own voice as a command, a question's answer or a spoken "yes" to an irreversible step.
- A spoken "stop" fails to halt the running task because NoHands was talking, or is merged with the speech.
- NoHands speaks while dictating (its words would be typed) or while asleep.
- Private text (rewrite results, the clipboard, a field's or the selection's text, anything a task read) is spoken at
  any level but `all`, or longer than 300 characters.
- Speech goes anywhere but the Mac's own output, or the spoken text reaches a log without the private marker.
- With `speakFeedback` off (the default), anything changes: no synthesizer is created, no audio node is added.

## What the code forces

- **The finish line is a `PromptStatus`.** `TaskRunner.finish` reports `finalStatus(outcome, text:, steps:)`:
  `.done("done · open the menu (2 steps)")`, `.failed("stuck: no Raptors game listed (5 steps)")`, `.stopped`,
  `.ignored`. Macros report `.done("done · 3 steps")` or `.failed(…)`; a rewrite reports `.done(<first six words>…)`.
  These rows all run in the task slot (`activeTask`); grammar commands report inline.
- **Questions and confirms are `.running` strings.** A model `ask` step shows `.running("step n · ? <question>")`
  (question clipped to 80) and waits in `awaitAnswer(.question)`; an irreversible step shows
  `.running("step n · say yes to <verb>")` and waits in `awaitAnswer(.confirm)`. Parsing those strings back would be
  fragile, so the speech function takes a small cue built where the status is made.
- **What a task read is in its history.** `readClipboard`, `readValue`, `readPage` and `readNotifications` feed
  "Read:" lines to the model, which then restates them in its `done` intent. Whether any ran is known in `TaskRunner`.
- **Echo cancellation is macOS voice processing on the capture engine** (`MicrophoneCapture.applyVoiceProcessing`,
  `echoCancellation` on by default). It cancels for certain only what plays out through the same engine's output
  node; the engine's `mainMixerNode` is already in the graph for that reason. It may be off by config, or refused by
  macOS (`MicrophoneEvent.echoCancellation(false)`).
- **A stop phrase is checked first** (`AttentionGate.isStop` in `isComplete`, `busy`, `answersPick` and `process`),
  skips the merge window, and in `busy` cancels the runner and the task.
- **Menu choices that change config** go through `ConfigPatch.merged` (as the Model submenu writes `intentBackend`).
- **`AVSpeechSynthesizer` is in AVFoundation**, already linked. `write(_:toBufferCallback:)` hands back PCM buffers;
  `AVSpeechUtterance.prefersAssistiveTechnologySettings` uses the user's Spoken Content voice and rate.

## Approaches

1. **Speak through the capture engine's own output (chosen).** Synthesize with `write(_:toBufferCallback:)` and play
   the buffers on an `AVAudioPlayerNode` attached to `MicrophoneCapture`'s engine, so voice processing has NoHands'
   voice as its echo reference and removes it before VAD. A word-overlap echo filter in Core backs it up.
2. **`AVSpeechSynthesizer.speak()` to the system output.** Simplest, but voice processing has no reference for audio
   played by another unit; whether it is cancelled depends on macOS. Used only when echo cancellation is off or
   refused, where there is no reference to give anyway.
3. **Mute the microphone while speaking.** Certain, but "stop" and the answer to a question could not cut in, which
   breaks the stop invariant's spirit. Rejected.

## How it works

### Config and level (Core)

```swift
public enum SpeakLevel: String, Codable, Sendable, CaseIterable { case off, outcomes, all }
// AppConfig
public var speakFeedback: SpeakLevel = .off
```

Lenient decode: a missing key, an unknown string or a non-string is `off`. `off` speaks nothing; `outcomes` speaks a
task's finish line; `all` adds questions, the spoken-yes prompt and the full text of lines that carry private text.
Unlike other keys, `speakFeedback` takes effect without a restart when the menu or a voice phrase changes it.

### What is spoken (Core, `SpokenFeedback`)

```swift
public enum FeedbackCue: Equatable, Sendable {
    /// A task-slot row (model task, macro, rewrite) reported this status. `carriesPrivateText`: the detail may hold
    /// text the user did not say: the task read something, or it is a rewrite.
    case status(PromptStatus, carriesPrivateText: Bool)
    case question(String)   // the board's question text
    case confirm(verb: String)
}
public enum SpokenFeedback {
    public static let maxSpoken = 300
    public static func line(for cue: FeedbackCue, level: SpeakLevel) -> String?
}
```

| Cue | `outcomes` | `all` |
|---|---|---|
| `listening`, `heard`, `held`, `running` | nothing | nothing |
| `stopped`, `dropped`, `ignored` | nothing | nothing |
| `done("done · open the menu (2 steps)")` | "Done: open the menu." | same |
| `done("done · 3 steps")` (macro) | "Done." | same |
| `failed("stuck: no Raptors game listed (5 steps)")` | "Stuck: no Raptors game listed." | same |
| `failed("timed out")` | "Timed out." | same |
| `done(…)`, private | "Done." | the line, cut at 300 |
| `failed("stuck: …")`, private | "Stuck." | the line, cut at 300 |
| `failed(other)`, private | "Failed." | the line, cut at 300 |
| `question("which one, the 7 pm or the 10 pm")` | nothing | "Which one, the 7 pm or the 10 pm?" |
| `confirm(verb: "send")` | nothing | "Say yes to send." |
| any cue, level `off` | nothing | |

The line is the board's wording, made speakable: a trailing `(N step[s])` and a `· N steps` segment are removed,
`" · "` becomes `": "`, `…` is dropped, whitespace is collapsed, the first letter is capitalized and a full stop (a
question mark for a question) is added when there is none. Cutting at 300 characters ends on a word boundary. An empty
result is nothing.

### Not hearing itself (Core, `SelfEcho`; Mac)

Three layers, strongest first:

1. **Echo cancellation on and running:** speech plays through the capture engine (Approach 1), so voice processing
   subtracts it before VAD and ASR. This is the normal case.
2. **Echo filter, always on while speaking:** `SelfEcho.isEcho(transcript:, utteranceEnd:, spoken:)` is pure. A
   transcript whose utterance ended between the start of a spoken line and 1 s after it finished is treated as
   NoHands' own voice when at least 70% of its normalized words (all of them, when it has fewer than three) are words
   of that line. It is dropped before routing: never a command, never a question's answer, never a confirm's yes.
   Logged as `ignore(own voice)`, not shown on the board.
3. **A stop phrase is checked before the filter** and always acts, even if it might be an echo: the worst it can do
   is stop something, which is the safe direction.

With **echo cancellation off or refused by macOS** (`echoCancellation(false)`), speech goes to the system output with
`speak()` and only layers 2 and 3 apply. The speaker still hears NoHands, so "stop" said over its voice may be
misheard and need saying again; the lines are short (one finish line, at most 300 characters at `all`). The docs say
so next to `echoCancellation`.

With a **Bluetooth headset** (AirPods), the voice plays in the ears and the headset mic picks up little of it; voice
processing still runs as it does today, and the engine already drives the output, so playing speech through it adds
no new route switch. Built-in mic with headset output: no acoustic path, the filter is a backstop. Checked by hand.

The speech never contains a confirm's yes words: `Say yes to <verb>.` is the only line with "yes", and an echo of it
is dropped by layer 2. `IrreversibleGuard`'s yes rule is unchanged.

### When it speaks and stops (Mac, `FeedbackSpeaker`)

A `@MainActor` class in `NoHandsMac`, owned by the pipeline, created only when the level is not `off`.

- **Speaks:** each task-slot row's final status once (by row id), each question and confirm prompt once at `all`.
  A new line replaces the one playing (newest wins); nothing queues.
- **Never speaks** in dictation mode or sleep mode, or while listening is paused. Entering dictation or sleep cuts the
  current line.
- **Cuts** on: a stop phrase (before `busy`/routing handle it; the task is still cancelled exactly as today), any
  transcript that passes the echo filter (the next command, a question's answer), a new task starting, `stop()` and
  `pause()`. It cuts when the transcript arrives, not at voice onset: an onset could be its own echo.
- **Voice and rate** follow the system (`prefersAssistiveTechnologySettings`, the Spoken Content settings); volume
  follows the output volume. System voices are on-device; nothing is sent anywhere.
- **Engine changes:** `MicrophoneCapture` gains `play(_ buffer:)`/`cancelPlayback()`, attaching one player node to
  `mainMixerNode` on first use. A configuration-change rebuild re-attaches it; a line playing at that moment is
  dropped.
- **`TaskRunner`** sets `carriesPrivateText` when any read action ran this task; a rewrite row always carries it. The
  pipeline turns the runner's `.question`/`.confirm` waits into cues alongside the existing `onStatus` reports.

`AudioOutputProbe` already leaves NoHands' own process out on macOS 14.2 and later. On 14.0 and 14.1 it asks whether
the output device runs at all, so a media check during speech may see "playing"; the next command cuts the speech
first, so this is a rare, short window. Noted, not fixed.

### Changing the level (Mac, menu and voice)

- **Menu:** a "Speak Feedback" submenu with Off, Outcomes and All, the current one checked. Choosing one writes
  `speakFeedback` through `ConfigPatch.merged` (same refusals and file mode as the Model submenu) and applies it at
  once.
- **Voice (grammar, Core):** `spoken feedback on` / `turn on spoken feedback` (→ `outcomes`), `spoken feedback off` /
  `turn off spoken feedback` (→ `off`), `spoken feedback all` / `speak everything` (→ `all`). A new
  `Action.setSpokenFeedback(SpeakLevel)`, grammar only (the intent decoder has no kind for it), joins the exhaustive
  switches. Turning it on confirms by speaking "Spoken feedback on."; turning it off shows the board row only. None
  of these phrases is a stop phrase or changes the meaning of one that works today.

## Privacy and security

- **Spoken:** only the lines in the table. Lines that may hold private text are reduced to one word below `all`; at
  `all` they are cut at 300 characters. Questions and confirms are spoken only at `all`.
- **Logged:** one unified-log line per spoken line with the cue kind and character count; the text only with the
  private marker. Never in the command log.
- **Sent:** nothing. Synthesis uses the on-device system voices; ordinary commands still never touch the network.
- **Input:** the echo filter only ever drops transcripts; it cannot create an action. No global key or mouse hook.
- **Docs:** `docs/privacy.md` gains a "Spoken feedback" bullet with the above.

## Docs

- `docs/configuration.md`: a `speakFeedback` row (`off`, `outcomes`, `all`), that it applies without a restart, and a
  sentence by `echoCancellation` on what happens with it off.
- `docs/voice-commands.md`: rows for the new phrases, and that "stop" also cuts NoHands' voice.
- `docs/using-nohands.md`: the Speak Feedback submenu.
- `docs/privacy.md`: as above.

## Tests

Per `AGENTS.md` § Testing, one table-driven test per rule:

- Core `SpokenFeedback` table: every row above, including that `listening`, `heard`, `held` and `running` are never
  spoken at any level, `off` speaks nothing, private lines are one word below `all`, the 300-character cut ends on a
  word.
- Core `SelfEcho` table: an echo inside the window is dropped; the same words after the window, or a different
  command, pass; short transcripts need all words; a stop phrase is never treated as echo (checked by the caller,
  asserted in the pipeline test).
- Core config: `speakFeedback` missing, each value, unknown string, non-string; `ConfigPatch` writes only that key.
- Core grammar: the new phrases to `setSpokenFeedback`; "stop", "stop dictating" and "stop the music" unchanged.
- Mac pipeline with a fake speaker: a task's done is spoken once; "stop" during speech cuts it and still cancels a
  running task; an echoed question is not taken as the answer; nothing is spoken in dictation.

Manual (in the PR): built-in speakers with echo cancellation on, a task ending done is spoken once and not executed
back; "stop" cuts it; echo cancellation off; AirPods; `all` with a question and a clipboard reading; the menu and
voice toggles apply without a restart.

## Calls I made

- **Voice phrases to change the level** (`spoken feedback on/off/all`, `turn on/off spoken feedback`,
  `speak everything`) were added beyond the ticket: a hands-free user can't reach the menu.
- **The menu is a submenu with three levels**, not a single toggle, and it writes `speakFeedback` to config.json
  (like the Model submenu) so the choice survives a restart.
- **The speech function takes a small cue, not only a `PromptStatus`:** questions and confirms are `.running`
  strings on the board, and whether a line holds private text is not in the status.
- **Anything a task read makes its finish line private**: below `all` it is just "Done.", "Stuck." or "Failed.". So
  "what's on my clipboard" at `outcomes` says only "Done."
- **The spoken-yes prompt (NH-61) is spoken at `all`**, with the questions.
- **Only task-slot rows are spoken** (model tasks, macros, rewrites); grammar commands and their failures stay silent,
  and so do `stopped`, `dropped` and `ignored`.
- **Speech plays through the capture engine** when echo cancellation is on, so voice processing has the reference.
- **An echo filter drops transcripts that repeat the spoken line** during it and 1 s after, even with echo
  cancellation on. Cost: a real command that repeats those words in that second is dropped, and a "yes" said over
  the "Say yes to …" prompt must be said again after it.
- **A stop phrase always acts**, even if it could be an echo.
- **Speech is cut when the next transcript arrives**, not at voice onset, so its own echo can't cut it.
- **Newest line wins**; nothing queues.
- **Voice and rate come from the Spoken Content settings**; no config key for them.
- **Not fixed:** on macOS 14.0 and 14.1 the media check may see NoHands' voice as audio playing.
