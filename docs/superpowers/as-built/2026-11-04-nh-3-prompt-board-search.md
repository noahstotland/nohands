# As-built: Land the prompt board and the search action

**Shipped:** in PR #23
**Ticket:** NH-3
**Spec:** [2026-11-04-nh-3-prompt-board-search-design.md](../specs/2026-11-04-nh-3-prompt-board-search-design.md)

## Differs from the spec

- The spec's plan step 3 asks for a table-driven route test. None was added: `searchPrefersTheSearchBoxThenTheResultsPageThenTheAddressBar` already drives all four routes through the fake `ElementProviding` and pins each route's key presses, so a new test would only restate it. The log lines themselves are not asserted.
- The `siteURL` route line does not carry the page host (`route=siteURL (no search field, known site)`): the host is the user's current page and the log line is public.
- Code review found that a held prompt that is replaced, or dropped by Pause or by "stop" followed by new speech, kept its "held" row. Each of those rows now ends `dropped` (`VoicePipeline`).
- Security review found gaps, all closed: a search box outside the focused window's frame is not clicked (the route is skipped, so Cmd-A and the typing cannot land in another app); the typed query, on every route, has control and format characters dropped and whitespace collapsed (tabs and newlines would be key presses); and text that starts with a script or browser scheme (`javascript:`, `data:`, `file:`, `chrome:` and similar, whatever follows the colon) or any non-http scheme glued to its payload is refused with "can't search for that". `SiteSearch.typable` holds the rule. The spec lists no such refusal.
- The README changes beyond the `search for` rows: the cherry-picked commit also replaces the old HUD wording (Prompt board paragraph, local-model failure line, "Pausing mid-command", "Stopping a task", "Talking while a task runs", the harness paragraph).
- The architecture spec (`2026-11-04-nohands-design.md`) is updated for the prompt board (overlay line, failure handling) and lists the `search` action kind.

## Checks that didn't run

- Live checks 1 to 4 in the spec (Chrome on YouTube, Finder, Calculator, prompt board with "stop"): they need the microphone, Accessibility and real apps. The PR lists them for the user to fill in.
- `nohands-cli eval` on `scripts/intent-eval.json` and `scripts/intent-eval-disfluent.json`: needs a running model.
