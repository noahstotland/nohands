# As-built: Number badges and click-by-name reach web page content

**Shipped:** in PR #20
**Ticket:** NH-17
**Spec:** [2026-11-09-nh-17-browser-page-elements-design.md](../specs/2026-11-09-nh-17-browser-page-elements-design.md)

## Differs from the spec

- A spoken "stop" during the 600 ms settle wait stops the click, move or labels: `ActionExecutor` checks for cancellation after the walk and returns `cancelled` before acting. The plan did not cover this.
- `freshElements` clears a stale exposure flag before its first walk, so a walk from a harness path nobody re-walked for costs no wait.
- The README sentence says what the delay is: up to about half a second more for browser `show numbers` and `click <name>`, and about a second more for the first one in a Chromium browser.
- Test fakes are named `walkLists` and `exposeOnNextWalk`, not the plan's `walks` and `exposeOnce`.
- Page-first order is a known trade-off: a page element named like a toolbar button (for example "Back") can win `click back`. The click stays inside the page.
- The browser walk still runs on the main actor, as the fast path did before.
