# NH-43: A media-playing signal so a task can tell when the video actually plays — Design

**Date:** 2026-11-05  **Status:** Shipped  **Ticket:** [NH-43](https://github.com/noahstotland/nohands/issues/43)
**Shipped:** in PR #63, with differences: [as-built](../as-built/2026-11-05-nh-43-media-playing-signal.md)

## Intent

"Turn on the latest Outdoor Boys video" is done when the video plays, not when the page loads. `TaskRunner.run` returned `.done` once a `done` step succeeded, and observations said nothing about playback. Add a media signal, a way to wait for it, and one check before a play goal is accepted as done.

## Design

### Core (`NoHandsCore`, pure, table-tested)

- **`MediaSignal.control`** reads an element as a player control or nil: button-like roles only, name matched exactly after dropping a trailing shortcut like "(k)" (pause, play, or a play/pause toggle read through its value). "Play all" and "Playlist" are not controls.
- **`MediaSignal.state`**: a `pause` control means `playing`; `play` without `pause` means `paused`; with no control, audio from another process means `playing`, else `none`. A control speaks for the front window, audio for the whole Mac, so audio is the fallback.
- **`MediaSignal.wantsPlayback(goal:)`**: the goal has the word `play`, `watch` or `listen`, or `turn on` / `put on` (up to two words between). "display", "replay" and "playing" do not count.
- **`ScreenObservation.media: MediaState?`**: nil outside task observations, so one-shot, intent-eval and local few-shot prompts keep their text. When set, `userMessage` prints `Media: playing` after `Mode:`; `Settle.same` compares it.
- **Wait condition** `wait_for: "media_playing"` (default 5000 ms, clamped 500-30000). The executor answers it; no `agent-desktop` call exists for it.
- **Grammar**: "is it playing", "is the video playing", "is anything playing" emit a new `Action.checkMedia`, which the model cannot produce.
- **Prompt rule** (both harnesses): a play goal is done only when the request shows `Media: playing`. Click a visible Play button; if an ad or countdown shows, wait and look again. `Media: none` means no player was found: decide from the screen.

### Mac (`NoHandsMac`)

- **`AudioOutputProbe`** (CoreAudio, no permission): true when any process other than NoHands has running output (per-process on 14.2+; the default device's running flag on 14.0-14.1). Any error answers false.
- **`ScreenObserver`** fills `media` from elements already collected, with no extra walk. The probe runs only when no control was found.
- **`ActionExecutor`**: `wait_for media_playing` recomputes the state every 500 ms on both harnesses, succeeds at `playing`, else "wait timed out"; "stop" cancels it at once. `.checkMedia` computes once and records the reading.
- **`TaskRunner` done check**: for a `wantsPlayback` goal, after a successful `done` step, settle and observe once more. `playing`, `none` or nil finishes `done`. The first `paused` records `not playing yet` as a failure and runs one more step. A second `paused`, or the step cap, finishes `stuck`. Other goals get no extra observation.

## Tests

One table per rule, no microphone, audio or model: `MediaSignal` (control, state, wantsPlayback), observation text, decoder, grammar phrases, the `TaskRunner` done check with a fake probe (re-ask once, then `done` or `stuck`; non-play goals unaffected), and the executor wait. Manual checks go in the PR.

## Out of scope

Now Playing metadata (private APIs); mapping audio to the front app; ad controls; a DOM bridge to `<video>`.

## Calls I made

- **A visible Play button beats audio** (Play plus Spotify sound is `paused`).
- **Audio from NoHands itself is ignored:** with echo cancellation or AirPods its own capture would always read "playing".
- **A second `done` while `paused` ends `stuck`.** `none` never blocks `done`, so a page with no found player behaves as before.
- **The done check observes again after the `done` step,** so click-Play-then-`done` is judged after the click.
- **Play goals match by words.** "turn on wifi" counts too, at the cost of one observation.
- **Exact control names, not substrings,** so playlist buttons are not players.
- **NoHands answers `media_playing` itself;** agent-desktop has no media condition.
- **"is it playing" shows its reading on the board row** and is not spoken.
