# NH-61: Confirm before irreversible actions

**Date:** 2026-11-15
**Status:** Draft
**Ticket:** [NH-61](https://github.com/noahstotland/nohands/issues/61)

## Goal

A hands-free task that is about to press Send, Delete, Place order or a similar button must not do it on a guess. When the user's request did not say that verb, the task stops before the step, shows `say yes to <verb>` on the prompt's row, and runs the step only if the user says yes within 30 seconds. Anything else, silence or "stop" ends the task without running the step.

## Today

Checked on `origin/main` (`048937a`).

- `ShortcutGuard.blocked` (`Sources/NoHandsCore/ShortcutGuard.swift`) blocks command-W, command-Q and `close_app` unless the goal has a close or quit word. `TabGuard` and `MenuBarGuard` block other slips. All three run in `TaskRunner.run` (`Sources/NoHandsMac/TaskRunner.swift`, the `else if let blocked = …` chain) on every step, including plan steps, and nothing looks at what a clicked element is called.
- A blocked step fails outright: there is no way to pause a task for a yes or no. NH-47 (`ask`, open) will add one for model questions.
- While a task runs, `VoicePipeline.busy` cancels the task on a stop phrase and holds any other utterance until the task ends.
- Grammar commands ("click send") run straight from the pipeline and never reach `TaskRunner`.

## Design

### 1. The matcher (`NoHandsCore`, new `IrreversibleGuard.swift`)

`IrreversibleGuard.held(_ actions: [Action], labels: [Int: UIElementInfo], goal: String) -> String?` returns the verb to confirm (for example `"send"`, `"place order"`), or nil when the step may run.

**Target name of each action** (actions with no name are not looked at):

| Action | Name checked |
|---|---|
| `click(.label(n))`, `click(.numbered(n))` | `labels[n].title` |
| `click(.element(named:))` | the name |
| `click_in(surface, name)` | the name |
| `menu_item(path)` | the whole path ("File > Send Again") |
| `set_value(target, _)` | the label's title or the name |
| `press_key` Return or Enter (any modifiers) | the title of the element in `labels` whose states include `focused` and whose role contains `button` (case-insensitive: `AXButton`, `button`, `AXMenuButton`) |

**Guarded verbs.** The name is split with `CommandGrammar.normalize` and matched on whole words, so "Sender", "Posts", "Sent" and "PayPal" do not match. The name side uses the imperative form only:

send, delete, remove, discard, pay, buy, purchase, checkout (also "check out"), confirm, submit, publish, post, unsubscribe, transfer, place order, empty trash.

**What the goal allows.** A verb is allowed when the goal (normalized the same way) has any of its word forms, as `ShortcutGuard` does: send, sends, sending, sent; delete, deletes, deleting, deleted; remove, removes, removing, removed; and so on for each verb ("pay, pays, paying, paid", "buy, buys, buying, bought"). "place order" is allowed by "order", "orders", "ordering" or "ordered", "empty trash" by "empty" or "emptying" together with "trash" or "bin", and "checkout" by "checkout" or "check out". On the name side multi-word verbs are matched as consecutive words. Each verb is allowed only by its own forms: "buy a lamp" allows a Buy button but still asks before Place order or Checkout.

The first held action of a step names the verb. A step is held or not as a whole.

Table test (`IrreversibleGuardTests`): one table of (actions, labels, goal, expected verb or nil) covering every action kind above, whole-word matching ("Sender", "Sent", "Posts" not held), goal word forms ("sending the email" allows Send), per-verb allowance (buy does not allow place order), multi-word verbs, the focused-button Return case (Return with no focused button, or a focused text field, is not held), and actions with no name (points, scrolls, typed text).

### 2. The answer (`NoHandsCore`)

`ConfirmAnswer.isYes(_ transcript: String) -> Bool`: true only for "yes", "confirm" or "do it", optionally with "please" before or after and with the attention word stripped. "yeah", "sure", "yes and also open Safari" and the empty string are no. Part of the same table test file.

### 3. Waiting for the answer (`TaskRunner`)

In the guard chain, after the existing guards pass and before `executeCancellable`, `TaskRunner` calls `IrreversibleGuard.held`. When it returns a verb:

1. `onStatus(.running("step n · say yes to <verb>"))`.
2. `await awaitAnswer(timeout: TaskRunner.answerTimeout)` (30 s): a single `CheckedContinuation<String?, Never>` like the capture wait, resumed by `answer(_:)`, by `cancel()` (nil) or by a timeout raced through the injected `sleep` (nil). An ID guards against a late timeout resuming a newer wait. This is the generic "pause the task for a spoken answer" that NH-47's `ask` can reuse; the yes check lives in the caller.
3. Yes: the step's actions run as usual and the task goes on.
4. Anything else, the timeout, or `cancel()`: nothing from the step runs and the task ends `.stopped`. The row shows `stopped: <verb> not confirmed` (no or timeout) or the usual stopped line (a stop phrase).

New public surface: `var isAwaitingAnswer: Bool` and `func answer(_ transcript: String)`.

A spoken "stop" keeps working: `VoicePipeline.busy` still checks stop phrases first and calls `runner.cancel()`, which resumes the wait with nil and the task ends `.stopped`.

### 4. Routing the answer (`VoicePipeline.busy`)

After the stop check, when `runner?.isAwaitingAnswer` is true, the utterance goes to `runner.answer(text)` instead of being held, its row shows `done` with the answer, and any held job stays held. The attention word is not required for an answer: it is a reply to the row the user is looking at, and anything that is not a yes only stops the task.

### 5. README

§ Multi-step tasks: one paragraph after the command-W and command-Q guard naming the guarded verbs, the 30 s wait, the yes words, that a no or silence stops the task, and that grammar commands ("click send") are the user's own words and are not asked about.

## Tests

- `IrreversibleGuardTests` (core): the matcher table and the yes table above.
- `TaskRunnerTests`: one table-driven test over a fake resolver whose step clicks a labelled "Send" button with goal "reply to Anna": answer "yes" runs the click and the task goes on; "no" runs nothing and ends `.stopped`; no answer (the injected sleep returns at once) runs nothing and ends `.stopped`; `cancel()` during the wait ends `.stopped`. Plus one row with goal "send the reply" where the click runs without waiting.
- No test needs the microphone, Accessibility or a model.

## Leaves out

- Typed text and dictation (ticket's Out of scope).
- Clicks at a picture point (vision fallback): they have no element name. The README already says vision clicks are guarded only by the prompt.
- Keyboard shortcuts that send (command-Return, command-shift-D in Mail): only Return on a focused button is checked, as the ticket says.
- `nohands-cli task` has no voice, so a held step there waits 30 s and stops. Scenario runs that click Send should name the verb in their goal.
- The model is not told about the guard; it never sees a held step.

## Calls I made

- Per-verb allowance is strict: "buy a lamp" still asks before Place order and Checkout, and "delete the draft" still asks before Remove. Money and data loss get the extra question.
- Only the three yes words the ticket names, plus "please" and the attention word. No "yeah", "sure" or "go ahead": a stray word from the room must not confirm a payment.
- Any non-stop utterance while waiting is the answer, even without the attention word, and with the attention word on stray speech therefore stops the task (the safe side).
- The element name side matches only the imperative verb ("Send", "Delete"), not other forms, so the Mail "Sent" mailbox or a "Posts" tab is not held; the goal side takes all forms.
- A yes covers that one step. A later step that hits another (or the same) guarded button asks again.
- The 30 s wait is a constant (`TaskRunner.answerTimeout`), not a config key.
- On no or timeout the task ends `stopped` (not `stuck`) with `stopped: <verb> not confirmed`, and the model is not asked again.
- `menu_item` checks every word of the whole path, so "Message > Send Again" is held; "Mailbox > Erase Deleted Items" is not, because "erase" is not on the list and "Deleted" is not the imperative.
- The wait is built in `TaskRunner` as a generic answer wait so NH-47's `ask` can share it.
