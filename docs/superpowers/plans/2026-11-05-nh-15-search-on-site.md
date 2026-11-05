# NH-15 Search on the Open Site Implementation Plan

**Goal:** "search for X on youtube" searches inside YouTube when it is the page in front (its search box, else its results URL in the same tab); otherwise it opens the results page in the default browser as today.

**Spec:** `docs/superpowers/specs/2026-11-05-nh-15-search-on-site-design.md`. Read it first.

**Constraints:** Swift 6 strict concurrency, no new `@unchecked Sendable`. `NoHandsCore` stays free of AppKit. The query is never in a log line (log `site=<template key>` only). `scripts/intent-eval*.json` are not edited. The intent schema and `IntentDecoder` do not change. `swift build` and `swift test` green after each task. Table-driven tests, within the AGENTS.md budget.

## Task 1: Core

- [ ] `Action.searchSite(String, site: String)` with a doc comment (site is a `SiteSearch.templates` key).
- [ ] `SiteSearch.site(spoken:) -> String?` (same `WebAddress` lookup and longest-suffix match as `url(site:query:)`; refactor so both share one `templateKey(forHost:)` helper) and `SiteSearch.isOn(site:host:) -> Bool` (longest template match for the host equals `site`; case-insensitive; "notyoutube.com" is not on youtube.com; "maps.google.com" is not on google.com).
- [ ] `CommandGrammar`: both site forms ("search <site> for X", "search for X on|in <site>") return `.searchSite(X, site:)` when `SiteSearch.site(spoken:)` is non-nil. Everything else in the rule is unchanged.
- [ ] `ActionSummary.kind`: `searchSite(len=N, site=youtube.com)`.
- [ ] Fix any other exhaustive switch the compiler flags (the decoder keeps rejecting unknown kinds; there is no `search_site` in the schema).
- [ ] Tests: update the existing grammar expectations in `searchForUsesTheFrontAppOrTheNamedSite` (and any other test that expected `.openURL` for these phrases) in the same table; add a `SiteSearch.isOn` table; extend the `ActionSummary` expectation next to the `search` one.

## Task 2: Executor (NoHandsMac)

- [ ] Extract the `.openURL` case body into a helper (`openURLAction(url, app:, isLast:)` returning the failure string or nil) used by both cases.
- [ ] `.searchSite(query, site:)`: refuse `text too long` past `maxTypedCharacters`; `SiteSearch.typable(query)` nil gives `can't search for that` (nothing typed or opened). If `ax.webURL()`'s host `isOn(site:)`: run the existing `search` routes (search box, else results URL in the address bar), logging `search: route=… site=<key> (site open)`. Otherwise: `SiteSearch.url(host: site, query:)` through the shared open helper, logging `search: route=openURL site=<key> (site not in front)`. The words are never logged.
- [ ] Share the route code with `.search` (add an optional site parameter used only for the log line); do not duplicate it.
- [ ] One test in `ActionExecutorTests`: site in front with a box (clicked and typed), site in front without a box (results URL in the address bar), another site in front and Finder in front (`open(url:appNamed: nil)` with the results URL and no keystrokes), refused text (`can't search for that`, nothing typed or opened). Use the existing fakes; extend them only if the open call is not already recorded.

## Task 3: README

- [ ] Replace the `search for <words> on <site>`, `search <site> for <words>` row text per the spec § README. No other README change.

## Verify

`swift build`, `swift test`, and the intent fixtures (`.build/debug/nohands-cli eval scripts/intent-eval.json` and `scripts/intent-eval-disfluent.json`) if they run without a model; manual checks go in the PR as not run.
