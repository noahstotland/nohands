# NH-61: Confirm before irreversible actions

**Date:** 2026-11-15
**Status:** Shipped
**Ticket:** [NH-61](https://github.com/noahstotland/nohands/issues/61)
**Shipped:** in PR #120, with differences: [as-built](../as-built/2026-11-15-nh-61-confirm-irreversible.md)

## Goal

A hands-free task about to press Send, Delete, Place order or a similar button must not do it on a guess. When the request did not say that verb, the task stops before the step, shows `say yes to <verb>` on the prompt's row, and runs the step only if the user says yes within 30 seconds. Anything else, silence or "stop" ends the task without running the step.

## Design

- **Matcher** (`IrreversibleGuard` in `NoHandsCore`) returns the verb to confirm for a step, or nil. The first held action holds the whole step.
- **Name checked:** the label title or element name for clicks, `click_in` and `set_value`; the whole path for `menu_item`; for Return or Enter, the focused button's title. Unnamed actions are never held.
- **Guarded verbs**, whole words, imperative form only ("Sender", "Sent", "Posts" do not match): send, delete, remove, discard, pay, buy, purchase, checkout, confirm, submit, publish, post, unsubscribe, transfer, place order, empty trash.
- **The goal allows a verb** by any of its word forms (send, sent, sending). "place order" is allowed by "order" forms, "empty trash" by "empty" with "trash" or "bin". Only a verb's own forms allow it: "buy a lamp" still asks before Place order.
- **Yes words** (`ConfirmAnswer.isYes`): "yes", "confirm" or "do it", with optional "please" and the attention word stripped. "yeah" and "sure" are no.
- **Waiting** (`TaskRunner`): after the other guards, a held step awaits an answer for `answerTimeout` (30 s). Yes runs the step. Anything else, a timeout or `cancel()` runs nothing and ends the task `.stopped` with `stopped: <verb> not confirmed`.
- **Routing** (`VoicePipeline.busy`): after the stop check, an utterance while the runner awaits goes to `answer(_:)`, without the attention word.
- Grammar commands ("click send") are the user's own words and are not asked about. README § Multi-step tasks says so.

## Tests

Table tests cover the matcher, the yes check and `TaskRunner`.

## Leaves out

- Typed text and dictation.
- Vision clicks at a point.
- Shortcuts that send (command-Return); only Return on a focused button is checked.
- `nohands-cli task` has no voice, so a held step waits 30 s and stops.

## Calls I made

- Only the three yes words plus "please": a stray word from the room must not confirm a payment.
- Any non-stop utterance while waiting is the answer, so stray speech stops the task.
- Name matching is imperative-only, so the "Sent" mailbox is not held.
- A yes covers one step. The 30 s wait is a constant, not a config key.
- No or timeout ends `stopped`, not `stuck`, and the model is not asked again.
