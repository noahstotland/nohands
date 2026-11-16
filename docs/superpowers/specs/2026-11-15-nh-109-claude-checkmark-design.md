# NH-109: Show a green checkmark by the Claude status when Claude works: Design

**Date:** 2026-11-15  **Ticket:** [NH-109](https://github.com/noahstotland/nohands/issues/109)
**Status:** Shipped
**Shipped:** in PR #131, as specified

## Intent

After a successful "Check Claude connection", the menu line reads "Claude: connected at 14:32" in the same grey as every other state. A green checkmark in front makes a working connection readable at a glance. Every other state looks as it does today.

Non-goals: the menu-bar item, icons for failure states, automatic checks.

Anti-goals: a checkmark while a check runs, after a failure, or with no key (a stale tick is worse than none); a tick that outlives the line text; any change to the wording.

## What the code forces

- `NSMenuItem` draws `attributedTitle` over `title`, so every non-connected branch of `refreshClaudeItems()` must set `attributedTitle = nil`.
- The old result is kept while a new check runs, so the tick must take `checking` too. Switching the backend clears the result, so line and tick drop together.
- `claudeItem` is disabled and greyed; a foreground colour should still show (checked by eye).

## Design

- **Core:** `ClaudeStatus.showsCheckmark(checking:last:)` is true only for `!checking && last?.kind == .connected`, with the same inputs as `menuLine`, so tick and text cannot disagree.
- **Mac:** when true, `attributedTitle` is a green "✓ " (`NSColor.systemGreen`) plus the line, built like the "● Grant Accessibility…" item.
- **Test:** one table over every `ClaudeCheckKind` crossed with `checking`, plus `last: nil`. Only connected and not checking is true.
- **Manual, in the PR:** the tick shows with a valid key, and not while checking, with a bad key, or after a backend switch.

## Calls I made

- **A coloured "✓ " character, not an SF Symbol.** The other marks are coloured "● " characters, and an item image would shift every title.
- **The tick goes in front of the text**, like "● ".
- **The tick goes away while a check runs** even if the last check connected.
