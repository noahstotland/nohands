# NH-79: Mail voice commands: Design

**Date:** 2026-11-15  **Ticket:** [NH-79](https://github.com/noahstotland/nohands/issues/79)
**Status:** Shipped
**Shipped:** in PR #140, as specified

## Intent

Reading and answering mail hands-free needs Mail's shortcuts, and today none of them can be said: dictation writes a
body once a compose window has focus, but nothing opens one, replies, sends, archives or moves between messages. This
ticket adds a Mail pack (`com.apple.mail`) on the NH-76 mechanism, the same shape as the Terminal pack (NH-84): a
table file, a line in the pack registry, a table test and rows in `docs/voice-commands.md`.

## Goals, non-goals, anti-goals

Goals are the ticket's Scope and Acceptance, plus `send`, since #61 has shipped (see Calls).

Non-goals (the ticket's Out of scope): writing or rewriting message text (#54, #55), other mail clients, searching for
spoken words ("search mail for invoices" still goes to the model), choosing a file in the attach sheet.

Anti-goals, which would make this a failure even if it works:

- A Mail phrase changes what a phrase does in any other app, or with no app in front.
- Any phrase is "stop" or contains "stop", or a stop phrase reaches the pack.
- A bare one-word phrase sends mail, so a stray "send" in the room can send a draft.
- A global phrase used while writing (`delete`, `up`, `down`, `undo`, `find`) changes meaning in Mail, so dictating
  and editing a reply behaves differently from every other app.

## What the code forces

- **The pack mechanism exists** (`NoHandsCore/AppPack.swift`). A pack is a `[String: [Action]]` of normalized
  phrases; `CommandGrammar.parse(_:frontmost:)` tries the pack's whole phrase first, then the global table, then the
  pack after dropping a leading "open" / "go to" and one article, so "go to the inbox" reaches an `inbox` entry and
  "open a new message" reaches `new message`. Stop phrases never reach a pack. `shippedPacksAreWellFormed` checks every
  shipped pack for stop phrases, empty actions and unnormalized keys.
- **A pack phrase wins over the global one** with the same words. The global table has `delete` (⌫), `up`, `down`,
  `undo`, `find` and `close window`; a Mail entry under those exact words would change them while composing, so the
  pack uses longer phrases ("delete message", "next message").
- **The grammar runs a phrase without the #61 confirm.** `IrreversibleGuard` and the "say yes to send" pause live in
  `TaskRunner` and cover steps the model chose; its rule is that a request that names the verb allows it ("send the
  email" allows Send). A spoken grammar phrase is the user naming the verb, so `send message` runs like every other
  pack chord.
- **Mail's menu titles on macOS 14.5**, read from `Mail.app/Contents/Resources/MainMenu.loctable` on this machine:
  New Message, Reply, Reply All, Forward, Send, Get New Mail, Mark as Read (its title flips to Mark as Unread), Toggle
  Flag, Archive, Move to Junk, Delete, Show Mailbox List (flips to Hide), Go to Favorite Mailbox, Mailbox Search,
  Attach Files…, Close. Several of them flip with the selection, so a toggle chord is steadier than a title.

## Approaches

1. **One pack of chords in its own Core file (chosen).** No menu walk, testable as a table, and each chord is the one
   Mail shows in its menus. The exception is `sent`, which has no fixed chord (⌘2 and up follow the user's Favorites
   bar), so it is a menu item by title.
2. **Menu items by title throughout.** Steadier when a shortcut is remapped, but "mark as read" would match "Mark All
   Messages as Read" when the message is already read (`MenuMatch` falls back to titles that hold every spoken word),
   and every phrase pays the Accessibility walk. Kept as the fallback for a chord the manual check finds broken.
3. **Send through a spoken confirm in the grammar.** Safer against a misheard "send", but needs a new pending-confirm
   state in `ModeMachine` and the pipeline for one phrase, and #61's own rule already treats a named verb as consent.
   Multi-word send phrases (Calls) keep the mishearing risk low instead.

## How it works

### `NoHandsCore/MailPack.swift`

```swift
extension AppPack {
    static let mail: AppPack = { ... AppPack(name: "Mail", bundleIDs: ["com.apple.mail"], phrases: phrases) }()
}
```

and `AppPacks.all = [.terminal, .mail]` (a sibling pack ticket landing first only adds a neighbour in that list).
Phrases (normalized keys):

| Phrases | Action |
|---|---|
| `new message`, `new email`, `new mail`, `compose`, `compose message`, `compose email` | ⌘N |
| `reply`, `reply to this`, `reply to message`, `reply to the message` | ⌘R |
| `reply all`, `reply to all` | ⇧⌘R |
| `forward`, `forward this`, `forward message`, `forward the message` | ⇧⌘F |
| `send message`, `send the message`, `send this message`, `send email`, `send the email`, `send this email`, `send mail` | ⇧⌘D |
| `undo send` | ⌘Z (Mail's Undo Send while its delay runs) |
| `next message`, `next email` | ↓ |
| `previous message`, `previous email`, `last message` | ↑ |
| `get new mail`, `get mail`, `check mail`, `check for new mail`, `check email` | ⇧⌘N |
| `mark as read`, `mark read`, `mark as unread`, `mark unread` | ⇧⌘U (toggles read and unread) |
| `flag`, `flag message`, `flag this`, `unflag`, `unflag message` | ⇧⌘L (toggles the flag) |
| `archive`, `archive message`, `archive this`, `archive it` | ⌃⌘A |
| `move to junk`, `junk`, `mark as junk`, `junk message` | ⇧⌘J |
| `delete message`, `delete this message`, `delete the message`, `delete email`, `delete this email`, `trash message`, `move to trash` | ⌘⌫ |
| `show mailboxes`, `hide mailboxes`, `mailbox list`, `show mailbox list`, `hide mailbox list` | ⇧⌘M (toggles the sidebar) |
| `inbox`, `inbox mailbox` (so `go to inbox`, `go to the inbox`) | ⌘1 |
| `sent`, `sent mail`, `sent mailbox`, `sent messages` (so `go to sent`) | `.menuItem("Mailbox > Go to Favorite Mailbox > Sent")` |
| `search mail`, `search mailbox`, `search email` | ⌥⌘F (Mailbox Search) |
| `attach a file`, `attach file`, `attach files`, `add attachment`, `attach` | ⇧⌘A (opens the Attach Files sheet) |
| `close message`, `close email`, `close this message` | ⌘W |

### `docs/voice-commands.md`

Rows in the Per-app commands table (App `Mail`), one per group above, and a sentence: read, flag, junk and the
mailbox list toggle; `go to sent` needs Sent in the Favorites bar; `next message` / `previous message` move the
selection in the message list; and the global `delete`, `undo`, `find`, `up` and `down` keep their meaning while
writing. The ticket says README; the table moved to `docs/voice-commands.md` in NH-119.

## Tests

Core, table-driven (`MailPackTests.swift`, no permissions):

- **Mail in front:** a sample phrase from each group, including a lead-word form ("go to the inbox", "open a new
  message"), resolves to its action through the shipped `CommandGrammar()`, so the registry line is tested too.
- **Another app or none in front:** each sampled phrase does not resolve to its Mail action with `com.apple.Safari` or
  no app in front.
- **Global phrases unchanged in Mail:** `delete`, `up`, `down`, `undo`, `find`, `close window`, `stop`, `cancel` give
  in Mail what they give with no app in front. No Mail phrase is a stop phrase or has "stop" as a word, and no
  one-word phrase sends (every send phrase has at least two words).

Manual on macOS 14 (listed in the PR, with any phrase that fails): each phrase in Mail through
`nohands-cli parse "<phrase>" --app com.apple.mail` for the dry run and by voice; send with a draft to self, then
`undo send`; `go to sent` with and without Sent in the Favorites bar; `next message` with the message list focused.

## Calls I made

- **`send` is in the pack, as a two-word phrase only (`send message`, `send email`, ...), with no spoken confirm.**
  The ticket held send until #61 shipped a confirm; #61 is closed, and its guard's rule is that a request naming the
  verb allows it, which a spoken "send message" does. Bare `send` is left out so one stray word can't send a draft,
  and `undo send` is added so a send is reversible by voice during Mail's undo delay. If you want a "say yes to send"
  step anyway, that is a pipeline change and a follow-up ticket.
- **Delete is `delete message` (⌘⌫), not bare `delete`.** Bare `delete` stays the global backspace, so editing a reply
  by voice works as everywhere else. Mail moves the message to Trash, and `undo` brings it back.
- **Read, flag, junk and the mailbox list use Mail's toggle chords.** "mark as read" on a read message marks it unread.
  The menu titles flip, and matching "Mark as Read" by title could hit "Mark All Messages as Read". The docs row says
  they toggle.
- **`next message` / `previous message` are the arrow keys**, since Mail has no menu item for them. They move the
  selection while the message list has focus; in a message body they scroll a line. Plain `up` / `down` stay global.
- **`go to inbox` is ⌘1** (the first Favorites mailbox, Inbox by default) and **`go to sent` is the menu item by
  title**, because the chord for Sent depends on the Favorites bar. The path is `Mailbox > Go to Favorite Mailbox > Sent`, so
  the Use This Mailbox For > Sent item can never match, and a path never falls back to agent-desktop (its menu search
  ignores the path). Without Sent in the bar it fails with "no menu item called Sent".
- **`search mail` only focuses Mail's search field** (⌥⌘F); the words to search for are then dictated or typed.
  "search mail for X" in one breath is left to the model.
- **`attach` opens the Attach Files sheet** and stops there, as the ticket says.
- **`close message` is ⌘W**; closing a draft shows Mail's own save sheet, which NoHands does not answer.
- **Added synonyms the ticket did not list** ("compose", "check mail", "trash message", "last message", "unflag").
  No bare `next`, `previous`, `delete`, `close` or `send` entries.
- **The pack lives in its own file** (`MailPack.swift`) and only appends `.mail` to `AppPacks.all`, so the sibling
  packs (NH-81, NH-82, NH-83) don't collide beyond that one line.
- **Chords come from Mail's menus as documented by Apple**; the menu file confirmed the titles but not the key
  equivalents (the nib can't be loaded outside Mail). A chord that fails the manual check becomes `.menuItem(<title>)`
  with the titles above, and the PR says which.

## Follow-ups (not in this ticket)

- "search mail for <words>" in one phrase.
- A spoken confirm for grammar phrases that send, if the user wants one.
