# NH-38: Settle faster after each task step: Plan

Spec: [2026-11-09-nh-38-settle-faster-design.md](../specs/2026-11-09-nh-38-settle-faster-design.md). The spec is the source of truth.

1. **Policy and watch (Core).** `SettlePolicy` (`none`, `oneLook`, `full`) is the highest level among a step's actions. `SettleWatch` settles when the last two observations match, or differ only in a ticking element value. Any change to app, title, URL, surface, media or element identities is real. One table test each.
2. **Runner (Mac).** `none` observes once with no sleep; `oneLook` sleeps `min(minSettleMs, settleMs)` then observes; `full` polls with `SettleWatch`. `settleMs` stays the wall-time limit on every path. The post-`done` check stays `full`. For `open_url` or `open_app` with no window under `agentDesktop`, wait for `windowOpened` within the time left; a failed wait never fails the step. The task outcome line logs `settle=<a>+<b>`. Tests cover each policy, a ticking value, stop during the wait, and a timed-out wait.
3. **Docs.** README: the wait depends on the step; `settleMs` (default 3000) is the maximum. Untested fixtures and the manual YouTube timing go under Not proven.
