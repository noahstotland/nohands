# NH-112: Claude token usage: Plan

Spec: [design](../specs/2026-11-15-nh-112-token-usage-design.md). Run `swift build` and `swift test` after each task.

1. **Core.** In `Sources/NoHandsCore/ClaudeUsage.swift`: add `outputTokens` (init default 0, read `output_tokens`), `logFragment` appends `out=<n>`; add `ClaudeUsageTotal` (`adding(_:ClaudeUsage?)`, `menuLine`, `logFragment`) per the spec's formatting rules. Tests (table-driven) in `Tests/NoHandsCoreTests`: `from(response:)` incl. missing `output_tokens`, total adding incl. nil usage, menuLine formatting boundaries. Update the existing `logFragment` assertions.
2. **Mac.** `Sources/NoHandsMac/ClaudeUsageMeter.swift` (`OSAllocatedUnfairLock`, `shared`, `record`, `total`). `ClaudeIntentResolver` and `ClaudeConnectionCheck` take `meter: ClaudeUsageMeter = .shared` and record after each 2xx response, before decoding. `VoicePipeline.runTask` logs `claude: session ...` at task end when the total has calls.
3. **Menu.** `AppDelegate`: disabled `claudeUsageItem` under `claudeItem`, hidden when `menuLine` is nil, refreshed in `refreshClaudeItems()` and from `menuWillOpen`.
4. **README.** Mention the menu line if the README documents the menu.
