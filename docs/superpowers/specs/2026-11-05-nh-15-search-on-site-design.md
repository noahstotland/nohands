# NH-15: "search for X on youtube" searches the open site — Design

**Date:** 2026-11-05  **Status:** Shipped  **Ticket:** [NH-15](https://github.com/noahstotland/nohands/issues/15)
**Shipped:** in PR #28, as specified

## Intent

Saying "search for the leafs game on youtube" with YouTube open in Chrome should show YouTube results for
"the leafs game" in that tab. It must not type the whole sentence into the address bar and search Google.

## What `main` does today (after NH-3, PR #23)

Read from the code, not tried live (that needs the microphone and Accessibility):

- The Google bug in the ticket is gone. `CommandGrammar.parse` now splits off "on <site>" / "in <site>" when
  `<site>` has a known results page, and the "on youtube" words are no longer part of the query. The
  `searchForUsesTheFrontAppOrTheNamedSite` test covers "search for X on youtube", "search youtube for X",
  "search for X" and a name that is not a site.
- **What is still wrong:** a named site always becomes `.openURL(resultsURL, app: nil)`. That opens the results
  page in the **default** browser, usually as a **new tab**, even when that site is already the page in front.
  If Chrome is in front on YouTube and Safari is the default browser, the results show up in Safari. The
  ticket asks for the open page to be used: its own search box first, then its results URL in the same tab.
- An unknown site ("search for cats on foobar") falls through to `.search("cats on foobar")`, which searches
  the front page for all the words. That is the same rule that keeps "search for books on history" working.

So this ticket is a small follow-on to NH-3, not a duplicate: NH-3 shipped the routes, this one makes a named
site use them when that site is already open.

## Design

### Core (`NoHandsCore`)

- **New action** `Action.searchSite(String, site: String)`: search for the words on a named site. `site` is a
  key of `SiteSearch.templates` ("youtube.com", "maps.google.com"), never free text, so it is safe to log.
- **`SiteSearch.site(spoken:) -> String?`**: the template key for a spoken site name or domain ("youtube",
  "YouTube.com", "google maps"), using the same `WebAddress` lookup and longest-suffix match that
  `SiteSearch.url(site:query:)` already uses. Nil when the site has no known results page.
- **`SiteSearch.isOn(site:host:) -> Bool`**: whether a page host is that site ("www.youtube.com",
  "m.youtube.com" and "youtube.com" are all on "youtube.com"; "notyoutube.com" is not). The longest template
  match must equal `site`, so a "maps.google.com" page is not counted as "google.com".
- **Grammar:** "search for X on <site>", "search for X in <site>" and "search <site> for X" emit
  `.searchSite(X, site:)` instead of `.openURL`. Everything else in the rule stays: unknown names keep all
  the words as a plain `.search`, "search youtube for" (no words) is nil, and "search the web for cats" is
  still left to the model.
- **`ActionSummary`:** `searchSite(len=N, site=youtube.com)`; the words stay out of the log.
- **Intent schema and decoder: unchanged.** The model never sees these phrases (the grammar claims them) and
  keeps its existing `search` and `open_url` actions. No new model-facing action type.

### Mac (`NoHandsMac`, `ActionExecutor`)

`.searchSite(query, site:)`:

1. Refuse with "can't search for that" when `SiteSearch.typable(query)` is nil, and "text too long" past
   `maxTypedCharacters`, the same as `.search`.
2. If the front page's host (`ax.webURL()`) is on `site`: run the existing `search` routes on that page. Its
   search box gets the words and Return; with no box reachable, the site's results URL is typed into the
   address bar of the current tab (route 2 always applies, since the site has a known results page).
3. Otherwise open the site's results page the way `.openURL(url, app: nil)` does today: the default browser,
   then wait for it to come to the front.

Log line: `search: route=… site=youtube.com (site open)` for step 2, through the existing route logging, and
`search: route=openURL site=youtube.com (site not in front)` for step 3. The words are never in the line.

### README

Change the `search for <words> on <site>`, `search <site> for <words>` row: when that site is the page in
front, it is searched there (its search box, else its results page in the same tab); otherwise its results
page opens in your default browser.

## Tests

- **Grammar (extend `searchForUsesTheFrontAppOrTheNamedSite`, one table):** "search for the leafs game on
  youtube" → `.searchSite("the leafs game", site: "youtube.com")`; "search youtube for X" and
  "search google maps for coffee" → `.searchSite` with their sites; "search for X" → `.search(X)`;
  "search for cats on foobar" → `.search("cats on foobar")`; "search the web for cats" → nil.
- **`SiteSearch.isOn` (one table):** `www.`/`m.` subdomains match, look-alike hosts don't, and a longer
  template ("maps.google.com") is not counted as its parent ("google.com").
- **Executor (one test):** site in front with a search box → box clicked and typed; site in front without a
  box → results URL in the current tab's address bar; another site or another app in front →
  `open(url:appNamed: nil)` with the results URL and no keystrokes; refused text → "can't search for that"
  and nothing typed or opened.
- `scripts/intent-eval*.json` are not edited.

## Manual checks (in the PR)

1. Chrome on youtube.com, say "search for the leafs game on youtube": YouTube results for "the leafs game"
   in the same tab, no Google. Log route `searchField` or `siteURL`, `site=youtube.com`.
2. Chrome on another site, same sentence: YouTube results open in the default browser. Route `openURL`.
3. Finder in front, same sentence: YouTube results open in the default browser; nothing typed into Finder.
4. If check 1 shows route `siteURL` (YouTube's box not found through Accessibility in Chrome), write down
   what `AXQuery.searchFieldFrame` saw in the PR and file a follow-up for the smallest DOM bridge. The
   results-URL route still gives the right page, so it does not block this ticket.

## Out of scope

- A DOM or JavaScript bridge into the browser.
- Opening the results in the front browser when it is not the default browser and the site is not open
  there.
- Finding the site in a background tab or another window.
- New sites in `SiteSearch.templates`.

## Calls I made

- **The ticket is not closed as a duplicate of NH-3.** NH-3 fixed the Google bug, but a named site still
  opens in the default browser instead of the open page, which the ticket's scope asks for.
- **"Open" means the page in the frontmost browser window's current tab.** YouTube in a background tab or
  another window counts as not open, and the results page opens in the default browser as today.
- **When the site is not in front, keep today's behaviour** (default browser, usually a new tab), even if
  another browser is in front. Navigating the front tab away from an unrelated page felt more surprising.
- **An unknown site keeps every word as a plain search of the front page** ("search for cats on foobar"
  searches for "cats on foobar"), and does not go to the model. "on" and "in" are also ordinary words
  ("books on history", "cats in the kitchen"), and sending them to the model would put ordinary commands on
  the network. The ticket comment that says an unknown site goes to the model is only true of the
  "search <site> for X" form, which this keeps.
- **A new `searchSite` action rather than a site field on `search`.** It keeps the model-facing `search`
  action and the intent schema unchanged, and the site comes only from the grammar's fixed list.
- **The site's host is logged publicly** (`site=youtube.com`). It is always one of the fixed template keys,
  never the user's words.
