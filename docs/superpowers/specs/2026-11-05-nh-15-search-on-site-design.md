# NH-15: "search for X on youtube" searches the open site — Design

**Date:** 2026-11-05  **Status:** Shipped  **Ticket:** [NH-15](https://github.com/noahstotland/nohands/issues/15)
**Shipped:** in PR #28, as specified

## Intent

"Search for the leafs game on youtube" with YouTube open in Chrome shows YouTube results in that tab. It must not type the sentence into the address bar and search Google.

NH-3 already splits off "on <site>" for sites with a known results page. Still wrong: a named site always became `.openURL(resultsURL, app: nil)`, opening the default browser, usually a new tab, even when that site is in front.

## Design

### Core (`NoHandsCore`)

- New `Action.searchSite(String, site: String)`. `site` is a key of `SiteSearch.templates` (such as "youtube.com"), never free text, so it is safe to log.
- `SiteSearch.isOn(site:host:)`: subdomains match, look-alikes ("notyoutube.com") do not, and "maps.google.com" is not "google.com".
- Grammar: "search for X on <site>", "in <site>" and "search <site> for X" emit `.searchSite`. Unknown names keep all words as a plain `.search`.
- The log shows the site key, never the words. The intent schema and decoder are unchanged.

### Mac (`ActionExecutor`)

For `.searchSite`:

1. Refuse untypable or too-long text, as `.search` does.
2. If the front page's host is on `site`, run the existing `search` routes there: the page's search box gets the words and Return, else the results URL is typed into the current tab's address bar.
3. Otherwise open the results page in the default browser, as today.

## Tests

Table-driven grammar and `SiteSearch.isOn` cases, and an executor test for the box, the URL fallback, another site or app in front, and refused text. Manual, in the PR: Chrome on YouTube searches in the same tab; another site or Finder in front opens the default browser.

README: a named site is searched in place when it is in front, else its results page opens in the default browser.

## Out of scope

A DOM or JavaScript bridge; finding the site in a background tab or window; new sites.

## Calls I made

- **"Open" means the current tab of the frontmost browser window.** A background tab counts as not open.
- **When the site is not in front, keep today's behaviour,** even if another browser is in front. Navigating an unrelated tab away is more surprising.
- **An unknown site stays a plain search, not a model call.** "on" and "in" are ordinary words ("books on history").
- **A new `searchSite` action, not a site field on `search`,** which leaves the model-facing schema unchanged.
