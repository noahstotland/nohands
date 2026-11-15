# As-built: Settle faster after each task step

**Shipped:** in PR #124
**Ticket:** NH-38
**Spec:** [2026-11-09-nh-38-settle-faster-design.md](../specs/2026-11-09-nh-38-settle-faster-design.md)

## Differs from the spec

The spec file was edited during review to match the build; this lists what the approved first version (bb0a4c8) said.

- The spec said `SettleWatch` keeps the last two readings. It keeps the last three (two transitions), so a ticking value settles on the second poll.
- The spec gave the harness window wait the whole time left in `settleMs`. It is capped at 1500 ms (`TaskRunner.windowWaitMs`) and the rest of `settleMs` is polled, because a window that appears just before `agent-desktop` starts never fires the event.
- The spec put every `type_text` and `type_into` under `oneLook`. Text containing a newline is `full`, because a newline is typed as a Return press.
- The spec said native readings carry no values. They do, so the ticking rule helps on both paths; a ticking text in an element title still takes the full `settleMs`.
- A stop during the window wait now skips the extra observation that would otherwise follow it.
