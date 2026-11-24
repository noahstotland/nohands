# NH-51: Media controls by voice: Plan

Spec: [2026-11-15-nh-51-media-controls-design.md](../specs/2026-11-15-nh-51-media-controls-design.md). Branch
`feat/nh-51-media-controls`. Verification after every task: `swift build` clean (Swift 6 strict, no
`@unchecked Sendable`); after tasks 1, 2 and 3 also `swift test`. Tests follow `AGENTS.md` § Testing: one
table-driven test per rule, none for HUD copy, none that need a real device, Accessibility or audio.

## Task 1: actions, grammar and volume maths (NoHandsCore)

- `Action.swift`: add `.media(MediaCommand)` and `.volume(VolumeChange)`. `MediaCommand`: play, pause, playPause, next,
  previous, `skip(seconds: Int)` (negative = back), fullScreen, exitFullScreen. `VolumeChange`: `set(Int)`, `by(Int)`,
  `mute(Bool)`. Both Codable, Equatable, Sendable. Fix every exhaustive `switch` over `Action` the compiler flags
  (ActionSummary, intent schema/decoder stay unchanged: the model gets no kinds for these).
- `VolumeMath.apply(_ change: VolumeChange, current: Int) -> Int?` (nil for mute changes), clamped to 0...100.
- `CommandGrammar`: exact-table entries for the fixed phrases in the spec's Phrases table, and a
  `parseMedia(tokens)` rule run before `parsePattern` (next to `parseTab`) for `volume …`, `set (the) volume to …`,
  `turn it up/down [n]`, `skip ahead/forward/back/backward [n second(s)]`. Ranges: skip 1...600 default 10; volume steps
  1...10 default 1 (×10 points); `n percent` moves by n; set clamps. Numbers via `NumberWords`. Out of range = nil.
  `full screen` (bare) and `is it playing` keep their entries; a stop phrase never matches.
- Tests: `CommandGrammarTests` table for every phrase and the no-match cases (`volume up 11`, `skip ahead 0 seconds`,
  bare `skip`, `full screen`, `stop`); `VolumeMathTests` clamping at both ends.
- Commit `feat(core): media and volume phrases (NH-51)`.

## Task 2: routing (NoHandsCore)

- `MediaRoute.swift`: `MediaRoute.step(for: MediaCommand, isBrowser: Bool, host: String?) -> MediaRoute.Step` with the
  spec's table (`siteKeys([KeyChord])`, `systemKey(SystemMediaKey)`, `windowFullScreen`, `exitFullScreen(siteEscape:)`,
  `unsupported(String)`). `SystemMediaKey`: playPause, next, previous. YouTube hosts come from `SitePlaybooks`' YouTube
  playbook (expose one internal/public accessor; do not duplicate the list).
- Test: one table over command × (YouTube browser, other browser host, non-browser).
- Commit `feat(core): media routing (NH-51)`.

## Task 3: Mac layer (NoHandsMac)

- First, a manual feasibility note only (do not block on it): the system-defined event is built with
  `NSEvent.otherEvent(with: .systemDefined, …, subtype: 8, data1: (key << 16) | (down ? 0xA00 : 0xB00))`, key codes
  NX_KEYTYPE_PLAY 16, NEXT 17, PREVIOUS 18; post `cgEvent` on `.cghidEventTap`.
- `InputSynthesizing.pressMediaKey(_:)` implemented in `CGEventInputSynthesizer`; add to the test fake in `Fakes.swift`.
- `VolumeControlling` protocol + `CoreAudioVolume` (default output device; `VolumeScalar`/`Mute`; main element if
  settable else channels 1 and 2; throws `this speaker has no volume control`). Executor takes it as an injected
  dependency with a default; a fake in `Fakes.swift`.
- `ElementProviding.focusedWindowIsFullScreen() -> Bool?` and `focusedElementIsTextInput() -> Bool` (AXQuery
  implementations, protocol-extension defaults `nil` / `false`).
- `ActionExecutor`: handle `.media` and `.volume` as in the spec's Executor section: play/pause state check via
  `mediaState()`, text-focus fallback/failure, exit-full-screen check, volume HUD (`volume 40%`, `muted`), any
  level > 0 unmutes. Skip = repeated `l`/`j`, rounded to 10 s presses, minimum 1.
- Tests with the fakes: pause with state none sends nothing; play while playing sends nothing; YouTube key with a text
  field focused (play falls back to system key; full screen fails); exit full screen when not full screen presses
  nothing; volume `by` and `set` call the fake with the clamped level.
- Commit `feat(mac): run media and volume commands (NH-51)`.

## Task 4: docs

- `README.md` voice command table: rows for the media phrases, volume phrases and exit full screen, stating the YouTube
  vs system-key routing and the do-nothing cases. Add `nohands-cli parse` examples only if the CLI table lists any.
- Commit `docs: media control phrases (NH-51)`.
