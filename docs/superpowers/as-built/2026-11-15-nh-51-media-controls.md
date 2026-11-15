# As-built: Media controls by voice

**Shipped:** in PR #137
**Ticket:** NH-51
**Spec:** [2026-11-15-nh-51-media-controls-design.md](../specs/2026-11-15-nh-51-media-controls-design.md)

## Differs from the spec

- `play the video` is not a phrase; it stays with the model, which clicks the page's Play button.
- `play`, `resume`, `skip ...` and `volume ...` phrases keep the full silence window (no early close), so a pause mid-phrase does not split them. `pause`, `mute`, `unmute` and `next`/`previous` still close early.
- Exit full screen on YouTube presses Escape, waits 800 ms, then presses command-control-F if the window still reports full screen (the spec says Escape only).
- Off YouTube, `full screen video` does nothing (`already full screen`) when the window is already full screen. On YouTube it presses `f`.
- A trailing `%` is accepted: `volume 30%` is `volume 30 percent`.
- A speaker with a volume control but no mute property fails mute and unmute with `this speaker can't be muted`.
- A spoken stop halts the key presses and the exit-full-screen follow-up.
