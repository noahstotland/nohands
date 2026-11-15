# NH-109: Show a green checkmark by the Claude status when Claude works: Design

**Date:** 2026-11-15  **Ticket:** [NH-109](https://github.com/noahstotland/nohands/issues/109)
**Status:** Shipped
**Shipped:** in PR #131, as specified

## Intent

After a successful "Check Claude connection", the Claude line in the menu reads "Claude: connected at 14:32" in
the same grey as every other state. A green checkmark in front of it makes a working connection readable at a
glance. Every other state looks as it does today.

## Goals, non-goals, anti-goals

Goals are the ticket's Scope and Acceptance.

Non-goals, from the ticket: the menu-bar item (mic image and `CMD`/`DICT`/`ZZZ` text), icons for failure states,
checking automatically, keeping the last result across relaunches.

Anti-goals, which would make this a failure even if it works:

- A checkmark while a check is running, after a failed check, or with no key. A stale tick is worse than none.
- A checkmark that stays after the line text changed back (the attributed title outliving the plain title).
- Any change to the line's wording.

## What the code forces

- `AppDelegate.refreshClaudeItems()` sets `claudeItem.title` from `ClaudeStatus.menuLine`. `NSMenuItem` draws
  `attributedTitle` over `title` when one is set, so the non-connected branch must set `attributedTitle = nil`
  (or always set a full attributed title), or the tick stays.
- `lastClaudeCheck` keeps the old result while a new check runs (`claudeChecking` is true), and the line already
  reads "Claude: checking…" then. The checkmark has to take `checking` too, not only the last result.
- `lastClaudeCheck` is cleared when the backend is switched, so the line and the tick both drop back together.
- `claudeItem` is disabled, so AppKit greys its text. A foreground colour in the attributed string still shows
  on disabled items (the red "● " items are enabled, so this needs the by-eye check).

## Design

### Core

In `Sources/NoHandsCore/ClaudeStatus.swift`, on `ClaudeStatus`:

```swift
/// Whether the menu shows the green checkmark: only for a finished check that connected.
public static func showsCheckmark(checking: Bool, last: ClaudeCheckResult?) -> Bool {
    !checking && last?.kind == .connected
}
```

It takes the same `checking` and last result that `menuLine` takes, so the tick and the text cannot disagree.

### Mac

`refreshClaudeItems()` builds the title from `menuLine`. When `showsCheckmark` is true it sets
`claudeItem.attributedTitle` to a green "✓ " (`NSColor.systemGreen`) followed by the line, the same way the
"● Grant Accessibility…" item is built. Otherwise it sets `attributedTitle = nil` and `title` to the line.

### Tests

One table-driven test in `Tests/NoHandsCoreTests/ClaudeStatusTests.swift` over every `ClaudeCheckKind` (including
`.unavailable(503)` and `.noKey`), crossed with `checking` true and false, plus `last: nil`. Only
`(.connected, checking: false)` is true. It fails if any other kind gets a tick, or if checking doesn't hide it.

### Manual check (listed in the PR)

With a valid key: open the menu, check the connection, see the green tick before "Claude: connected at HH:mm".
Check again and see no tick on "Claude: checking…". With a bad key: no tick on "Claude: key rejected…". Switch the
backend: the tick goes with the result.

## Calls I made

- A coloured "✓ " character in the attributed title, not an SF Symbol image: the menu's only other status marks
  are the coloured "● " characters, and an item image would push every menu title over by the image's width.
- The tick goes in front of the text, like "● ", not after it.
- `NSColor.systemGreen`, the counterpart of the `systemRed` already used.
- While a check runs, the tick goes away even if the previous check connected, since the text then reads
  "checking…".
- The function takes the result, not the `(result, time)` tuple, because the time doesn't matter to the tick.
