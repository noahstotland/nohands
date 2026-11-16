# As-built: Follow-up commands that refer to the last task

**Shipped:** in PR #146
**Ticket:** NH-48
**Spec:** [2026-11-16-nh-48-follow-up-commands-design.md](../specs/2026-11-16-nh-48-follow-up-commands-design.md)

## Differs from the spec

- The spec keeps the earlier screen as one `endedOn` line; `EarlierTask` stores app, window and URL as separate fields (same line in the request).
- The "Ended … on:" screen is the last screen the task read before its final step, not a read at the end.
- A backend switch while a task runs clears the memory at once, but that task sets it again when it finishes.
