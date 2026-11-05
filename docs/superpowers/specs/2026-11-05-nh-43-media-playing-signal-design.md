# NH-43: A media-playing signal so a task can tell when the video actually plays — Design

**Date:** 2026-11-05  **Status:** Shipped  **Ticket:** [NH-43](https://github.com/noahstotland/nohands/issues/43)
**Shipped:** in PR #63, with differences: [as-built](../as-built/2026-11-05-nh-43-media-playing-signal.md)

## Intent

"Turn on the latest Outdoor Boys video" is done when the video plays, not when its page has loaded. Today the
task loop ends whenever the model says `done`, and nothing on the observation says whether anything is playing.
This ticket gives the loop and the model a media signal, a way to wait for it, and one check before a play goal
is accepted as done.

## What `main` does today

Read from the code, not tried live:

- `TaskRunner.run` returns `.done` as soon as a `done` step's actions run without failure. Nothing looks at the
  screen afterwards.
- The observation (`ScreenObservation`, rendered by `ClaudeRequestBuilder.userMessage`) has app, window, URL,
  mode, overlay, harness, surface, windows, elements and readings. Nothing about playback.
- The model can `wait` with `wait_for` (`text`, `window`, `event`, `menu`, `menu_closed`, `element`), which the
  agent-desktop harness turns into `agent-desktop wait`. On the native harness `.waitFor` just sleeps up to 5 s,
  and the native prompt does not mention `wait_for`.
- Element titles already carry the accessibility description when there is no title (`AXQuery`: title, else
  description), so YouTube's "Pause (k)" button is in the native walk; agent-desktop snapshots also carry
  values and states.
- CoreAudio is only used for microphone capture.

## Design

### Core (`NoHandsCore`, pure, table-tested)

**`MediaState`**: `playing | paused | none`, raw values as printed.

**`MediaSignal.control(role:name:value:) -> MediaControl?`**: reads one element as a player control, or nil.

- Only button-like roles count (`button`, `checkbox`, `toggle`, `switch`, matched case-insensitively with any
  `AX` prefix dropped). A link or heading named "Play" is not a control.
- The name is lower-cased, a trailing shortcut in parentheses ("Pause (k)", "Play (space)") and surrounding
  punctuation are dropped, then matched exactly against a short list:
  - **pause**: `pause`, `pause video`, `pause button`
  - **play**: `play`, `play video`, `play button`
  - **toggle**: `play/pause`, `play pause`, `playpause`, `play-pause`. A toggle is `pause` when its value says
    `playing` and `play` when it says `paused`; otherwise it tells nothing.
- So "Play all", "Playlist", "Play next" and "Display" are not controls.

**`MediaSignal.state(controls:audioPlaying:) -> MediaState`**, cheapest evidence first:

| Controls in the focused window | Audio from another process | State |
|---|---|---|
| any `pause` | any | `playing` |
| `play`, no `pause` | any | `paused` |
| none | yes | `playing` |
| none | no | `none` |

A visible control speaks for the window in front; audio speaks for the whole Mac, so it is used only when no
control was found.

**`MediaSignal.wantsPlayback(goal:) -> Bool`**: true when the goal's words include `play`, `watch`, `listen`, or
the pairs `turn on` / `put on` (with up to two words between, as in "turn the video on"). Word matching, so
"display" and "replay" do not count; "playing" does not count either (it reads as a question).

**`ScreenObservation.media: MediaState?`**: nil when not observed (the one-shot path, the intent-eval fixtures,
the local model's few-shot examples), so none of those prompts change. When set, `userMessage` prints
`Media: playing` (or `paused` / `none`) on its own line after the `Mode:` line. `Settle.same` also compares
`media`, so a settle after clicking Play waits until the state stops changing.

**Wait condition**: `DesktopWaitKind.mediaPlaying = "media_playing"` (the model-facing `wait_for` list, so the
schema enum picks it up) and `WaitCondition.mediaPlaying`. The decoder accepts `{"kind":"wait",
"wait_for":"media_playing","timeout_ms":…}` with today's timeout rules (default 5000, clamped 500-30000).
`DesktopCommand` never carries it: the executor answers it itself (below), so no `agent-desktop` argv exists
for it.

**Grammar**: "is it playing", "is the video playing" and "is anything playing" emit a new `Action.checkMedia`.
The model cannot produce it (no decoder kind), like `searchSite`. `ActionSummary`: `checkMedia`.

**Prompt rules** (`IntentSchema`, both harness prompts, since `wait_for` is in the shared schema):

- The native prompt gains one line under `wait`: `wait with wait_for "media_playing": wait until media plays in
  the front window. Fields: timeout_ms (500-30000).` The harness rules list `media_playing` among the
  `wait_for` kinds.
- A rule after the status list: *A goal to play, watch, turn on, put on or listen to something is done only when
  the request shows "Media: playing". If the page shows a Play button, click it. If an ad is playing or a
  countdown or "Skip ad" is showing, wait (wait_for media_playing) and look again. "Media: none" means no player
  was found: decide from the screen.*

### Mac (`NoHandsMac`)

**`AudioOutputProbe`** (new, CoreAudio, no permission needed): `isPlaying() -> Bool`.

- On macOS 14.2 and later it walks `kAudioHardwarePropertyProcessObjectList` and is true when any process other
  than NoHands has `kAudioProcessPropertyIsRunningOutput`. Leaving NoHands out matters: with echo cancellation
  (NH-13) or a headset such as AirPods, NoHands' own capture keeps the output device running.
- On 14.0 and 14.1 it falls back to the ticket's `kAudioDevicePropertyDeviceIsRunningSomewhere` on the default
  output device.
- Any CoreAudio error answers false (no hint), never throws.

**`ScreenObserver`** takes the probe (injected, a fake in tests) and fills `observation.media` in the task
loop's `observe`:

- Controls come from the elements it already collected, before the `maxElements` cap and the untitled filter:
  the native walk's elements, or the full agent-desktop snapshot (which also has values for toggles). No extra
  accessibility walk.
- The audio probe is only called when no control was found.

**`ActionExecutor`**:

- `.waitFor(.mediaPlaying, timeoutMs)`, on both harnesses: every 500 ms, walk the front window's elements and
  compute the state as above; `nil` (success) at `playing`, `"wait timed out"` at the timeout. It checks
  cancellation every poll, so "stop" ends it at once. It never calls agent-desktop.
- `.checkMedia`: the same one-shot computation; records a reading `Media: playing` (or `paused` / `none`) and
  succeeds. `VoicePipeline` shows a grammar command's first reading as its `done` detail, so the row reads
  `is it playing · Media: playing`. (Grammar commands take no readings today, so nothing else changes.)

**`TaskRunner`**, the done check: when the goal `wantsPlayback` and a `done` step ran without failure, settle
and observe once more (the screen after the step's actions, as the next step would see it). Then:

- `media` is `playing`, `none` or nil: finish `done` as today.
- `media` is `paused` and this task has not been re-asked yet: record the step in history with the failure
  `not playing yet`, and run the next step on that observation (it counts as a step).
- `media` is `paused` again, or the step cap is reached: finish `stuck("not playing yet")`.

Other goals are untouched: no extra observation, no extra step.

### README

- Voice command table: a row for `is it playing`, `is the video playing`, `is anything playing`: "Says whether
  media is playing in the front window (`playing`, `paused`, `none`)".
- `observe` and `snapshot` CLI rows: mention the media line.

## Tests

One table per rule (`AGENTS.md` § Testing):

- **`MediaSignal.control`** (Core): `Pause (k)` button → pause; `Play` button → play; `Play/Pause` with value
  `playing` → pause, `paused` → play, none → nil; `Play all` button, `Play` link, `Playlist` → nil.
- **`MediaSignal.state`** (Core): the four rows of the table above, including Play with audio → `paused`.
- **`MediaSignal.wantsPlayback`** (Core): "turn on the latest outdoor boys video", "put the video on", "watch
  veritasium", "play some jazz", "listen to the podcast" → true; "display settings", "turn off wifi", "is it
  playing", "open youtube" → false.
- **Observation text** (Core, existing `IntentStepTests` style): `media` nil prints no line; set prints
  `Media: paused`.
- **Decoder** (Core, existing wait table): `media_playing` decodes with default and clamped timeouts.
- **Grammar** (Core, existing fixed-phrase table): the three phrases → `[.checkMedia]`.
- **`TaskRunnerTests`** (one table, fakes for the resolver, the elements and the audio probe): play goal, `done`
  while a `Play` button is showing → re-asked once with `not playing yet` in history; second `done` with
  `Pause` showing → `done`; second `done` still `Play` → `stuck("not playing yet")`; `done` with no controls
  and no audio → `done` at once; a non-play goal with `Play` showing → `done` at once.
- **Executor** (one test): `wait_for media_playing` returns nil once the fake elements show `Pause`, and
  `wait timed out` when they never do, with no harness call either way.
- `scripts/intent-eval*.json` are not edited.

No test needs the microphone, Accessibility, real audio or a model.

## Manual checks (in the PR)

1. YouTube in Chrome, video paused: "is it playing" → `Media: paused`; press space → `Media: playing`.
2. Same in Safari.
3. QuickTime Player with a movie, paused then playing.
4. Spotify playing, Chrome on a YouTube page with a paused video in front: `Media: paused` (the control wins
   over the audio).
5. Echo cancellation on, nothing playing, Finder in front: `Media: none` (NoHands' own capture is not audio).
6. "turn on the latest Outdoor Boys video" end to end: the task finishes only once the video plays; with
   autoplay off, the log shows the `not playing yet` re-ask and a Play click.
7. A pre-roll ad: the model waits instead of finishing.

## Out of scope

- Now Playing metadata (title, artist): private APIs.
- Telling which app is making the sound (Chrome and Safari play through helper processes, so mapping audio to
  the front app needs more than a PID match).
- Pausing, resuming or skipping ads as new commands.
- A DOM bridge to read the `<video>` element's state.

## Calls I made

- **A visible Play button beats audio.** With a Play button and sound from elsewhere (Spotify), the state is
  `paused`. Audio only answers when no control is found. The ticket's table did not cover Play plus audio.
- **Audio from NoHands itself is ignored, using per-process CoreAudio on macOS 14.2+.** The ticket named only
  the device-wide property, but with echo cancellation or AirPods NoHands' own capture would make it read
  "playing" all the time. 14.0-14.1 fall back to the device-wide property.
- **After the re-ask, a second `done` while still `paused` ends `stuck("not playing yet")`.** The ticket said
  "then accepted or stuck"; I read it as accepted if playing, stuck if not. `none` never blocks `done`, so a
  page where no player is found behaves as today.
- **The done check observes again after the `done` step** (one settle, only for play goals), so a step that
  clicks Play and says `done` in one go is judged on the screen after the click.
- **Play goals are matched by words** (play, watch, listen, turn … on, put … on). "turn on wifi" counts too;
  that costs one extra observation and finds `none`, which changes nothing.
- **Exact control names, not substring matches**, so "Play all" and playlist buttons are never read as a
  paused player. A player whose button has some other name reads as `none` (or audio).
- **`wait_for: media_playing` is answered by NoHands, not agent-desktop**, on both harnesses, by polling every
  500 ms. agent-desktop has no media condition. The native prompt learns `wait_for` for this one kind only.
- **The media line is printed only on task observations.** The one-shot path, the intent-eval fixtures and the
  local model's examples keep their exact text, so the local model's cached prefix does not change.
- **"is it playing" shows `Media: playing` on the board row**, the line the model sees, and it is not spoken.
  I added "is the video playing" and "is anything playing" as the same command.
