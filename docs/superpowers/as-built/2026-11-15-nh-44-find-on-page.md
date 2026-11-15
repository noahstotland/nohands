# As-built: Find on page

**Shipped:** in PR #126
**Ticket:** NH-44
**Spec:** [2026-11-15-nh-44-find-on-page-design.md](../specs/2026-11-15-nh-44-find-on-page-design.md)

## Differs from the spec

- **"scroll to" edges.** The spec keeps only "scroll to the top" and "scroll to the bottom" with the model. As built,
  `scroll to` followed by `top`, `bottom`, `top of (the) page`, `bottom of (the) page`, `up`, `down`, `left` or `right`
  all stay with the model, so `scroll to the down` still parses as nothing.
- **"find the newest video"** now parses as a find (it was a stand-in for a phrase the grammar did not handle).
- **`scrollIntoView` is async,** so the 300 ms re-read does not block the main actor, and it needs the frame to meet the
  focused window, not only a screen (a window smaller than the screen can report off-window frames that touch it).
- **The scroll action is the string `AXScrollToVisible`;** Swift does not import `kAXScrollToVisibleAction`.
- **`pinFirst` keeps the list's own element** when it finds the match, so a harness ref and states survive; it runs after
  the observer builds its list, for both native and harness lists.
- **A find settles with one short look** (`SettlePolicy.oneLook`), like the other scroll actions.
- **Words are capped at 120 characters,** not 200: the accessibility layer keeps 120 characters of a title.
- **The walk never descends into text-entry elements** (text fields, text areas, secure fields, combo and search
  fields), whose children hold what the user typed, and a match on the page wins over one in the browser's own chrome.
- **A found element is pinned in the next observation only when the find was the step's last action.**
