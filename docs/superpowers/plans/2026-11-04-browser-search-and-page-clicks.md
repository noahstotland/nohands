# Browser Search and Page Clicks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Status:** Shipped
**Shipped:** NH-3 in PR #23; NH-17 in PR #20, with differences: [as-built](../as-built/2026-11-09-nh-17-browser-page-elements.md)

**Goal:** "Search for the Leafs game on YouTube" searches YouTube (not Google) wherever the user is, "search for X" uses the search box of the page or app in front, and voice clicks and number badges reach a web page's links, buttons and fields in a browser.

**Architecture:** Two tickets, two branches, stacked. NH-3 lands the finished `feat/prompt-status-web-search` branch (the `search` action, `SiteSearch`, the prompt board) as a PR against `main`, plus one diagnostic log line. NH-17 stacks on it: the fast-path accessibility walk in `AXQuery` becomes browser-aware (the page's web area first, a larger budget) and `ActionExecutor` re-walks once after a Chromium page tree is first exposed. Nothing new reaches the model; the task loop and the agent-desktop harness are untouched. A DOM bridge is deliberately deferred (NH-18): Chromium's accessibility tree is already the DOM's projection, and the two gaps found were a grammar rule and a walk budget, not a missing API.

**Tech Stack:** unchanged (Swift 6 strict concurrency, SwiftPM, Swift Testing, ApplicationServices). No new dependencies.

**Spec:** no new spec. The tickets are the spec: [NH-3](https://github.com/noahstotland/nohands/issues/3), [NH-15](https://github.com/noahstotland/nohands/issues/15), [NH-17](https://github.com/noahstotland/nohands/issues/17), [NH-18](https://github.com/noahstotland/nohands/issues/18) (proposal only). Background: `docs/superpowers/specs/2026-11-04-task-agent-design.md` § Observation.

## Root cause (why the sentence went to Google)

`CommandGrammar.parse` on `main` claims every `search for <words>` phrase as a fast-grammar command and emits command-L, type, Return (`Sources/NoHandsCore/CommandGrammar.swift`, the `case "go", "search"` branch). The model never sees the request, so "on youtube" is typed into the address bar as part of the query. `feat/prompt-status-web-search` already replaces that rule: `search for X on <site>` / `search <site> for X` open the site's results page through `SiteSearch.url(site:query:)`, and a bare `search for X` becomes `Action.search(X)`, which `ActionExecutor.search` resolves to the frontmost page's or app's own search box (found by `AXQuery.searchFieldFrame()`), else the site's results URL for the current page's host, else the address bar. Its grammar tests already cover the three NH-15 rows.

## Global Constraints

- Root checkout stays on `main`; work happens in the worktrees named per task. Never push `main`.
- Swift 6 strict concurrency: no `@unchecked Sendable` or `@preconcurrency` added to make a build pass.
- `NoHandsCore` imports only Foundation and CoreGraphics. AX work stays in `NoHandsMac`.
- Ordinary commands never touch the network; the grammar paths here call no model.
- Transcripts and typed text are private: a log line may name a route, never the query.
- Every phrase in the README voice command table keeps working; changed rows are edited in the same PR.
- `swift build` and `swift test` green before a PR; intent fixtures (`scripts/intent-eval*.json`) untouched.
- Test lines do not exceed feature lines in a PR; one table-driven test per rule.
- PRs: conventional commit titles, the ticket linked, a `## Release note` section, the manual checks listed. Use `./scripts/gh.sh`, never bare `gh`.

## Review Focus

1. **"Search for X" in an app with no search box** must not type anywhere: `ActionExecutor.search` returns `nothing to search in <app>` (pinned by `ActionExecutorTests` on the NH-3 branch; Task 1 keeps them green).
2. **The address bar is never mistaken for the page's search box** ("Address and search bar" contains "search"): `SearchField.matches` excludes `address`, `website`, `url` (pinned by `SiteSearchTests`).
3. **A thin first walk in Chrome** (page tree not yet built) must not make "click subscribe" fail silently: Task 2 re-walks once after exposure (pinned by `namedClickRewalksAfterExposure`).
4. **Non-browser apps keep the 150 ms budget**: a browser-sized walk in Finder or Xcode would make every "click save" slow (pinned by `browserWalkOnlyInBrowsers` in Task 2, on the pure policy helper).
5. **Site names the grammar does not know** ("search the web for cats") still go to the model, never to a guessed URL (pinned on the NH-3 branch: `g.parse("search the web for cats") == nil`).

---

### Task 1: Land NH-3 (`feat/prompt-status-web-search`) as a PR

**Worktree:** `/Users/noahstotland/.t3/projects/nohands/.claude/worktrees/prompt-status-web-search`, branch `feat/prompt-status-web-search`, already rebased on `main` (ff9e08b), one commit (3669191). 365 tests passed before the rebase.

**Files:**
- Modify: `Sources/NoHandsMac/ActionExecutor.swift` (the private `search(_:)`): one `PipelineLog.info` line per route.
- Modify: `README.md` only if the rebase left a `Scripts/` (capital S) reference; `main` renamed the folder to `scripts/`.
- Test: `Tests/NoHandsMacTests/ActionExecutorTests.swift` (existing `search` tests stay green; no new test, no bug fixed).

**Interfaces:**
- Produces: the branch tip that Task 2 stacks on. `ElementProviding.frontmostIsBrowser()`, `ElementProviding.searchFieldFrame()`, `AXQuery.otherBrowserBundleIDs`, `AXQuery.chromiumBundleIDs`.

- [ ] **Step 1: Confirm the rebase is clean**

Run: `swift build 2>&1 | tail -3 && swift test 2>&1 | tail -3 && grep -n "Scripts/" README.md`
Expected: build ok, `Test run with 365 tests passed`, no `Scripts/` hits (fix any to `scripts/`).

- [ ] **Step 2: Add the route log line**

In `ActionExecutor.search(_:)`, before each of the three returns and the failure, log which route was taken with `PipelineLog.info`: `"search: page or app search box"`, `"search: results page for <host>"`, `"search: address bar"`, `"search: nothing to search in <app>"`. The query is never logged. Host and app name are not private.

- [ ] **Step 3: Run the suite**

Run: `swift test 2>&1 | tail -3`
Expected: `365 tests passed`.

- [ ] **Step 4: Build the app bundle**

Run: `scripts/bundle.sh 2>&1 | tail -2`
Expected: `build/NoHands.app` assembled. Do not `open` it.

- [ ] **Step 5: Commit and push**

```bash
git add Sources/NoHandsMac/ActionExecutor.swift README.md
git commit -m "fix(mac): log which route a spoken search took"   # with the Co-Authored-By trailer
git push -u origin feat/prompt-status-web-search
```

- [ ] **Step 6: Open the PR against `main`**

`./scripts/gh.sh pr create --base main --title 'feat: prompt board; "search for" uses the page or app search box (NH-3)' --body-file <body>` where the body has: a Summary (one paragraph for the search change, one for the prompt board), `Closes #3`, `Related: #15`, a `## Release note` section (two bullets, user-facing words), a `## Manual checks` list left for the owner (YouTube in Chrome: "search for outdoor boys" uses the page's search box; "search for the leafs game on youtube" from Finder opens YouTube results in the default browser; Finder: "search for notes" uses Finder's search field; an app with no search box: the row says `nothing to search in <app>` and nothing is typed), the test count, and the footer `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.

- [ ] **Step 7: Move the ticket**

`./scripts/gh.sh issue edit 3 --add-label status:in-review` (use the `status:` label that exists; `./scripts/gh.sh label list` shows them). Comment on #15: NH-3's grammar already covers its three rows (`searchForUsesTheFrontAppOrTheNamedSite`); the open-page preference for "on <site>" is a product decision left to the owner.

---

### Task 2: NH-17, browser-aware fast-path walk and one re-walk after exposure

**Worktree:** `/Users/noahstotland/.t3/projects/nohands/.worktrees/nh-17-browser-page-elements`, branch `feat/nh-17-browser-page-elements`, based on Task 1's branch tip. The PR's base is `feat/prompt-status-web-search` until NH-3 merges, then `main`.

**Files:**
- Create: `Sources/NoHandsCore/WalkPolicy.swift`
- Modify: `Sources/NoHandsMac/AXQuery.swift` (`actionableElements(screens:)`, a `firstWebArea` helper shared with `searchFieldFrame()`)
- Modify: `Sources/NoHandsMac/ActionExecutor.swift` (`.showLabels`, `elementsIfNeeded(named:)`, a new `exposureSettle` init parameter)
- Modify: `README.md` (voice command section, one sentence)
- Test: `Tests/NoHandsCoreTests/WalkPolicyTests.swift`, `Tests/NoHandsMacTests/ActionExecutorTests.swift`, `Tests/NoHandsMacTests/Fakes.swift`
- Commit first: this plan file, `docs/superpowers/plans/2026-11-04-browser-search-and-page-clicks.md` (`docs: plan for browser search and page clicks`).

**Interfaces:**
- Consumes: `ElementProviding.frontmostIsBrowser()`, `didJustExpose()`, `actionableElements()` (Task 1 branch).
- Produces:
  ```swift
  // NoHandsCore
  public struct WalkPolicy: Equatable, Sendable {
      public var budget: Duration
      public var maxNodes: Int
      public var pageFirst: Bool
      public static let app = WalkPolicy(budget: .milliseconds(150), maxNodes: 2000, pageFirst: false)
      public static let browser = WalkPolicy(budget: .milliseconds(600), maxNodes: 5000, pageFirst: true)
      /// In a browser: pageFirst, with the larger of the caller's and `browser`'s budget and node cap (the task
      /// loop's 1 s / 6000 walk must not shrink); elsewhere the caller's own.
      public static func pick(isBrowser: Bool, `default`: WalkPolicy) -> WalkPolicy
  }
  // NoHandsMac
  public init(input:ax:overlay:config:frontTimeout:exposureSettle: Duration = .milliseconds(600))   // ActionExecutor
  ```

- [ ] **Step 1: Write the failing Core test**

`Tests/NoHandsCoreTests/WalkPolicyTests.swift`, `browserWalkOnlyInBrowsers`: table of `(isBrowser, default, expected)`: `(true, .app, .browser)`, `(false, .app, .app)`, `(false, WalkPolicy(budget: .seconds(1), maxNodes: 6000, pageFirst: false), that same value)`, `(true, that value, the same budget and node cap with pageFirst: true)`.

- [ ] **Step 2: Run it to see it fail**

Run: `swift test --filter WalkPolicyTests 2>&1 | tail -3`
Expected: compile error, `WalkPolicy` undefined.

- [ ] **Step 3: Implement `WalkPolicy`** in `Sources/NoHandsCore/WalkPolicy.swift` as declared above.

- [ ] **Step 4: Use it in `AXQuery.actionableElements(screens:)`**

`let policy = WalkPolicy.pick(isBrowser: frontmostIsBrowser(), default: WalkPolicy(budget: budget, maxNodes: maxNodes, pageFirst: false))`. Build the `Walker` with `policy.maxNodes` and `policy.budget`. When `policy.pageFirst`: after the menu bar, find the focused window's first `AXWebArea` (extract the `firstWebArea(_:depth:)` closure from `searchFieldFrame()` into a private method both use) and `walker.visit(webArea, depth: 1, descend: true)` before the windows loop; `Walker.firstVisit` already dedupes the second pass. The task loop's observer (built with 1000 ms / 6000 nodes) also goes through `pick` and therefore also gets page-first ordering in browsers, which is intended.

- [ ] **Step 5: Write the failing executor test**

In `Tests/NoHandsMacTests/Fakes.swift`, give the fake element provider a `walks: [[UIElementInfo]]` queue (each `actionableElements()` call pops the next list, the last one repeats) and an `exposeOnce: Bool` that makes `didJustExpose()` return true exactly once. In `ActionExecutorTests.swift`, `namedClickRewalksAfterExposure`: provider with `walks = [[], [subscribe button at (100, 200, 80, 30)]]`, `exposeOnce = true`, executor built with `exposureSettle: .zero`; `execute([.click(.element(named: "subscribe"), button: .left, count: 1)])` returns nil and the fake input recorded one click at the button's centre; a second case with `exposeOnce = false` and the same walks fails with `no element named subscribe` after exactly one walk (assert the provider's call count).

- [ ] **Step 6: Run it to see it fail**

Run: `swift test --filter ActionExecutorTests 2>&1 | tail -3`
Expected: FAIL (one walk, click not delivered).

- [ ] **Step 7: Implement the re-walk**

`ActionExecutor`: store `exposureSettle`. Add `private func freshElements() async -> [UIElementInfo]`: walk; if `ax.didJustExpose()`, `try? await Task.sleep(for: exposureSettle)` and walk again. Use it for `.showLabels` and for a `.click`/`.moveCursor` whose target is `.element(named:)` (resolve the element list before calling `TargetResolver`, replacing `elementsIfNeeded(named:)`). Cancellation: if `Task.isCancelled` after the sleep, return the first walk.

- [ ] **Step 8: Run the suite**

Run: `swift test 2>&1 | tail -3`
Expected: all tests pass (365 + the new ones).

- [ ] **Step 9: README**

In the voice command section, after the `click save` row's table, add one sentence: in a browser, number badges and `click <name>` cover the page's links, buttons and fields as well as the toolbar; the first command after a browser comes to the front can take about a second longer while the page's accessibility tree is built.

- [ ] **Step 10: Commit and push**

```bash
git add Sources/NoHandsCore/WalkPolicy.swift Sources/NoHandsMac/AXQuery.swift Sources/NoHandsMac/ActionExecutor.swift Tests/NoHandsCoreTests/WalkPolicyTests.swift Tests/NoHandsMacTests/ActionExecutorTests.swift Tests/NoHandsMacTests/Fakes.swift README.md
git commit -m "feat(mac): voice clicks and number badges reach web page content in browsers"
git push -u origin feat/nh-17-browser-page-elements
```

- [ ] **Step 11: Open the PR**

`./scripts/gh.sh pr create --base feat/prompt-status-web-search --title 'feat(mac): number badges and click-by-name reach web page content (NH-17)'` with: Summary, `Closes #17`, `Stacked on #<NH-3 PR number>; retarget to main after it merges`, `## Release note`, `## Manual checks` (YouTube in Chrome: "show numbers" badges the search box and the first video links; "click search" focuses the page's search box, not the address bar; Finder: "show numbers" unchanged and as fast as before), the footer line. Label the ticket `status:in-review`.

---

### Not planned: NH-18, the DOM bridge

Filed as a proposal only. Build it only if the live checks of Tasks 1 and 2 show a page element the user names that Accessibility cannot find or click. The ticket fixes the shape in advance: fixed, parameterized AppleScript JavaScript in Chrome or Safari behind the browser's "Allow JavaScript from Apple Events" setting, parameters passed as a JSON argument, model output never executed as script.
