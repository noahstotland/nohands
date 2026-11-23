# NH-154: Close the gaps left in the confirm for irreversible task steps

**Date:** 2026-11-23
**Status:** Shipped
**Ticket:** [NH-154](https://github.com/noahstotland/nohands/issues/154)
**Shipped:** in PR #184, with differences: [as-built](../as-built/2026-11-23-nh-154-irreversible-confirm-gaps.md)
**Builds on:** [NH-61 spec](2026-11-15-nh-61-confirm-irreversible-design.md), [as-built](../as-built/2026-11-15-nh-61-confirm-irreversible.md)

## Goal

The NH-61 guard (`IrreversibleGuard.held`) decides from the screen the model saw, and only from the name the step carries. This ticket closes five gaps the NH-61 review left open:

1. The screen can change during the 30 s wait for a yes, and a button drawn after the observation (or past the element cap) is never seen.
2. Routes with no name in the step: a cursor move then a plain press, focus then Space, and a drag onto a button.
3. A grid cell `n` is checked against label `n`'s name.
4. A comma after a negation always ends it, so "don't delete, send or archive anything" allows Send.
5. Return (and now Space) on a focused button is held only where the element list carries the `focused` state (agent-desktop).

## Design

Two checks, one before the step (asks for a yes, as today) and one at press time (refuses the press).

### 1. Before the step: `IrreversibleGuard.held` sees every route

`held(_:labels:goal:overlay:cursor:)` gains two parameters, both with defaults that keep today's callers (`PackFile`, `PackDraft`) unchanged: `overlay: OverlayState = .none` and `cursor: CGPoint? = nil`. It walks the step's actions in order, keeping a simulated cursor position and focused element, and finds the element each press lands on:

| Action | Element checked |
|---|---|
| `click(.label n)` | label `n` (today) |
| `click(.numbered n)` | grid shown: the observed element under cell `n`'s centre (`GridModel.center(of:)`); labels overlay shown: that overlay's label `n`; nothing shown: label `n` (today, safe side) |
| `click(.cursor)`, `releaseMouse` | the observed element under the simulated cursor |
| `click(.point p)` | the observed element under `p` |
| `moveCursor(t)` | named or label targets: held as today (first half of a press). Every target also moves the simulated cursor (`point`, `relative` from the cursor, `numbered` as above, `screenCenter` is unknown) |
| `focusElement(t)` | held as today; also sets the simulated focused element |
| `drag(from:to:)` | the element under (or named by) `to`: a drag released on a button presses it |
| `pressKey` Return (any modifiers, today) or Space (no modifiers, new) | the simulated focused element if the step focused one, else the observed element with the `focused` state that is a button |

"The element under a point" is a new pure function in `NoHandsCore`: the smallest observed element whose frame contains the point; none when no frame does or the point is unknown. The cursor starts at `cursor` (the real pointer, read by `TaskRunner` from the executor's input), so a move in one step and a click in the next is covered.

### 2. Press time: the executor checks the element it is about to press

`ActionExecutor` gets `pressGuard: PressGuard?` (a `NoHandsCore` struct: the goal and the verbs already confirmed for this step). `TaskRunner` sets it for each model step and clears it after; grammar commands, macros' fixed steps and packs never set it, so they behave as today.

Just before a mouse press (click, mouse-up, the release of a drag) or a Return or Space, the executor reads the title of what will be pressed from the live screen:

- a click or drag end at a point: a new `ElementProviding.elementTitle(at:)` (Accessibility hit test at that point, climbing to the nearest ancestor with a title, at most a few levels);
- a press by agent-desktop ref: the title the harness resolved (`find`'s name) or the snapshot's title for a label;
- Return or Space: a new `ElementProviding.focusedElementTitle()`.

`IrreversibleGuard.unconfirmed(title:guard:)` returns the guarded verb in that title the goal does not allow and the user did not confirm, else nil. On a verb, nothing is pressed and the step fails with `<verb> not confirmed, look again`; the model's next step, on a fresh observation, names the button and is held for a yes by check 1. An unknown title (hit test failed, no focused element) lets the press go ahead.

Both new `ElementProviding` methods get default implementations returning nil, so test fakes and other conformers compile unchanged.

### 3. After the yes: read the screen again

After a yes, `TaskRunner` observes again before running the step (always: comparing needs the read anyway). The step runs on the fresh labels when every label number it uses still has the same title and role, and `held` on the fresh observation asks only about verbs the user just confirmed. Otherwise nothing runs and the step is recorded with `ActionExecutor.elementChanged` ("element changed, look again"), so the model looks again; a guarded button on the new screen is asked about again. The press-time check (2) then runs with the confirmed verbs, so a button that appears between the re-read and the press is still caught.

### 4. Negation across a comma

`goalVerbs` keeps splitting on `. ; ! ?` and resetting on "but" and "then". A comma now ends a negation only when:

- the negated part before it named no guarded verb form ("no, send it", "no problem, send it", "don't wait, send it" allow Send, as today), or
- the words after it start a new instruction: they begin with "just", "instead", "rather", "now" or "please" ("don't delete it, just send it" allows Send).

Otherwise the negation runs on to the next break: "don't delete, send or archive anything" and "don't send it, save it" do not allow Send ("don't send it, just save" still does not, since Send is in the negated part).

### Docs

`docs/tasks.md` § Confirmation guard: which routes are guarded (by name, label, grid cell, cursor, point, drag, focus and Return or Space), that the screen is read again after a yes, and that a press onto a guarded button the step did not name fails with `<verb> not confirmed, look again`. The NH-61 as-built's sentence about elements seen only after the observation points here.

## Tests

`NoHandsCore` (table rows in `IrreversibleGuardTests`, one test per rule):

- `held` routes: grid cell over Send vs label `n` named Send (both directions), cursor move then `click(.cursor)` in one step, a click at the cursor when the real pointer is already over Send, `releaseMouse` over Send, a point click on Send, a drag onto Send by label and by point, focus then Space, Space on a focused button, Space with a modifier not held.
- `unconfirmed`: a guarded title not allowed, allowed by the goal, already confirmed, an unguarded title, nil title.
- Negation rows: "no, send it" allows; "don't send it, just save" does not; "don't delete, send or archive anything" does not; "don't delete it, just send it" allows; today's rows unchanged.

`NoHandsMac`:

- `TaskRunnerTests`: the observation changes during the wait. Rows: label 1 renamed from Send to Delete → nothing clicked, step fails `element changed, look again`; Send moved → the click lands at the new frame; unchanged → clicks as today.
- `ActionExecutorTests`: one table for the press-time check with a fake `elementTitle(at:)` / `focusedElementTitle()`: a cursor click on Send refused, allowed when confirmed, allowed when the title is unknown, Space on a focused Send refused.

Manual (needs Accessibility): in Mail, a task "reply to Anna" that reaches Send by pointer move and click is held; Return on a focused Send with the native walk fails with `send not confirmed, look again`.

## Leaves out

- The spoken confirm for fixed phrases (separate ticket), typed newlines (NH-61 spec).
- Asking for a yes mid-step: a press-time catch fails the step instead, and the next step asks.
- Shortcuts that send (command-Return in Mail) beyond Return on a focused button, as in NH-61.
- `screenCenter` cursor moves in the before-step check (no screen frame in `NoHandsCore`); press time covers them.

## Calls I made

- Point clicks (the vision fallback's) are checked too, by the element under the point, though the ticket lists picture-point clicks as out of scope: the same lookup covers them for free and a press on Send by point is still a press on Send. Dropping it is one case in each check.
- A press-time catch fails the step rather than pausing it for a yes: resuming half a step after a 30 s wait is riskier than letting the model look again, and the next step's name is held by check 1.
- An unknown title at press time lets the press go ahead, so canvases, games and apps with poor Accessibility keep working; the before-step check still applies.
- The screen is always read again after a yes, not only "when it changed": finding out whether it changed needs the read.
- Space is held only without modifiers; Return keeps today's rule (any modifiers).
- "A new instruction" after a comma is a fixed list of opening words (just, instead, rather, now, please), plus the old rule when the negated part named no guarded verb. "don't delete it, send it" now asks before Send: a safe-side false positive.
- The press-time check runs only in model task steps, where `TaskRunner` sets `pressGuard`; grammar commands are the user's own words (NH-61).
- One Accessibility hit test per press in a task step: a single call, not a walk, so it adds no noticeable time.
