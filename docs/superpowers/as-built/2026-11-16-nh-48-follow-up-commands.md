# As-built: Follow-up commands that refer to the last task

**Shipped:** in PR #146
**Ticket:** NH-48
**Spec:** [2026-11-16-nh-48-follow-up-commands-design.md](../specs/2026-11-16-nh-48-follow-up-commands-design.md)

## Differs from the spec

- The spec keeps the earlier screen as one `endedOn` line; `EarlierTask` stores app, window and URL as separate fields (same line in the request).
- The "Ended … on:" screen is the last screen the task read: before its final step, or after the final settle when the goal is about playing media. It is not a fresh read at the end.
- A single-word opener ("no", "nope", "actually", "also", "instead") alone is not a follow-up: at least one more word must follow. The spec's phrase list only said the words start the request.
- A follow-up that ends `ignored` or `failed` keeps the earlier memory, so a retry still works.
- The earlier goal counts for the "done only when playing" check unless the new words ask to pause, stop or mute.
- The kept steps include the final `done` step.
- Menu Pause also clears the memory, and a chained goal over 300 characters cuts its older part, not the new words.
