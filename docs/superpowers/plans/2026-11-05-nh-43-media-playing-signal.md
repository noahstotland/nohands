# NH-43 media-playing signal — Plan

**Spec:** [2026-11-05-nh-43-media-playing-signal-design.md](../specs/2026-11-05-nh-43-media-playing-signal-design.md)

Task 0 (verification, run after every task): `swift build` and `swift test` (no permissions, no Ollama).
Tests follow `AGENTS.md` § Testing: one table per rule, test lines not above feature lines.

## Task 1: Core types and rules
`MediaSignal.swift` in `NoHandsCore`: `MediaState`, `MediaControl`, `control(role:name:value:)`, `state(controls:audioPlaying:)`, `wantsPlayback(goal:)`. `ScreenObservation.media: MediaState?`; `ClaudeRequestBuilder.userMessage` prints `Media: …` after the `Mode:` line only when set; `Settle.same` compares `media`. Tests: `MediaSignalTests` (control, state, wantsPlayback tables) and one observation-text check.

## Task 2: Wait kind, action, grammar, prompts
`DesktopWaitKind.mediaPlaying`, `WaitCondition.mediaPlaying`, decoder case (default 5000, clamp 500-30000), `Action.checkMedia` (no decoder kind, `ActionSummary`), grammar phrases "is it playing" / "is the video playing" / "is anything playing", prompt text in `IntentSchema` (native `wait` line, harness `wait_for` list, play-goal rule). Check `DesktopCommand.argv` stays exhaustive (executor answers the wait itself). Extend the existing decoder and grammar tables. The `scripts/intent-eval*.json` fixtures are not edited and must still pass offline checks.

## Task 3: Mac probe, observer, executor
`AudioOutputProbe` (CoreAudio, per-process `kAudioProcessPropertyIsRunningOutput` excluding own PID on 14.2+, device-wide fallback below, errors -> false), protocol-injected into `ScreenObserver` (fake in tests); fill `observation.media` in the task observe from collected elements (before cap and untitled filter), probe only when no control. `ActionExecutor`: `.waitFor(.mediaPlaying)` polls every 500 ms on both harnesses, cancellable, "wait timed out"; `.checkMedia` adds reading. Executor test for the wait.

## Task 4: TaskRunner done check
Play goal + `done` without failure: settle/observe once; `paused` first time -> history failure "not playing yet" and continue; `paused` again or step cap -> `stuck("not playing yet")`; `playing`/`none`/nil -> done. Non-play goals untouched. One table test in `TaskRunnerTests`.

## Task 5: README
Voice table row for the three phrases; `observe` and `snapshot` CLI rows mention the media line (and make the CLI print it if it prints observations).
