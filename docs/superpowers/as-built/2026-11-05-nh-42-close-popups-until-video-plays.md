# As-built: NH-42 close pop-ups until the video plays

**Shipped:** in PR #65
**Ticket:** NH-42
**Spec:** [2026-11-05-nh-42-close-popups-until-video-plays-design.md](../specs/2026-11-05-nh-42-close-popups-until-video-plays-design.md)

## Differs from the spec

- The spec puts the pop-up rules in the base system prompt. They ship as a `Tab rules` line in the user message, just before the `Tabs:` block, and only when a browser reading exists: with the rules in the system prompt, the local model started answering "close the current tab" with `close_app` or `close_tab`. This also keeps the system prompt one stable cached prefix (NH-37). The Ollama schema offers the three tab kinds only when a `Tabs:` list is present. The Claude schema always lists them (a changed `output_config.format` would drop the cached system block); the Claude system text ends with a `Tab kinds:` rule that limits them to requests showing a `Tabs:` list.
- `select_tab` is also checked for an unknown number ("no tab N").
- The window `task` flag shows only on a window that is also new.
- The executor acts on the id-registered element directly (no fresh read); a dead element reports "tab already closed".
- The unused `ScreenObservation.windows` field is removed (replaced by the tab listing).
- The media-playing signal (NH-43) is wired: rules end on the `Media:` line reading playing.
- A step with a failed action after `open_url` marks no task tab, so the task's own page could show as `new`.
