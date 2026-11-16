# NH-82: Messages voice commands: Design

**Date:** 2026-11-15  **Ticket:** [NH-82](https://github.com/noahstotland/nohands/issues/82)
**Status:** Proposed

## Intent

Messages has a small set of shortcuts that are easy to say, but none of them has a phrase today. This ticket adds the
second app pack on the NH-76 mechanism, Messages (`com.apple.MobileSMS`). It covers starting a message, moving between
conversations, search, details, read and unread, the emoji and tapback pickers, close window and delete conversation.
The work is a table file, one line in the pack registry, a test and rows in `docs/voice-commands.md`.

## Goals, non-goals, anti-goals

Goals are the ticket's Scope and Acceptance, with the changes listed under Calls I made: pin and unpin are left out,
"delete conversation" is added and "send" is still left out.

Non-goals (the ticket's Out of scope): writing or rewriting message text (#54, #55), reading messages aloud or to the
model (#50, #60), picking a contact by name beyond Messages' own search, and sending a message.

Anti-goals. Any of these makes the ticket a failure even if the phrases work:

- A Messages phrase changes what a phrase does in another app, or with no app in front.
- A phrase reads or sends message text, or puts it in a log.
- A phrase sends a message, or answers Messages' own delete confirm.
- Any phrase is "stop" or contains "stop", or a stop phrase reaches the pack.

## What the code forces

- **The pack mechanism exists** (`NoHandsCore/AppPack.swift`, NH-76; first used by Terminal in NH-84). `AppPacks.all`
  is `[.terminal]`. A pack maps normalized phrases to chords or `.menuItem(title)`. A pack phrase that is also a global
  phrase wins. Before the pack lookup the grammar drops a leading "open", "go to" and an article. A stop phrase never
  reaches a pack. `shippedPacksAreWellFormed` already checks every shipped pack.
- **Messages' menus on macOS 14.5**, read from the running app's menu bar through Accessibility on this machine:

  | Menu > item | Shortcut |
  |---|---|
  | File > New Message | ⌘N |
  | File > Close Window | ⌘W (Close All is ⌥⌘W; ⇧⌘W does nothing) |
  | Edit > Find… | ⌘F (puts focus in the conversation search field) |
  | Edit > Tapback Message… | ⌘T |
  | Edit > Emoji & Symbols | the globe key (⌃⌘Space also opens the picker in any text field) |
  | Conversation > Show Details | ⌘I |
  | Conversation > Mark as Unread | ⇧⌘U |
  | Conversation > Delete Conversation… | none; the "…" means Messages asks before it deletes |
  | Window > Go to Next Conversation / Go to Previous Conversation | ⌃Tab / ⌃⇧Tab |

  **Pin and unpin are not in any menu.** They appear only in the conversation's right-click menu and have no shortcut.
  The Conversation menu shows "Mark as Unread" for a conversation that has been read. "Mark as Read" is in Messages'
  strings and should replace it for an unread conversation; the manual check confirms this.
- **"Send" and "delete" vs #61.** #61 (shipped, PR #120) holds a step only inside a hands-free task. Grammar commands
  count as the user's own words and are never asked about. A "send" phrase in this pack would therefore send with no
  confirm, the same as the global `enter` already does in Messages today.
- **Globals already cover two phrases.** `find` (⌘F) and `next tab` / `previous tab` (⌃Tab / ⌃⇧Tab) do the right
  thing in Messages. `search for <name>` already gives `.search(<name>)`, which types into the front app's own search
  box. The global `close window` is ⇧⌘W, which does nothing in Messages, so the pack has to override it.

## Approaches

1. **One pack in its own Core file: chords where Messages has one, menu items for the rest (chosen).** It matches
   the Terminal pack and works as a table test. Read and unread are menu items because the one shortcut, ⇧⌘U, may
   toggle: "mark as unread" on a conversation that is already unread could mark it read.
2. **Menu items for everything.** Survives a remapped shortcut, but every phrase then pays for the Accessibility menu
   walk. Kept as the fallback for any chord the manual check finds broken.
3. **Pin by right-clicking the selected conversation row.** The grammar has no way to find that row without the model
   or a screen walk. Rejected for this ticket. A pin request goes to the model, which can do it as a task step.

## How it works

### `NoHandsCore/MessagesPack.swift`

```swift
extension AppPack {
    static let messages = AppPack(name: "Messages", bundleIDs: ["com.apple.MobileSMS"], phrases: [ ... ])
}
```

and `AppPacks.all = [.terminal, .messages]`. Phrases (normalized keys):

| Phrases | Action |
|---|---|
| `new message`, `new conversation`, `new chat`, `compose`, `compose message`, `start new message`, `start a new message` | ⌘N |
| `next conversation`, `next chat`, `next message thread` | ⌃Tab |
| `previous conversation`, `previous chat`, `last conversation` | ⌃⇧Tab |
| `search`, `search messages`, `search conversations`, `find conversation` | ⌘F |
| `show details`, `details`, `conversation details`, `show info`, `info` | ⌘I |
| `mark as unread`, `mark unread`, `mark conversation as unread` | `.menuItem("Mark as Unread")` |
| `mark as read`, `mark read`, `mark conversation as read` | `.menuItem("Mark as Read")` |
| `emoji`, `add emoji`, `emoji picker`, `show emoji` | ⌃⌘Space |
| `tapback`, `add tapback`, `react`, `tapback message` | ⌘T |
| `close window`, `close conversation window` | ⌘W |
| `delete conversation`, `delete this conversation`, `delete the conversation` | `.menuItem("Delete Conversation…")` |

"delete conversation" only opens Messages' own confirm. Nothing in the pack presses Delete in it. The user says
"click delete", "enter" or "escape". A deleted conversation sits in View > Recently Deleted for 30 days.

The lead stripping from NH-76 sends "open a new message", "go to the next conversation" and "the details" to these
entries.

### Docs

Rows in the Per-app commands table in `docs/voice-commands.md` (App `Messages`), one row per group above. Below them,
a note:

- `find`, `next tab`, `previous tab` and `search for <name>` also work in Messages.
- `delete conversation` asks first, and NoHands does not answer that question for you.
- Sending stays `enter` (or "press return"), so there is no "send" phrase.
- Pin and unpin are not phrases yet. Say them as a request and the model handles them.

## Tests

Core, table-driven (`MessagesPackTests.swift`, Core only, no permissions), the same shape as `TerminalPackTests`:

- **Messages in front:** one sample phrase from each group in the table, plus the globals the ticket relies on (`find`,
  `next tab`, `previous tab`, `search for mom` → `.search("mom")`), resolves to its action through the shipped
  `CommandGrammar()`, so the registry line is tested too.
- **Another app or no app in front:** each sampled pack-only phrase does not resolve to its Messages action with
  `com.apple.Safari` or with no app in front. "close window" with Safari in front is still ⇧⌘W.
- **No stop and no send:** no Messages phrase is a stop phrase, or has "stop" or "send" as a word. "stop", "cancel"
  and "cancel that" with Messages in front give what they give with no app in front.

Manual on macOS 14, listed in the PR along with any phrase that fails: each phrase with Messages in front, first as a
dry run with `nohands-cli parse --app com.apple.MobileSMS "<phrase>"`, then by voice in the app. Also: "mark as read"
on an unread conversation, and "delete conversation" showing Messages' confirm with nothing answering it.

## Calls I made

- **Pin and unpin are left out of the pack.** Messages on macOS 14.5 has them only in the right-click menu, with no
  menu bar item and no shortcut. The grammar can't reach them without the model, so the PR lists them as phrases that
  could not be made to work, and they still work as a model request.
- **"delete conversation" is in the pack; "send" is not.** #61 is closed, but its confirm step covers only task steps,
  never grammar phrases. Delete is safe without it because Messages asks first ("Delete Conversation…") and keeps the
  conversation in Recently Deleted for 30 days. Send is final and nothing would confirm it, and `enter` already sends.
  A spoken "send" confirm for grammar phrases would be its own ticket.
- **Read and unread are menu items, not ⇧⌘U**, so "mark as unread" can never mark a conversation read. If "Mark as Read"
  turns out not to exist, the PR says so and the phrase is dropped.
- **Emoji is ⌃⌘Space, not the globe key.** NoHands can't synthesize the globe key reliably, and ⌃⌘Space opens the
  same picker. The fallback is `.menuItem("Emoji & Symbols")`.
- **"close window" in Messages is ⌘W**, overriding the global ⇧⌘W, which does nothing there. Other apps are unchanged.
- **Bare "search" is ⌘F (the conversation search field).** "search for <name>" keeps the global behavior, which types
  the name into that field. No new name matching.
- **Added synonyms the ticket did not list:** "new chat", "compose", "next chat", "last conversation", "info",
  "react". There is no bare "next" or "previous", so those keep their current meaning.
- **"tapback" and "add emoji" only open the pickers**, as the ticket says. Picking a reaction or an emoji by voice is
  left to the existing click, label and grid commands.
- **No phrases for the extra items Messages has** (reply ⌘R, edit last message ⌘E, text size, the View filters). They
  stay outside this ticket's scope.
- **The pack lives in its own file** (`MessagesPack.swift`), so NH-79 (Mail) only conflicts on the `AppPacks.all` line.

## Follow-ups (not in this ticket)

- A spoken confirm for irreversible grammar phrases, then a Messages "send" phrase.
- Pin and unpin through the conversation's right-click menu.
