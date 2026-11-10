# NH-17: number badges and click-by-name reach web page content — Design

**Date:** 2026-11-09
**Status:** Shipped
**Ticket:** [NH-17](https://github.com/noahstotland/nohands/issues/17)
**Shipped:** in PR #20, with differences: [as-built](../as-built/2026-11-09-nh-17-browser-page-elements.md)

Written after the build: the ticket and the [plan](../plans/2026-11-04-browser-search-and-page-clicks.md) were the spec.

## Intent

"Show numbers" and "click subscribe" in Chrome labelled the toolbar and tabs but rarely the page, because the fast-path accessibility walk (150 ms, 2000 nodes) spent its budget on the toolbar before reaching the page's web area.

## Behaviour

- In a browser, the walk visits the focused window's first `AXWebArea` right after the menu bar, with a budget of 600 ms and 5000 nodes. A caller that already walks longer (the task loop: 1 s, 6000 nodes) keeps its own budget. Other apps keep 150 ms and 2000 nodes. The rule is `WalkPolicy.pick` in `NoHandsCore`.
- After a walk that first exposes a Chromium page tree, `show numbers` and a named click or move wait 600 ms and walk once more. A spoken stop during the wait stops the action.
- The README says badges and `click <name>` cover page content in browsers.

## Leaves out

A DOM or JavaScript bridge (NH-18), and the task loop's observer and the agent-desktop harness.

## Calls made

- Page content comes before the toolbar, so a page element named like a toolbar button can win `click back`. The click stays inside the page.
- The walk still runs on the main actor, as before.
