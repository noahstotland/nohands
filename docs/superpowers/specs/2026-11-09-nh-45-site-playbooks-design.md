# NH-45: Site playbooks — Design

**Date:** 2026-11-09  **Ticket:** [NH-45](https://github.com/noahstotland/nohands/issues/45)
**Status:** Shipped
**Shipped:** in PR #122, with differences: [as-built](../as-built/2026-11-15-nh-45-site-playbooks.md)

## Intent

"Turn on the latest Outdoor Boys YouTube video" should follow a known route, not rediscover YouTube one step at a
time. The model gets a few fixed lines of route text for the sites people use most, and only when the goal or the
current page involves that site.

## Today

- `IntentSchema.systemPrompt` has one YouTube hint and prefers a direct URL such as
  `youtube.com/@mapleridgeworkshop/videos`. A guessed handle can land on a 404.
- `SiteSearch.templates` knows results URLs. Nothing says what to do once the results page loads.
- `ClaudeRequestBuilder.userBlocks(request:)` builds the user message for both backends. The system block is the
  only cached prefix on Claude. On Ollama the few-shot examples (`IntentExamples`) are built with that same function
  and sit in the warmed prefix.
- A goal that passes `PlanGate.mayPlan` first asks for a `TaskPlan`, written from the transcript alone. `PlanEngine`
  runs it with no model in the loop. The ticket's own example goal passes that gate.

## Approaches

1. **A table in Core, added as its own user-message block by `userBlocks`.** One place, both backends, the task loop
   and one-shot requests alike. The system prompt and schema don't change, so the cache holds. Chosen.
2. **Add the routes to the system prompt.** Rejected: the ticket rules it out, it costs tokens on every request, and
   it changes the cached prefix.
3. **Set the text on `StepRequest` from `TaskRunner` and the CLI.** Rejected: every caller has to remember it, and
   the fixtures would need their own wiring.

## Design

### Table (`NoHandsCore/SitePlaybooks.swift`, new)

```swift
public enum SitePlaybooks {
    struct Playbook: Sendable {
        let name: String            // "YouTube"
        let phrases: [[String]]     // words that name the site in a goal
        let notFollowedBy: Set<String>
        let hosts: Set<String>      // compared exactly, lower-cased
        let checked: String         // date the route was verified in a browser
        let lines: [String]
    }
    static let table: [Playbook]
    static func matching(goal: String, url: String?) -> [Playbook]   // table order, no duplicates
    public static func block(goal: String, url: String?) -> String?  // nil when nothing matches
}
```

| Site | Goal phrases | Not when followed by | Hosts |
|---|---|---|---|
| YouTube | `youtube`, `you tube` | | `www.youtube.com`, `youtube.com`, `m.youtube.com` |
| Google | `google` | `chrome docs drive maps calendar sheets slides meet photos earth mail` | `www.google.com`, `google.com` |
| Wikipedia | `wikipedia` | | `en.wikipedia.org`, `www.wikipedia.org`, `wikipedia.org` |
| Amazon | `amazon` | `prime music kindle web` | `www.amazon.com`, `amazon.com` |
| Reddit | `reddit` | | `www.reddit.com`, `old.reddit.com`, `reddit.com` |

Goal matching uses `CommandGrammar.normalize` and drops a trailing `'s` or `’s` from each word, so "youtube's" counts.
URL matching parses the host with `URL(string:)` and compares it exactly. `SiteSearch.templateKey(forHost:)` is not
reused, because its subdomain rule would put Gmail and Docs on Google and AWS on Amazon.

The window title and element titles are never read for matching. A page can only select an entry by actually being
on that host, and no page text goes into the block.

### YouTube lines (the other sites follow this shape)

```
Latest video of a channel: do not guess a @handle unless the request or the screen shows it. open_url
https://www.youtube.com/results?search_query=<name, words joined by +>&sp=EgIQAg%253D%253D (channels only), then
wait 1500. Click the first channel result, then its Videos tab, then the first video, which is the newest.
Play a video or song: open_url https://www.youtube.com/results?search_query=<words joined by +>, then wait 1500.
Click the first video result that is not marked Sponsored.
Player keys, once the video page is open: k play or pause, f full screen, m mute.
```

Google, Wikipedia, Amazon and Reddit each get a results URL (the one in `SiteSearch.templates`) and what to click
next. Each route is checked in a browser during the build, and that date goes in `checked`. A route that doesn't
hold up is corrected or dropped. The YouTube channel filter was fetched once at spec time (2026-11-09, plain HTTP):
21 channel results, 0 video results, and `@OutdoorBoys` first for "outdoor boys".

### Request (`ClaudeRequestBuilder.userBlocks`)

- `userBlocks(request:playbooks: Bool = true)` and `userMessage(request:playbooks: Bool = true)`.
- When `SitePlaybooks.block(goal: r.goal, url: o.url)` is not nil, it becomes its own block after the history and the
  repeated-step note and before the `App:` observation block:

  ```
  Site routes (written by NoHands, not by the page; follow one when it fits the goal):
  YouTube:
    <lines>
  ```

- A goal and page with no match produce the same bytes as today. The existing golden test pins that.
- Every step and every one-shot request gets the block, on both backends. The fixtures run as one-shots, so they
  exercise it.
- `IntentExamples` passes `playbooks: false`, so the few-shot turns and the warmed Ollama prefix stay byte-identical
  even though some of them mention YouTube.
- No new action, no decoder change. What the model does with a route still goes through the schema and the task guards.

### Fixtures and README

- Two new cases in `scripts/intent-eval.json`, app `Finder`, step 1 only. No existing expectation changes.
  - `turn on the latest outdoor boys youtube video`
  - `play bohemian rhapsody on youtube`
  - Each accepts the playbook `open_url`, with the query joined by `+` or `%20`, with or without `wait 1500`.
- README § Multi-step tasks gets one sentence saying that known sites have routes.

## Testing

Core, no network, table-driven:

- **Matching:** goal and URL in, names out. Covers: the ticket's goal; `you tube`; `youtube's`; a Finder goal (none);
  `open google chrome` (none); `google cats` (Google); `notyoutube` (none); a page on `www.youtube.com` with an
  unrelated goal (YouTube); `youtube.com.evil.example`, `evil.example/youtube.com` and `docs.google.com` (none); a nil
  URL; a goal and page naming the same site (one entry); two different sites (both).
- **User message:** a YouTube goal has the YouTube lines before `App:`; a Finder goal has no `Site routes` text.
- **Examples:** no `IntentExamples` turn, native or harness, contains `Site routes`.

Fixtures, on Claude: both `intent-eval` files pass.

Manual, recorded in the PR with step counts (needs a key and the permissions):

1. `turn on the latest outdoor boys youtube video`. Note whether a plan ran it.
2. The same goal with `in chrome` added. Naming a browser skips the planner, so this run is the one that tests the
   route in the loop.

## Leaves out

- Learned routes from past runs (#46) and sites behind a login.
- Any change to the system prompt, the schema or `PlanQuestion`.
- Playbooks for sites beyond the five the ticket names.
- Regional hosts (`amazon.co.uk`) and non-English Wikipedia.

## Calls I made

- **The planner does not get playbooks.** The ticket's example goal passes `PlanGate`, so on a good plan the route
  text is never sent. The playbook reaches the model only when there is no plan or a plan hands over. Plans have a
  closed step set with no way to express the channel filter URL, and teaching them would be a separate change to
  `PlanQuestion` and `TaskPlan`. That's why the manual check has a second run that skips the planner. If the
  planned run takes more steps than the loop run, that is a case for a follow-up ticket.
- **The system prompt's handle hint stays**, even though it leans the other way. The playbook line says not to guess a
  handle. Editing the shared prompt would move the cached prefix and every fixture's baseline for one hint.
- **Trigger is the site's name in the goal, as the ticket says.** "Latest video of Outdoor Boys" with no mention of
  YouTube gets no playbook on step 1. It gets one once the page is on YouTube.
- **Hosts match exactly**, not by subdomain, to keep Google's route off Gmail and Docs.
- **`google` and `amazon` have exclusion words**, so "open google chrome" and "amazon prime video" don't pull in a
  search route. `you tube` is accepted because speech recognition splits it.
- **Both backends get the block.** The ticket says "the model". It adds a small amount of text to the local model's
  last turn only, and that turn isn't cached anyway. The ticket's acceptance is on Claude only.
- **One-shot requests get the block too**, because the fixtures run that way. A plain "open youtube" that reaches the
  model carries the lines too. The existing fixtures will show whether that hurts.
- **All matching sites are included** with no cap. There are five short entries at most.
- **The first fixture's phrase says "youtube"**, so the playbook fires under the rule above.
