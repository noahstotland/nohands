# NH-90: Small-model slip guards: Plan

**Spec:** `docs/superpowers/specs/2026-11-08-nh-90-small-model-slips-design.md` (approved). Ticket [NH-90](https://github.com/noahstotland/nohands/issues/90).
Branch `feat/nh-90-small-model-slips`, rebased on `main` (which holds #86). Test: `swift test`. Typecheck: `swift build`.

All new logic goes in `NoHandsCore` (pure, no AppKit or network), unit tested per `AGENTS.md` § Testing. Test lines stay under
the feature lines. Never edit `scripts/intent-eval*.json`.

## Task 1: Typed-address guard (`NoHandsCore`)

- `WebAddress.typedAddress(_:) -> URL?`: `url(for:)` succeeds and the text has `http(s)://`, or starts with `www.`, or the host's
  last label is in the common-endings list from the spec. Known site names without a dot do not count.
- New `TypedAddressGuard.rewrite(_:goal:)` per the spec: whole-text address becomes `.openURL(url, app: nil)`; a bare
  `press_key return` right after a converted action is dropped; off for the text-entry goal words; a `type_text` after an
  `open_app` or `command-l` in the same step is left alone; `type_into`, `set_value`, `search` never rewritten.
- Test: one table-driven test per rule (bare domain, https with path, `www.`, ordinary text, `notes.txt`, `apple`, goal with
  "type", step starting with `open_app` / `command-l`, Return dropped only directly after a conversion).

## Task 2: Menu-bar guard and name binding (`NoHandsCore`)

- `ScreenObservation.menuBarTitles: [String] = []` (not rendered; `Settle.same` ignores it).
- `MenuBarGuard.blocked(_:labels:menuBarTitles:goal:badgesShowing:) -> String?` per the spec (role `AXMenuBarItem`, case-insensitive
  `AX` prefix; allowed with menu words or when all the title's words are in the goal; off while badges show).
- `ElementNames.bind(_:labels:menuBarTitles:goal:) -> [Action]` per the spec (first action only, exact trimmed case-insensitive
  match to a non-menu-bar element, lowest number first; not bound when it names a menu-bar item the goal allows).
- Tests: blocked by label and by name; allowed with "menu", with the title's words, while badges show; binding rules (page element
  beats menu-bar item, "File" vs "Profile", later click not bound, allowed menu-bar title not bound, no match untouched).

## Task 3: Element list (`NoHandsCore` + `NoHandsMac`)

- `LabelAssigner.menuBarLast(_:)`: non-menu-bar elements keep order from 1; menu-bar items follow. Test it.
- `ScreenObserver.observeNative(... menuBarLast:)`: applied after `assign`, before the untitled filter and cap, only from the
  task-loop `observe`, and not while `overlay` is `.labels`. Fill `menuBarTitles` with every menu-bar title found before the
  cap. The one-shot `observe` is unchanged.

## Task 4: Wire into `TaskRunner.run`

Order per the spec: rewrite via `TypedAddressGuard` right after the step is resolved and before `repeats.record` (so History,
repeat detection and `markTaskTab` see `open_url`); `ElementNames.bind` on the `actions` value that runs (before the
point mapping), not in History; `MenuBarGuard` appended to the guard chain after `ShortcutGuard` and `TabGuard`. `badgesShowing`
is `observation.overlay == "labels"`. One `TaskRunnerTests` test with the existing fakes: a typed URL reaches the executor as
`open_url` and History records it; a blocked menu-bar click runs nothing and is recorded as a failure.

## Task 5: Repeat nudge (`ClaudeRequestBuilder.userBlocks`)

When the last two history records have identical non-empty actions, add the block
`  Steps N and M ran the same actions. Try a different approach now; a third identical step ends the task.` after the history
(N, M are the 1-based numbers of those two records). Both backends. Test: present after two identical, absent for different or empty.

## Task 6: Prompt and examples

- Shared system prompt task paragraph: "Prefer deterministic routes: open_url with a direct URL (e.g.
  youtube.com/@mapleridgeworkshop/videos) over clicking through menus", no "type".
- `IntentSchema.localNamedTargetRule`, appended only in `OllamaRequestBuilder.messages` (system prompt only; warm-up prefix
  still matches because both paths use `messages`). Wording per the spec.
- `IntentExamples`: fictional channel `@mapleridgeworkshop`; step 2 uses `target_kind` "element" with the example's own video
  title; the Back example uses a 6/11/17 list; the harness search example's `set_value` moves to number 4 and its search-button
  click becomes `target_kind` "element". Same count and order, Xcode example last.
- Tests: no real channel handle, no copy of the live goal's URL, clicked label numbers all differ, Xcode last. Update the
  `IntentStepTests` assertion on the `@veritasium` URL.

## Task 7: Verify

`swift build` and `swift test` clean; `scripts/intent-eval*.json` unchanged (`git diff --stat -- scripts`). Manual checks (Claude
and local fixture runs, Outdoor Boys live run) need a key, a model and permissions: list them for the PR, do not fake them.
If a local Ollama and `.build/debug/nohands-cli eval` are available, record the local pass rate before/after; otherwise say not run.
