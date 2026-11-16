# NH-149: Spoken yes before irreversible fixed phrases: Design

**Date:** 2026-11-16  **Ticket:** [NH-149](https://github.com/noahstotland/nohands/issues/149)
**Status:** Proposed

## Intent

Mail's "send message" and "delete message", Messages' "delete conversation" and the global "empty trash" run the
moment the grammar hears them. One mishear in the middle of a sentence sends a half-written email. NH-61 put a spoken
"yes" in front of irreversible steps the model chose; fixed phrases have nothing. This ticket adds the same yes to
fixed phrases that are marked as needing it, in the built-in tables and in the pack file, and makes sure a pack (local
or from an NH-85 registry) cannot leave the mark off a phrase that sends or deletes.

## Goals, non-goals, anti-goals

Goals are the ticket's Scope and Acceptance.

Non-goals: guarding dictation or typed text; changing the NH-61 task confirm; finding irreversible key chords by what
they do in an app we don't know (see Leaves out); a "never ask" setting.

Anti-goals, which would make this a failure even if it works:

- Anything other than "yes", "confirm" or "do it" (with "please" before or after, and the attention word when one is
  set) runs a held phrase. That includes NoHands' own spoken "say yes to …" heard back.
- A spoken "stop" is merged into another utterance, fails to drop a held phrase, or fails to halt a running task.
- A pack author ships a phrase that names send, delete or another guarded verb without the confirm.
- A held phrase runs in a different app than the one it was heard in.
- An unmarked phrase gets slower or asks.

## What the code forces

- **The grammar returns bare actions.** `CommandGrammar.parse` gives `[Action]?` and forgets which table entry hit,
  so nobody downstream can tell "send message" from "next message". The mark has to come out of the grammar with the
  actions.
- **Every spoken route goes through `ModeMachine.routeCommand`.** `route` (spoken utterances, held jobs) and
  `routeStep` (macro steps) both call it, so a new `Routing` case there reaches both.
- **Only the task slot can wait for an answer.** While `activeTask` is set, `VoicePipeline.busy()` gets every
  utterance; a stop there cancels the task, drops the held job and releases the mouse. Outside a task the pipeline
  has no way to wait. A held phrase therefore waits in the task slot, like a rewrite or a macro does.
- **`ConfirmAnswer.isYes` and `FeedbackCue.confirm(verb:)` exist** (NH-61, NH-60) and are reused as they are.
- **Pack files are parsed in one place.** `PackFile.parse` is the only way a file pack (local `pack add`, registry
  `pack install` / `update`, the Browse window, launch-time load, `pack new` drafts) becomes an `AppPack`, so a rule
  there covers every pack that is not built in.

## Design

### The mark

- `AppPack` gains `confirms: Set<String>`: the phrase keys (normalized) that ask first. Built-in packs set it per
  group in the table; the global table gets `CommandGrammar.confirmed: Set<String>` holding "empty trash" (and "empty
  the trash" through the filler-stripped lookup).
- `PackSet` carries the mark through its per-app merge: the pack that wins a phrase also decides whether it asks.
- `CommandGrammar.match(_:frontmost:textFocused:) -> GrammarMatch?` returns `actions`, `confirm: String?` (the phrase
  key to read back, nil for unmarked) and `bundleID: String?` (set when the hit came from a pack). `parse` stays as
  `match(...)?.actions`, so every caller that only parses (CLI `parse`, `bench`, `EndpointReplay`, `isComplete`,
  `carriesSpokenText`, `PackSummary`, `PackDraft`, `Macros` name checks) is unchanged.
- `ModeMachine.routeCommand` returns a new `Routing.confirm(HeldPhrase)` when the match has a `confirm`;
  `HeldPhrase` holds `phrase`, `actions` and `bundleID`. A `.setMode` action is never marked, so the mode switch
  logic does not change.

### What asks first

Built-ins, marked by group (every phrase in the group asks):

| Where | Phrases |
|---|---|
| Mail | `send message` and the rest of its group, plus a new bare `send` (now safe behind the yes) |
| Mail | `delete message`, `trash message`, `move to trash` and the rest of its group |
| Messages | `delete conversation` and its group |
| Global | `empty trash`, `empty the trash` |

Not marked, on purpose: Mail `undo send`, Terminal `send control c` (interrupt), VS Code `remove breakpoint`. Slack
(NH-81, PR #141), Chrome (NH-74), Safari (NH-77), Finder (NH-78, `delete file`) and dark mode (NH-163) are not on main
yet; the built-in table test below fails until their send and delete phrases are marked, so whichever merges second
marks them.

### The pack file field

- A command object may carry `"confirm": true` or `"confirm": false` (optional; format stays 1). Any other value is
  rejected: `bad confirm (true or false)`.
- A command is **forced** to confirm when any of these holds:
  1. A phrase names a guarded verb: its words contain a verb name from `IrreversibleGuard` (send, delete, remove,
     discard, pay, buy, purchase, checkout, confirm, submit, publish, post, unsubscribe, transfer, place order, empty
     trash), whole words, and the phrase does not start with "undo".
  2. Its actions equal a marked built-in command's actions for a bundle ID both packs cover (so "zap" bound to
     command-shift-D in Mail asks, like "send message").
  3. Its actions equal another forced command's actions in the same pack.
- A forced command with `"confirm": false` is rejected: `confirm false on an irreversible command (it names send,
  delete or another guarded verb)`. A forced command with no field is stored as asking, so packs already installed
  stay valid and gain the yes. An author may mark any other command `true`.
- Today's rejections stay: a menu item the phrase does not name is still rejected by `IrreversibleGuard.held`, so a
  phrase cannot reach "Delete Conversation…" without naming delete (and then rule 1 forces the confirm).
- `PackFile.encode` writes `"confirm": true` on marked commands. `PackSummary.commandLines` adds ` (asks first)`, so
  `pack add`, `pack install`, `pack update` and the Browse alert show it before the user says yes. `PackDiff` adds
  `phrase "x" now asks first` or `no longer asks first`.
- `pack new` (NH-98) drafts already skip irreversible menu items; a draft phrase the rules force is written with
  `"confirm": true`.

### Code paths that run grammar or pack actions

| Path | Goes through the confirm |
|---|---|
| `VoicePipeline.process` → `.execute` (a spoken command, no task running) | Yes: `.confirm` instead |
| `busy()` → `heldJob`, run by `process(held: true)` after the task | Yes: it routes like any utterance and becomes the next task-slot entry |
| `runMacro` → `routeStep` (NH-57 macro steps) | Yes: the macro waits at that step |
| `answersPick` → `openPicked` (NH-58 file list) | No: picks a file, not a pack phrase |
| Dictation mode (`ModeMachine.route` `.dictation`) | No: packs are not looked up; dictation is out of scope |
| `TaskRunner` model steps, route memory replay, follow-ups (NH-48) | No change: NH-61's `IrreversibleGuard` already guards them |
| `nohands-cli run <phrase>` | Refuses a marked phrase: `asks first: not run from the CLI`. Typed, not heard, but the CLI should not differ silently |
| `nohands-cli parse`, `bench`, `EndpointReplay` | Parse only, never run; `parse` adds `(asks first)` |

### Holding a phrase

`process` returns a `PendingTask` with `confirm: HeldPhrase` (after the same `canExecute` check as `.execute`), and
`startTask` runs it in the task slot:

1. The row shows `.running("say yes to <phrase>")` (`say yes to send message`), and `say(.confirm(verb: phrase))`
   reads "Say yes to send message." when spoken feedback is `all` (NH-60 levels unchanged: confirms are spoken only
   at `all`).
2. It waits up to 30 s (`ConfirmAnswer.timeout`, which `TaskRunner.answerTimeout` then uses too) for the next
   utterance. `busy()` gets a new branch, after the stop branch: while a held phrase waits, the utterance is its
   answer.
3. The answer:
   - **Yes** (`ConfirmAnswer.isYes(text, attention:)`): exactly "yes", "confirm" or "do it", "please" allowed before
     or after, attention word required when set. If the phrase came from a pack and its app is no longer frontmost,
     the row fails `<App> is no longer in front: say it again` and nothing runs. Otherwise it runs with
     `executor.execute(actions, files: .spoken)`, is logged as a grammar command, and the row shows done or failed
     like an inline command. The answer row shows done.
   - **Anything else** (including "yeah", "yes send it", unaddressed speech with the attention word on, a failed
     self-echo): the phrase is dropped, `.dropped("not confirmed")`, and the reply is not run as a command. This is
     NH-61's rule ("any other reply only stops the task").
   - **30 s of nothing**: `.dropped("no yes in 30 s")`.
   - **"stop"**: the existing stop branch in `busy()` runs first: the task is cancelled, the row shows stopped, any
     held mouse button is released. Stop is never gated by the attention word and never merged (MergeBuffer is not
     touched).
4. Each ending is one command-log entry: done or failed on a yes, `ignored("not confirmed")` or
   `ignored("no yes in 30 s")` otherwise, and `stopped` on a stop.

### With the other features

- **Macros (NH-57).** A held step shows `step 2 of 3 · say yes to send message` and waits the same way. Yes runs it
  and the macro goes on; anything else or a timeout ends the macro, `step 2 of 3 · not confirmed`; a stop ends it as
  stopped. Saying the macro's name is not the yes: a macro of "send message" asks every time.
- **Spoken feedback (NH-60).** The ask is the existing `FeedbackCue.confirm` (at `all`). The finish line is spoken
  like any task-slot row (at `outcomes` and up), since the held phrase runs in the slot. `ownVoiceHeard` runs before
  `busy()`, so NoHands' own "Say yes to send message." heard back is dropped as echo; if the echo check misses it,
  the words are not a yes and the phrase is dropped, never run.
- **Follow-ups (NH-48).** A held phrase is a grammar command: it does not set or clear `lastTask`, and the yes reply
  is never routed, so it is never a follow-up. A follow-up the model runs ("send it") is guarded by NH-61, unchanged.
- **Registry packs (NH-85).** Install and update parse with `PackFile.parse`, so the forced rules apply; a registry
  pack cannot turn the confirm off on a phrase that sends or deletes. The summary and the diff show `(asks first)`
  before the user agrees.
- **Merge window.** "send message" is a complete phrase, so `isComplete` closes the window at once and a quick "yes"
  is its own utterance. A merged "send message yes" is not a phrase and goes to the model as today.
- **"empty trash" (NH-52).** It asks for the spoken yes, and then Finder's own warning still shows (answer `enter`
  or `escape`). The Finder-warning-off refusal stays.

## Tests

Core (one table-driven test per rule):

- Grammar: a marked phrase routes to `.confirm` with its phrase and bundle ID; an unmarked one routes to `.execute`;
  `routeStep` behaves the same.
- Built-in invariant: every built-in pack phrase the forced rules catch is marked, minus the listed exemptions
  (`undo send`, `send control c`, `remove breakpoint`).
- Pack file: forced by phrase words, by built-in actions, by same-pack actions; `"confirm": false` on a forced command
  rejected; a non-boolean rejected; `true` on any command kept; missing field on a forced command stored as asking;
  `encode` round-trips the field.
- `PackSummary` and `PackDiff` show the mark.

Pipeline (`VoicePipelineTests`, with the existing fakes): a held phrase runs on "yes", "confirm", "do it" and
"please yes"; is dropped and not run on "yeah", another command, an unaddressed reply and a timeout (test timeout
shortened); is dropped by "stop" with the task-slot stop path; a pack phrase is not run when the frontmost app
changed; a macro step asks and ends on a no.

Manual (listed in the PR): Mail send and delete with a real draft; empty trash then Finder's dialog; spoken feedback
at `all` reads the ask and the echo is ignored.

## Docs

- `docs/voice-commands.md`: an "asks first" note on each marked row, the new Mail `send` row, and a short paragraph
  on what confirms (yes, confirm, do it), the 30 s, and stop.
- `docs/app-packs.md`: the `confirm` field, the forced rules and the `(asks first)` line in the summary.

## Calls I made

- **Anything but a yes drops the phrase and is not run.** Matches NH-61. The other option, running the new words as
  a command, would let "next message" through but also run a stray mishear right after a mishear.
- **The forced rule goes by the phrase's words and by matching built-in actions, not by what a key chord does.**
  A pack can still bind a nonsense phrase to a chord that sends in an app we have no built-in for; nothing can know
  that without the app. Listed in Leaves out.
- **A forced command with no field asks; only an explicit `false` is rejected.** Keeps installed packs loading.
- **The read-back is the phrase, not a verb** ("say yes to send message", "say yes to empty trash"), so it needs no
  verb guessing and says exactly what was heard.
- **"empty trash" and "delete conversation" ask even though Finder and Messages ask too.** Consistent with the rule
  that every phrase naming a guarded verb asks; costs one extra "yes".
- **Mail gets a bare `send`**, as the ticket allows once the confirm exists. Messages keeps no send phrase (Return
  sends there); Slack's are for its own PR.
- **The held phrase runs only in the app it was heard in.** If the frontmost app changed during the wait, it fails
  and asks to say it again.
- **Spoken feedback reads the ask only at `all`**, as NH-60 decided for task confirms; at `outcomes` the user sees
  the ask but does not hear it.
- **`nohands-cli run` refuses marked phrases** rather than adding a `--yes` flag.
- **Exempt built-ins:** `undo send`, `send control c`, `remove breakpoint`; and a phrase starting with "undo" is
  never forced.

## Leaves out

- Irreversible chords behind phrases that name no guarded verb, in apps with no built-in pack.
- Guarding dictation, typed text, or the file pick list.
- The NH-61 task confirm and its wording.
- Marking the phrases of NH-74, NH-77, NH-78, NH-81 and NH-163, which are not on main; the built-in test makes the
  later PR mark them.
