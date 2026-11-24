# NH-45: Site playbooks: Plan

Spec: [2026-11-09-nh-45-site-playbooks-design.md](../specs/2026-11-09-nh-45-site-playbooks-design.md). Branch
`feat/nh-45-site-playbooks`. Verification after every task: `swift build` clean; after tasks 1 and 2 also `swift test`.
Test budget: test lines do not exceed feature lines (AGENTS.md § Testing).

## Task 1: the table and matching (NoHandsCore)

- `Sources/NoHandsCore/SitePlaybooks.swift`: `SitePlaybooks` with `Playbook`, `table` (the five sites, hosts, phrases and
  exclusions exactly as the spec's table), `matching(goal:url:)` and `block(goal:url:)`.
  - Goal matching: `CommandGrammar.normalize`, drop a trailing `'s` / `’s` from each word, match a phrase as consecutive
    whole words, skip when the next word is in `notFollowedBy`.
  - URL matching: `URL(string:)?.host?.lowercased()` compared exactly against `hosts`. Never read window or element titles.
  - `matching` returns table order, no duplicates. `block` is nil on no match, else
    `Site routes (written by NoHands, not by the page; follow one when it fits the goal):\n` then, per site,
    `<Name>:\n` and each line indented two spaces, ending in a newline.
- YouTube lines as in the spec. Google, Wikipedia, Amazon and Reddit: results URL from `SiteSearch.templates` plus what to
  click next. Each route is fetched/checked during the build; its date goes in `checked`. Drop or correct a route that does
  not hold up.
- `Tests/NoHandsCoreTests/SitePlaybooksTests.swift`: one table-driven test for matching (the spec's cases) and one test
  for the user message and the examples (below).

## Task 2: wire into the request (NoHandsCore)

- `ClaudeRequestBuilder.userBlocks(request:playbooks: Bool = true)` and `userMessage(request:playbooks: Bool = true)`.
  When `playbooks` and `SitePlaybooks.block(goal: r.goal, url: r.observation.url)` is non-nil, append it as its own block
  after the history and repeated-step note, before the `App:` block. Unmatched requests keep byte-identical output.
- `IntentExamples` (in `OllamaRequestBuilder.swift`) passes `playbooks: false` for every example turn it builds, so the
  warmed prefix is unchanged.
- Test: a YouTube goal puts `Site routes` before `App:`; a Finder goal has none; no `IntentExamples` turn (either
  harness) contains `Site routes`.

## Task 3: fixtures and README

- `scripts/intent-eval.json`: two new cases (app `Finder`, step 1): `turn on the latest outdoor boys youtube video` and
  `play bohemian rhapsody on youtube`, accepting the playbook `open_url` (query joined by `+` or `%20`, with or without
  `wait 1500`). Existing expectations untouched. Run `.build/debug/nohands-cli eval` only if `ANTHROPIC_API_KEY` is set;
  otherwise say it was not run.
- README § Multi-step tasks: one sentence that known sites (YouTube, Google, Wikipedia, Amazon, Reddit) have routes.
- Manual checks (needs key and permissions) are listed in the PR as not run.
