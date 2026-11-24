# As-built: agent-desktop harness, live runs

**Shipped:** in PR #186
**Ticket:** NH-4
**Spec:** [2026-11-04-nh-4-verify-harness-live-design.md](../specs/2026-11-04-nh-4-verify-harness-live-design.md)

## Runs

2026-11-23, MacBook Pro, agent-desktop 1.1.0, screen unlocked, Accessibility granted to the agent shell. The task runs used Claude (`claude-haiku-5-5`, `intentBackend: claude`); `claude-check` connected first. Both tasks ran once, so no retry budget was used.

| # | Command | Harness | Outcome | Steps | Settle per step (ms) | Time |
|---|---|---|---|---|---|---|
| 0 | `desktop-status` | agent-desktop 1.1.0 | accessibility granted | n/a | n/a | n/a |
| 0b | `agent-desktop list-windows` | n/a | windows listed, several `accessible: true`; no locked-screen signature | n/a | n/a | n/a |
| 1 | `snapshot TextEdit` | agent-desktop | 26 refs, 21 listed, `complete=true` | n/a | n/a | 3.3 s wall |
| 2 | `snapshot "Google Chrome"` | agent-desktop | 96 refs, 93 listed, `complete=true` | n/a | n/a | 2.7 s wall |
| 3 | `observe` | agent-desktop | same 21 elements as run 1, `Harness: agent-desktop` | n/a | n/a | 5.1 s wall (includes the command's own 4 s of waits) |
| 4 | `task "type hello and save it as nh4-live-test"` | agent-desktop (`harness: agent-desktop` line) | **done** | 2 | 760, 1066 | 5.4 s task, 10.6 s wall |
| 5 | `task "open the Veritasium channel's newest video"` | agent-desktop | **done**, video playing | 8 | 1049, 1650, 1804, 822, 759, 1631, 741, 935 | 37.8 s task, 43.1 s wall |

Acceptance is met: the TextEdit task ended `done` through agent-desktop. Run 4 saved the file as `nh4-live-test`, not `test`: `~/Documents/test` is a directory the user keeps, so the goal used a name that cannot collide with it, and that directory was never touched. (The save landed in TextEdit's last-used folder, not in a new directory.) The file is `~/Downloads/nh4-live-test.rtf` (TextEdit's last-used save folder) and holds the text `hello`. It stays there for the user to remove.

## Runs 1–3: what matched the screen

- **TextEdit** (a new blank document, checked against a screenshot): window `Untitled`; the text area `focused`; typeface `Helvetica`, style `Regular`, size `12`; `align left` checked and the other three not; bold, italic and underline `0`; line spacing `1.0`; Close, Full Screen and Minimize present. Two disabled scrollbars show the ratios of an empty document. Matches.
- **Chrome** (fullscreen video, so the toolbar and tab strip were hidden): every browser element carries `offscreen`, which is right for a fullscreen window. The tab titles and the address bar value matched the tab strip and URL. The toolbar appears three times because agent-desktop lists Chrome's three fullscreen toolbar windows. The `snapshot` command prints `URL: -` (it passes none); `observe` printed the real URL.
- **`observe`** printed the same list as `snapshot` for TextEdit and the page URL for Chrome.

## Differs from the spec and the README

- `nohands-cli snapshot <app>` does not wait 3 s when the app is named (only the no-argument form does). `docs/cli.md` and the usage text now say so.
- `main` had moved 143 commits since the spec: a vision fallback, plans, site playbooks and many guards. `task` runs now batch actions per step (run 4's first step typed, saved and typed the name in one go).
- The step log did not say which harness the task used. `TaskRunner` now exposes `taskHarness`, `harnessFallbackReason` and `harnessReport`, and `nohands-cli task` prints `harness: agent-desktop` or `harness: native (fallback: …)` after step 1. A test covers the fallback in `TaskRunnerTests`.
- Before run 5 a new Chrome window was made with `osascript`, so the task would not take over the user's fullscreen tab. The final screenshot showed the video in a window whose tab strip also held the user's earlier tabs, which were all still open; which window the task's `openURL` used was not checked.

## Failures and tickets

- **NH-185** ([#185](https://github.com/noahstotland/nohands/issues/185)): in run 5, steps 3, 5 and 7 were lone Escape presses to close what the model called an open "Apple menu". Three of eight steps. The step log prints actions, not observations, so the cause (a stale overlay, a click that hit a menu bar item, or a model misread) isn't known. Left as a ticket: finding it needs per-step observation logging and a rerun.
- Run 5's last step clicked the video and declared `done` in the same step, without a check. The video was playing (0:17 on screen, uploaded 5 days earlier by the Veritasium channel).

## Checks that didn't run

- Ollama (local model) task runs, out of scope for this ticket.
- Run 5 on the native fallback, and run 4 on the native fallback: both loaded agent-desktop, so the fallback path was covered only by the unit test with the fake harness.
- Whether the Chrome video was the channel's newest upload was judged from the page by eye, not by a scripted check.
