# NH-15 Search on the Open Site Implementation Plan

**Goal:** "search for X on youtube" searches inside YouTube when it is the page in front (search box, else results URL in the same tab); otherwise it opens the results page as today.

**Spec:** `docs/superpowers/specs/2026-11-05-nh-15-search-on-site-design.md`. Read it first.

**Constraints:** the query is never logged (log `site=<key>` only); the intent schema and fixtures are unchanged.

## Task 1: Core

- `Action.searchSite(String, site:)`, grammar-only.
- `SiteSearch.site(spoken:)` and `isOn(site:host:)` (longest template match; "notyoutube.com" is not youtube.com).
- Both grammar search forms return it.

## Task 2: Executor

- Site in front: reuse the `.search` routes. Otherwise open the results URL. Refuse too-long or untypable text.
- One test covers the routes and refusals.

## Task 3: README

- Update the two search rows.
