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
- A browser that was not in front when the task started is read twice inside one `annotateTabs` call, 300 ms apart (the runner's injected `sleep`), and its baseline is the union of the two reads (`TabLedger.baseline(alsoSeen:)`), so windows and tabs a cold launch or session restore lists one at a time are the user's. No step runs between the two reads, so a pop-up opened by a later acting step is never baselined (one opened by the step that launched the browser can be, which is the safe side). The browser in front at the task's first observation keeps the single-read baseline; a pop-up opened in that one-read gap counts as the user's (safe side).
- The tab read is bounded: at most 40 tabs per tab group, the read deadline is checked inside the tab loop, and the listing shows at most 10 new tabs and windows beyond the front window's own (the front window's own tabs do not count against that), then `+N more new`.
- A window whose tab loop stopped on the cap or the deadline is read with `BrowserWindow.complete == false`. The ledger treats it like a window read empty: it is not fully read at baseline, tabs it shows later join the baseline as the user's, and a tab is only ever `new` in a window whose baseline read was complete.
- The command-W path checks for cancellation after its 100 ms pause, so a spoken stop never lets command-W go out.
