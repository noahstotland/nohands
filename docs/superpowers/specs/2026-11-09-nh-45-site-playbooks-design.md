# NH-45: Site playbooks — Design

**Date:** 2026-11-09  **Ticket:** [NH-45](https://github.com/noahstotland/nohands/issues/45)
**Status:** Shipped
**Shipped:** in PR #122, with differences: [as-built](../as-built/2026-11-15-nh-45-site-playbooks.md)

## Intent

"Turn on the latest Outdoor Boys YouTube video" should follow a known route, not rediscover YouTube step by step. The model gets fixed route text for the most-used sites, only when the goal or page involves that site.

## Approaches

- **A Core table, added as its own user-message block** (chosen): the system prompt and schema don't change, so the cache holds.
- Routes in the system prompt: rejected (tokens every request, changes the cached prefix).

## Design

- `SitePlaybooks` in Core is a table: name, goal phrases, excluding words (so "open google chrome" doesn't match), exact hosts, verified date, lines. Sites: YouTube (`youtube`, `you tube`), Google, Wikipedia, Amazon, Reddit.
- Goal matching uses `CommandGrammar.normalize` and drops a trailing `'s`. URL matching compares the parsed host exactly, because `SiteSearch.templateKey(forHost:)` would put Gmail and Docs on Google.
- No page text goes into the block.
- YouTube lines: do not guess a `@handle`; `open_url` the channel-filtered results search (`&sp=EgIQAg%253D%253D`), wait 1500, click the first channel, its Videos tab, then the first video (the newest). To play a video, search and click the first result not marked Sponsored. Other sites get a results URL and what to click next.
- `userBlocks` and `userMessage` take `playbooks: Bool = true`. A match becomes its own block after the history and before the `App:` block, headed "Site routes (written by NoHands, not by the page; follow one when it fits the goal)". No match produces the same bytes as before.
- `IntentExamples` passes `playbooks: false`, so few-shot turns and the warmed Ollama prefix stay byte-identical.
- No new action or decoder change. Two new `scripts/intent-eval.json` cases (the ticket goal and `play bohemian rhapsody on youtube`); no existing expectation changes.

## Testing

- Table-driven matching, including `you tube`, `youtube's`, `notyoutube` (none), host spoofs such as `youtube.com.evil.example` (none) and one site named twice (one entry).
- The lines appear before `App:` for a YouTube goal, never for a Finder goal, and never in `IntentExamples`.
- Both `intent-eval` files pass on Claude. Manual: the ticket goal, then with `in chrome` (skips the planner).

## Leaves out

- Learned routes (#46), logins, other sites, regional hosts, changes to the system prompt, schema or `PlanQuestion`.

## Calls I made

- **The planner gets no playbooks.** The ticket goal passes `PlanGate`, so on a good plan the route is never sent, and plans can't express the channel filter URL.
- **The system prompt's handle hint stays**, though it leans the other way: editing it moves the cached prefix and every fixture baseline.
- **Trigger is the site's name in the goal.** A goal without "YouTube" gets the playbook once the page is on YouTube.
- **Both backends and one-shot requests get the block**; the fixtures run one-shot.
