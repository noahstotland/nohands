# As-built: A media-playing signal so a task can tell when the video actually plays

**Shipped:** in PR #63
**Ticket:** NH-43
**Spec:** [2026-11-05-nh-43-media-playing-signal-design.md](../specs/2026-11-05-nh-43-media-playing-signal-design.md)

## Differs from the spec

- The spec said `VoicePipeline` already shows a grammar command's first reading on the row. It did not; the pipeline now reads the executor's readings, so "is it playing" shows `Media: …`.
- The media wait and "is it playing" walk the front window with the task observer's larger accessibility budget (1000 ms, 6000 nodes), off the main actor, not the default one. `ActionExecutor` takes an optional `mediaAX` for it.
- The ad rule in the prompt says an ad countdown or "Skip ad" means the video has not started even if the player shows Pause: wait a few seconds, click Skip ad, look again. The spec's "wait with `media_playing`" would return at once during an ad.
- `wantsPlayback` does not count "watch later" or "apple watch".
- `ActionExecutor` and `ScreenObserver` take injectable audio probes (and a poll interval) for tests.
