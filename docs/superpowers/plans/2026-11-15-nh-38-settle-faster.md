# NH-38: Settle faster after each task step: Plan

Spec: [2026-11-09-nh-38-settle-faster-design.md](../specs/2026-11-09-nh-38-settle-faster-design.md). Branch
`feat/nh-38-settle-faster`. Verification after every task: `swift build` clean; after tasks 1 and 2 also `swift test`.
The spec is the source of truth; this plan only orders the work and names the files.

## Task 1: policy and watch (NoHandsCore)

- `Sources/NoHandsCore/SettlePolicy.swift` (Foundation only): `enum SettlePolicy { case none, oneLook, full }` with
  `static func `for`(_ actions: [Action]) -> SettlePolicy` (highest level among the actions; empty list is `none`). The
  per-action switch is exhaustive with no `default`. Levels exactly as the spec's table. `pressKey`: `oneLook` when its
  modifiers are empty (shift alone and function alone also count as no Command, Control or Option) and the key is not
  Return; `full` for Return or any chord with command, control or option.
- `SettleWatch` in the same file: a struct fed one `ScreenObservation` at a time (`mutating func feed(_:) -> Bool`,
  true when settled), keeping the last four readings. Settled when `Settle.same` holds for the last two, or when the last
  two differ only in element values and every element identity (role + title + states, grouped, values compared as a
  group) whose values changed between them also changed between the two before them. Any change to app, window title,
  URL, surface, media, or the set of identities is real. Make `Settle` expose what `SettleWatch` needs (for example an
  internal `Settle.sameExceptValues`) rather than copying the comparison.
- Tests in `Tests/NoHandsCoreTests/TaskGuardsTests.swift`: one table for `SettlePolicy` (mixed steps, empty, each
  `press_key` case, `wait_for`, a read) and one table for `SettleWatch` (ticking value settles on the second poll; a
  value change with a new element does not; a changed title and a changed URL do not; a value that changes only once
  does not).

## Task 2: runner (NoHandsMac)

- `TaskRunner.settle` takes the step's policy: `.none` one observation, no sleep; `.oneLook` sleep
  `min(minSettleMs, settleMs)` then one observation; `.full` the current polling loop using `SettleWatch` in place of
  `Settle.same`. `settleMs == 0` is one observation with no sleep for every policy. The existing no-step calls
  (`settleWaitsForTwoEqualObservations`, `settleStopsAtMax`, the Chromium-exposure call) keep today's behaviour
  unchanged, and those two tests must pass unedited. The limit stays `settleMs` of wall time on every path.
- The two in-loop settle calls and the playback check after `done` pass the policy of the step just run
  (`SettlePolicy.for(step.actions)`, so a blocked or failed step keeps its actions' policy). The playback check after a
  `done` keeps `full`.
- Typed window wait (spec section 3), only for `taskHarness == .agentDesktop`, a step whose policy came from
  `open_url`/`open_app`, and a front app with no window (`observer.frontWindow().frame == nil`): run
  `harness.act(.wait(.event, value: DesktopEvent.windowOpened.rawValue, app: front app, ref: nil, timeoutMs: left))`
  through `runCancellable` so `cancel()` kills it; `left` is `settleMs` minus time spent, and the time counts toward
  the limit. `open_app` with the wait delivered: one observation. `open_url` delivered, or any timeout or failure:
  continue polling for the time left. A failed wait never fails the step. If the front app has a window: no wait, poll
  as `full`.
- `public private(set) var settleTimes: [Int]`, reset at the start of `run`, holding each value `onStep` reports in ms.
- `VoicePipeline.swift` (~line 561): append `settle=<a>+<b>+...` to both `outcome` and `detail` strings
  (`task(done, steps=3, settle=120+300+90)`); omit the part when empty.
- Tests in `Tests/NoHandsMacTests/TaskRunnerTests.swift`: a typing step does one sleep and one observation; a navigation
  step polls until two readings match; a ticking value stops by the second poll; a `wait`-only step does no sleep; a stop
  during the harness wait ends the task `.stopped`; with `FakeHarness`: the wait runs only with no window, `open_app`
  then observes once, `open_url` keeps polling, a timed-out wait still gives an observation within `settleMs`. Extend
  `FakeHarness` in `Fakes.swift` only as needed (a controllable wait result and delay). Merge rows where a table fits.

## Task 3: docs

- `README.md`: in the task-loop paragraph and the `settleMs` key text add one clause each: the wait depends on what the
  step did, and `settleMs` is the most it can take. Default stays 3000. Mention the `settle=` part of the utterance log
  only if the README already documents the `task(...)` log line.
- Run the intent fixtures only if the CLI and a key are available; otherwise list them under Not proven. The manual
  3-step YouTube timing also goes under Not proven.
