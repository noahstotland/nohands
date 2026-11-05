# NH-3: Land the prompt board and the search action — Plan

**Spec:** [2026-11-04-nh-3-prompt-board-search-design.md](../specs/2026-11-04-nh-3-prompt-board-search-design.md)
**Ticket:** NH-3

## Tasks

1. Branch from `origin/main` and cherry-pick a722a18 (prompt board, `search` action). Done: commit 18eeaab.
2. Add one public `PipelineLog` line per search in `ActionExecutor.search` naming the route (`searchField`, `siteURL`, `addressBar`, `none`) and why earlier routes were skipped. The query stays out of the line. A thrown input error logs a warning naming the route. Done: commit 39aff64.
3. No new test: `searchPrefersTheSearchBoxThenTheResultsPageThenTheAddressBar` already drives all four routes through the fake `ElementProviding` and pins the key presses of each. A log line is not asserted (it would restate the implementation).
4. Verify: `swift build` and `swift test` green in the worktree. The intent fixture eval needs a running model and is a manual check.
5. Open the PR with the ticket linked, the README row change and the live-check list from the spec.

## Review Focus

1. The cherry-pick keeps its original behavior; only the log lines are new.
2. The query text never reaches a `.public` log field.
3. "stop" handling in `VoicePipeline` and `TaskRunner` still halts a running task and is never merged into another utterance (the prompt board changes how both report status).
