# NH-81: Slack voice commands: Design

**Date:** 2026-11-15  **Ticket:** [NH-81](https://github.com/noahstotland/nohands/issues/81)
**Status:** Shipped
**Shipped:** in PR #141, with differences: [as-built](../as-built/2026-11-15-nh-81-slack-commands.md)

## Intent

Getting around Slack is all keyboard chords, and none of them can be said today. This ticket adds the second app pack
on the NH-76 mechanism: Slack (`com.tinyspeck.slackmacgap`). It covers jump to a conversation, new message, DMs,
threads, activity, Later, search, previous and next channel, previous and next unread, mark as read, upload,
sidebar, huddle, and closing a panel or the window. It also adds one small extension to packs, a **typing lead**, so
"jump to design team" opens the quick switcher and types the name in one utterance.

## Goals, non-goals, anti-goals

Goals are the ticket's Scope and Acceptance, plus "jump to <name>" in one utterance and a decision on "send" (below).

Non-goals (the ticket's Out of scope): writing or rewriting message text (#54, #55), reading channels or messages
(#50, #60), deleting or editing a message, Slack in a browser (#74, #77).

Anti-goals, which would make this a failure even if it works:

- A Slack phrase changes what a phrase does in another app, or with no app in front.
- Any Slack phrase is "stop" or contains it, or a stop phrase reaches the pack.
- Bare "mute" or "unmute" stops controlling the Mac's speakers while Slack is in front.
- "jump to <name>" presses Return or sends anything on its own.
- A typing lead catches a phrase another Slack entry or a global rule owns ("jump to" is the only lead).

## What the code forces

- **Packs** (`NoHandsCore/AppPack.swift`): `AppPack(name:bundleIDs:phrases:)`, exact normalized phrases to
  `[Action]`, registered in `AppPacks.all` (now `[.terminal]`). `CommandGrammar.parse(_:frontmost:)` tries the pack
  on the whole phrase, then the global table, then the pack after dropping one "open" / "go to" and one article.
  Stop phrases never reach a pack. `shippedPacksAreWellFormed` checks every shipped pack.
- **Packs are exact phrases only.** "jump to general" can't be an entry, and without one it goes to the model.
  "go to general" is worse: the global `go to <words>` rule sends it to a browser's address bar. One-utterance jumps
  need a lead rule, the extension below.
- **Global phrases Slack already shares:** `go back` (⌘[) and `go forward` (⌘]) are Slack's history chords, `find`
  (⌘F) is Slack's "search in the current conversation", `escape` is Slack's "mark current conversation as read",
  `full screen` (⌃⌘F) is Slack's full screen, `enter` presses Return (which sends in the composer today). The pack
  doesn't repeat them.
- **`close window` is global ⇧⌘W**, but Slack's window closes with ⌘W. The pack overrides it.
- **`mute` and `unmute` are the system volume** (NH-51). The huddle's mute is its own phrase.
- **#61 (shipped)** stops a model-planned step before it presses Send and the like when the goal didn't name the verb.
  Its spec says grammar commands "are the user's own words and are not asked about". It doesn't guard chords at all.
- **Slack isn't installed on this machine**, so the menus can't be read here as NH-84 did. The chords come from
  Slack's help page "Slack keyboard shortcuts" (slack.com/help/articles/201374536, read 2026-11-15, Mac column).
  Three chords aren't on that page and come from Slack's older menus. They're marked *unverified* below, and the
  manual check settles them.

## Approaches

1. **One chord pack plus a typing lead for "jump to" (chosen).** The pack covers every fixed phrase like Terminal's.
   One small `AppPack` field handles the single phrase that carries a name.
2. **Chord pack only; "jump to" opens the switcher, then "type general" and "enter".** No mechanism change, but
   the most common Slack action takes three utterances, and "go to general" still lands in the browser.
3. **Send "jump to <name>" to the model.** Works with no code, but it's slow, it needs the network or Ollama, and
   it fails with "LLM off".

## How it works

### Typing leads (`NoHandsCore/AppPack.swift`)

`AppPack` gains `typingLeads: [String: [Action]]` (default empty, so Terminal is unchanged). A key is a normalized
lead phrase. When the utterance starts with that lead and Slack's pack is in front, the grammar returns the lead's
actions, then `.typeText(<rest>)` with the rest in the speaker's raw words (case and dots kept through `rawWords`).
Before the name is typed, one leading article ("the", "a", "an") is dropped, and so is one trailing "channel".

- **Order in `parse`:** after both pack exact lookups and before `menu <words>`. So an exact pack phrase that starts
  with the lead still wins, and the global table still wins on a whole phrase.
- **Empty rest** ("jump to", "jump to the"): the lead's actions only. The switcher opens with nothing typed.
- **Stop:** as with phrases, a stop utterance never reaches a typing lead.
- `shippedPacksAreWellFormed` also checks the leads: normalized, not empty, no stop word, not an exact phrase key.

Slack's only lead is `jump to` → `[⌘K, wait(ms: 300)]`. "jump to design team" gives
`[⌘K, wait 300, typeText("design team")]`. The switcher stays open on its best match: the user says `enter` to go
there, or `down` first for another match.

### `NoHandsCore/SlackPack.swift`

`AppPack.slack`, bundle ID `com.tinyspeck.slackmacgap`, and `AppPacks.all = [.terminal, .slack]`.

| Phrases | Action | Slack's name |
|---|---|---|
| `jump to <name>` (lead), `jump to`, `quick switcher`, `switch conversation` | ⌘K (lead: then type) | Jump to a conversation |
| `new message`, `compose`, `compose message`, `new direct message` | ⌘N | Compose a new message |
| `direct messages`, `dms`, `browse dms`, `browse direct messages` | ⇧⌘K | Browse DMs |
| `threads`, `show threads` | ⇧⌘T | Open the Threads view |
| `activity`, `mentions`, `mentions and reactions`, `show activity` | ⇧⌘M | Open the Activity view |
| `later`, `saved items`, `saved messages`, `show later` | ⇧⌘S *unverified* | Later |
| `search`, `search slack` | ⌘G | Start a search |
| `search this channel`, `search in channel`, `search this conversation` | ⌘F | Search in the current conversation |
| `previous channel`, `channel up` | ⌥↑ | Jump to previous channel or DM |
| `next channel`, `channel down` | ⌥↓ | Jump to next channel or DM |
| `previous unread`, `previous unread channel` | ⌥⇧↑ | Jump to previous unread channel or DM |
| `next unread`, `next unread channel` | ⌥⇧↓ | Jump to next unread channel or DM |
| `all unreads`, `unreads`, `show unreads` | ⇧⌘A | Open the All unreads view |
| `mark all as read`, `mark all read`, `mark everything read` | ⇧Esc | Mark all messages as read |
| `mark as read`, `mark channel read`, `mark this channel read` | Esc | Mark current conversation as read |
| `upload a file`, `upload file`, `attach a file`, `attach file` | ⌘O (fallback ⌘U) | Upload a file |
| `toggle sidebar`, `show sidebar`, `hide sidebar` | ⇧⌘D *unverified* | Show or hide the sidebar |
| `huddle`, `start huddle`, `join huddle`, `leave huddle`, `end huddle` | ⇧⌘H | Start, join, leave or end a huddle |
| `mute huddle`, `unmute huddle`, `mute myself`, `unmute myself` | ⇧⌘Space | Toggle mute on a huddle |
| `close panel`, `close pane`, `close thread`, `hide right sidebar` | ⌘. | Hide the right sidebar |
| `close window`, `close slack window` | ⌘W | Close window |
| `browse channels`, `channel browser` | ⇧⌘L | Browse channels |
| `people`, `show people`, `directory` | ⇧⌘E | Open the People view |
| `home view`, `slack home` | ⌃1 *unverified on Mac column wording* | Open the Home view |
| `preferences`, `slack preferences`, `settings` | ⌘, | Open your preferences |
| `send`, `send message`, `send it` | Return | (the composer's send) |

The NH-76 lead stripping still applies to exact phrases: "open the threads", "go to activity" and "open a new
message" reach their entries. Articles in the keys themselves ("upload a file") are listed as their own entries,
since the stripping drops only a leading article.

Each *unverified* chord falls back during the manual check to `.menuItem(<title>)` with the title Slack shows. If
neither works, the phrase comes out of the pack and the PR lists it.

### Send

Slack's composer sends on Return, and the global `enter` already presses it. So voice can send a Slack message
today, and adding `send` grants nothing new. #61's guard is for a step the user didn't ask for. Its spec says grammar
commands are the user's own words and are not asked about. "send" is the user naming the verb themselves, which is
exactly what #61 lets through without asking. So the pack has `send`, `send message` and `send it` as Return.
Return outside the composer does nothing that can't be undone.

### Docs

`docs/voice-commands.md` § Per-app commands: one row per group of related phrases (App `Slack`; not every synonym is listed), plus a sentence. The sentence
says the global `go back`, `go forward`, `find`, `escape`, `full screen` and `enter` also work in Slack, bare
`mute` stays the Mac's speakers, `jump to <name>` leaves the switcher open for `enter`, and any `open <phrase>` that is a Slack phrase (`open settings`, `open people`) means Slack's own view. The NH-76 sentence
gains "or start with a lead some apps define (Slack's `jump to <name>`)".

## Tests

Core, table-driven (`SlackPackTests.swift`, no permissions), on the shipped `CommandGrammar()`:

- **Slack in front:** a sample phrase from each row resolves to its chord, `close window` to ⌘W and `send` to
  Return. The listed globals (`go back`, `find`, `escape`, `mute`) keep their global actions.
- **Another app or none in front:** each sampled pack-only phrase doesn't resolve to its Slack action with
  `com.apple.Safari` or no app in front, and `close window` stays ⇧⌘W.
- **Typing lead (one table):** the rows are "jump to general", "Jump to the Design Team channel" (types
  "Design Team"), "jump to" (⌘K only), and "jump to general" with Safari in front (not ⌘K). "jump to" in a
  Terminal-only grammar isn't a lead, and "stop" with Slack in front matches no app in front.
- `shippedPacksAreWellFormed` gains the lead checks and runs over both packs.

Manual on macOS 14 with the current Slack desktop app (listed in the PR, with every phrase that fails and the
fallback used): each phrase through `nohands-cli parse --app com.tinyspeck.slackmacgap "<phrase>"` and by voice;
"jump to <a channel>" then "enter"; start a huddle, then "mute huddle" and "leave huddle"; the three *unverified*
chords and upload ⌘O vs ⌘U.

## Calls I made

- **"send" is in the pack (Return)**, though the ticket held it for #61. #61 shipped and doesn't guard grammar
  commands the user says, and `enter` already sends in Slack. Drop the three `send` keys if you want send kept out.
- **Packs gain typing leads**, a mechanism change the ticket didn't ask for, so "jump to general" works in one
  utterance with LLM off. The only lead is Slack's `jump to`.
- **"jump to <name>" doesn't press Return.** It types the name and leaves the quick switcher open on its best
  match, so a misheard name never opens the wrong conversation. The user says `enter`. Pressing Return straight
  away would save an utterance but act on whatever ranks first.
- **"go to <name>" isn't a jump** in Slack. It keeps the global meaning (the browser), so "go to github.com" still
  works from Slack. Only "jump to" types into the switcher.
- **A 300 ms wait after ⌘K** before typing, so the switcher is open when the name arrives (the global `go to` types
  straight after ⌘L, but Slack's switcher animates in). The manual check tunes it.
- **Upload is ⌘O**, as Slack's current help page lists it (older Slack used ⌘U). The manual check settles it.
- **Later, sidebar and Home chords are unverified** (⇧⌘S, ⇧⌘D, ⌃1). Slack isn't installed on this machine, and the
  help page doesn't list the first two. Each falls back to a menu item or comes out, as the PR says.
- **"close panel" is ⌘. (Hide the right sidebar)**, the panel threads and profiles open in. "close window" overrides
  the global ⇧⌘W with Slack's ⌘W.
- **The huddle mute has its own phrases** (`mute huddle`, `mute myself`). Bare `mute` stays the Mac's speakers, so
  NH-51's phrase doesn't change meaning in one app.
- **The huddle phrases all press the one toggle (⇧⌘H)**, so "start huddle" while in one leaves it. Slack has a single
  chord for start, join, leave and end, and "leave huddle" is the spoken release the product rules ask for.
- **Added phrases the ticket didn't list**: all unreads, browse channels, people, preferences, home view, search
  this channel, huddle mute, and synonyms ("dms", "compose", "channel up").
- **Globals that already match Slack aren't repeated** (`go back`, `go forward`, `find`, `escape`, `full screen`),
  as NH-84 did.

## Follow-ups (not in this ticket)

- "jump to <name> and send <text>" style chains, after the text tickets (#54, #55).
- Slack in a browser (#74, #77).
