# NH-51: Media controls by voice: Design

**Date:** 2026-11-15  **Ticket:** [NH-51](https://github.com/noahstotland/nohands/issues/51)
**Status:** Draft

## Intent

Once the game is on, the user should be able to pause it, turn it up and make it full screen without touching
anything. Today the grammar has no media phrases and the key table has no media keys, so "pause" goes to the model
and "volume up" has no way to happen at all.

## Goals, non-goals, anti-goals

Goals: the ticket's Scope and Acceptance, with the changes listed under Calls I made.

Non-goals: brightness and other system controls (#52, ticket); site keys for video sites other than YouTube; seeking
in native apps (QuickTime, Music, Spotify have no system seek key); choosing which app gets the play key when
several players are open (macOS sends it to its Now Playing app); giving the model new action kinds (it can already
press `k` and `f` in a task, and the YouTube playbook tells it to).

Anti-goals, which would make this a failure even if it works:

- "pause" while nothing plays starts playback, or "play" while a video plays pauses it.
- A site key (`k`, `f`, `l`) is typed as a letter into a text box because the search field had focus.
- A command presses space on a page with no video and scrolls it.
- "exit full screen" puts a window that was not full screen into full screen.
- "volume up" on a muted Mac leaves it muted, or a volume phrase sets a level outside 0 to 100.
- Any phrase in the README table changes meaning: bare "full screen" is still command-control-F, "is it playing"
  is unchanged, "stop" is still a stop and never matches a media phrase.
- A media phrase touches the network or the model.

## What the code forces

- **`Key` holds virtual key codes only** (`Keys.swift`) and `CGEventInputSynthesizer.press` posts keyboard events.
  The system play, next and previous keys are not key codes: they are system-defined events (`NSEvent` type
  `.systemDefined`, subtype 8, `data1 = (NX_KEYTYPE << 16) | (down ? 0xA00 : 0xB00)`), built with
  `NSEvent.otherEvent` and posted through its `cgEvent` on the HID tap. `NoHandsMac` already imports AppKit, so this
  lives in `InputSynthesizer` and Core keeps no AppKit. The ticket asks to check on macOS 14 that a non-Apple
  process's posted event is honoured: the plan's first task is that check, through `nohands-cli run "play pause"`
  with Music and with a YouTube tab, before the rest is built on it.
- **Volume has no key code worth posting.** Posted volume keys move in steps of 1/16 and give no reading back, so
  "volume 30 percent" can't be done with them. CoreAudio's `kAudioDevicePropertyVolumeScalar` and
  `kAudioDevicePropertyMute` on the default output device can, with no permission. `AudioOutputProbe.swift` already
  reads CoreAudio in `NoHandsMac`.
- **`MediaSignal.state(elements:audioPlaying:)` and `ActionExecutor.mediaState()`** already tell playing, paused and
  none from the front window's Play or Pause button, else from any other app's sound. That makes play and pause
  checkable before a toggle is sent.
- **The grammar's exact table is checked first** (after pack phrases), so fixed phrases go there; numbered volume
  and skip phrases need a small rule before `parsePattern`, like `parseTab`.
- **`SitePlaybooks` already holds the YouTube hosts** and says the player keys (`k`, `f`, `m`). The ticket's
  `Media:` line from #43 exists as `mediaState()`, and the page URL comes from `ax.webURL()`.
- **`ActionExecutor` returns a failure string** that the board shows on the prompt's row, and `showHUD` shows a
  one-line notice.

## Approaches

1. **Two grammar-only actions, routed in Core, run by the executor (chosen).** Core parses phrases into
   `.media(MediaCommand)` and `.volume(VolumeChange)`, and a pure `MediaRoute` picks, from the front app being a
   browser and the page host, either YouTube keys, a system media key or a window chord. The executor reads the
   facts (browser, URL, focused role, media state, full screen) and runs the route. Routing and volume maths are
   unit tested; the executor stays thin.
2. **Parse to plain chords in Core** (`.pressKey(k)`). Core can't know what is in front, so "pause" would type `k`
   into Finder; and system keys and volume can't be chords.
3. **Send media phrases to the model.** Slow, needs a backend, and the model can't set the volume at all.

## How it works

### Phrases (Core, `CommandGrammar`)

| Spoken | Action |
|---|---|
| `play`, `resume`, `play the video`, `play the music` | `.media(.play)` |
| `pause`, `pause the video`, `pause the music` | `.media(.pause)` |
| `play pause`, `toggle play` | `.media(.playPause)` |
| `next track`, `next song`, `next video` | `.media(.next)` |
| `previous track`, `previous song`, `previous video` | `.media(.previous)` |
| `skip ahead [n seconds]`, `skip forward [n seconds]`, `skip back [n seconds]`, `skip backward [n seconds]` | `.media(.skip(seconds: ±n))`, n defaults to 10, 1 to 600 |
| `full screen video`, `video full screen`, `make the video full screen` | `.media(.fullScreen)` |
| `exit full screen`, `leave full screen` | `.media(.exitFullScreen)` |
| `mute`, `mute sound` | `.volume(.mute(true))` |
| `unmute`, `unmute sound` | `.volume(.mute(false))` |
| `volume up [n]`, `volume down [n]`, `turn it up [n]`, `turn it down [n]` | `.volume(.by(±10·n))`, n defaults to 1, 1 to 10 |
| `volume up n percent`, `volume down n percent` | `.volume(.by(±n))` |
| `volume <n> [percent]`, `set volume to <n> [percent]`, `set the volume to <n> [percent]` | `.volume(.set(n))`, clamped to 0 to 100 |

Numbers go through `NumberWords`, so "volume thirty percent" and "skip ahead thirty seconds" work. "seconds" may be
"second". Anything outside the ranges is no match (falls to the model), except a set level, which clamps.

### Routing (Core, new `MediaRoute`)

`MediaRoute.route(_ command: MediaCommand, isBrowser: Bool, host: String?) -> MediaRoute.Step`, where `Step` is
`.siteKeys([KeyChord])`, `.systemKey(SystemMediaKey)` (`playPause`, `next`, `previous`), `.windowFullScreen`,
`.exitFullScreen(siteEscape: Bool)` or `.unsupported(String)`.

| Command | Browser on YouTube | Anything else |
|---|---|---|
| play, pause, play pause | `k` | system play key |
| next / previous | shift-N / shift-P | system next / previous key |
| skip ±n s | `l` or `j` × round(n / 10), at least 1 | unsupported: `skip works on YouTube only` |
| full screen video | `f` | command-control-F (the window; QuickTime's video goes full screen with it) |
| exit full screen | escape | command-control-F only if the window is full screen |

YouTube means the URL host is one of `SitePlaybooks`' YouTube hosts; the table reads them from there so they stay
one list.

### Executor (Mac)

- **Play and pause check first.** `pause` reads `mediaState()`; `paused` or `none` shows `nothing is playing` and
  sends nothing. `play` sends nothing when the state is `playing` (`already playing`). `play pause` always toggles.
- **Site keys need the page focused.** Before a YouTube key, the executor reads the focused element's role
  (`AXFocusedUIElement` of the front app). A text field, text area, search field or combo box means the key would be
  typed: play and pause fall back to the system play key; the other site commands fail with
  `a text box has focus: click the video first`.
- **System keys** go through a new `InputSynthesizing.pressMediaKey(_ key: SystemMediaKey)`: a down and an up
  system-defined event on the HID tap.
- **Exit full screen** reads `AXFullScreen` of the focused window (new `ElementProviding.focusedWindowIsFullScreen()
  -> Bool?`); `false` or unreadable shows `not in full screen` and presses nothing.
- **Volume** goes through a new `VolumeControlling` protocol in `NoHandsMac` (`CoreAudioVolume` conforms) with
  `level() -> Int?`, `setLevel(Int) throws` and `setMuted(Bool) throws`, on the default output device: the main
  element when it is settable, else channels 1 and 2. `VolumeMath.apply(change, current:) -> Int` (Core) clamps to 0
  to 100. Any change to a level above 0 also unmutes, as the volume keys do; `mute` and `unmute` set, they do not
  toggle. After each change the HUD shows `volume 40%` or `muted`. A device with no settable volume fails with
  `this speaker has no volume control`.

### README

New rows in the voice command table for the media and volume phrases.

## Testing

Per `AGENTS.md` § Testing, one table test per rule:

- Grammar: every phrase above to its action, plus the no-match cases (`volume up 11`, `skip ahead 0 seconds`,
  `skip`), and that `full screen`, `is it playing` and `stop` keep their actions.
- `VolumeMath`: set clamps (`volume 150 percent` to 100, `volume 0` to 0), steps clamp at both ends.
- `MediaRoute`: each command on YouTube, on another host, and outside a browser.
- Executor, with the existing fakes: pause with state `none` sends nothing; a site key with a text field focused
  falls back or fails as above; exit full screen when not full screen presses nothing.

Manual (listed in the PR): the system-event check above; YouTube in Chrome and Safari; Music; Spotify; QuickTime;
volume set, step and mute with built-in speakers and with AirPods.

## Calls I made

- **Volume and mute use CoreAudio everywhere, never the volume keys or YouTube's `m`.** The ticket lists volume and
  mute as media keys and YouTube `m`; posted keys can't set a percentage or read back a level, and `m` toggles, so
  "mute" on a muted video would unmute it. CoreAudio sets, so "mute" twice stays muted.
- **"pause" with nothing playing does nothing, and "play" while playing does nothing.** Both are toggles underneath;
  the media state check stops the opposite from happening. Costs one window walk (as `is it playing` does).
- **On a non-YouTube page, play and pause use the system play key, not space.** The ticket says space; space scrolls
  a page with no player, and Chrome and Safari already answer the system play key for web video.
- **Only YouTube gets site keys.** Other sites use the system keys; seeking works on YouTube only.
- **A volume step is 10 points** (`volume up 3` is +30), and `volume up n percent` moves by n points. The volume keys'
  1/16 step is not something anyone can count by voice.
- **Skip rounds to 10-second presses** (`j`/`l`); "skip ahead 25 seconds" is 3 presses (30 s).
- **"full screen video" off YouTube is the window's full screen**, and "exit full screen" off YouTube presses
  command-control-F only when the window reports it is full screen.
- **Extra aliases beyond the ticket:** `resume`, `toggle play`, `next/previous song`, `next/previous video`,
  `turn it up/down`, `set volume to`, `leave full screen`, `make the video full screen`. Bare `skip` is not a phrase
  (it would fight "skip ad").
- **Grammar only: the model gets no media or volume action kinds.** Keeps the intent schema and fixtures unchanged.
- **The play key goes wherever macOS sends it** (its Now Playing app) when the front app is not a YouTube tab.
