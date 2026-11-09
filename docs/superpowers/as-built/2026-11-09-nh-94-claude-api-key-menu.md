# As-built: Menu item to enter the Claude API key

**Shipped:** in PR #107
**Ticket:** NH-94
**Spec:** [2026-11-09-nh-94-claude-api-key-menu-design.md](../specs/2026-11-09-nh-94-claude-api-key-menu-design.md)

## Differs from the spec

- The spec's Alert section leaves listening on while the alert is open. It ships paused: `setClaudeKey` pauses listening before `runModal` and resumes after, so dictation can't type into the key field and a spoken "press return" can't press Save. The menu and status bar show Paused meanwhile. It does nothing when there is no pipeline, when the user had already paused, or when Accessibility is revoked, so it never overrides those pauses.
- A path at `config.json` that exists but is not a regular file (a folder, a FIFO) throws `writeFailed(EINVAL)`, not `symlink`. It is still refused with nothing changed.
- Known gap: opening the alert while the pipeline is still starting, or before a chosen Resume finishes, does not pause (security review pass 1, Low).
