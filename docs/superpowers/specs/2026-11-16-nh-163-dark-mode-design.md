# NH-163: Dark mode and Do Not Disturb by voice: Design

**Date:** 2026-11-16  **Ticket:** [NH-163](https://github.com/noahstotland/nohands/issues/163)
**Status:** Shipped
**Shipped:** in PR #172, as specified

## Intent

NH-52 gave the system chores a voice phrase but left out dark mode and Do Not Disturb, because neither has a public
API. A keyboard-free user still wants to switch to light mode in a bright room or silence notifications before a call.
Today both need hands or go to the model, which can't do them either.

## Goals, non-goals, anti-goals

Goals: the ticket's Scope and Acceptance. `dark mode`, `light mode` and `toggle dark mode` change the appearance
through an Apple Event to System Events, with the Automation permission asked for the first time the user says one of
them. `do not disturb on` and `do not disturb off` run a Shortcut the user made, by a fixed name.

Non-goals: other Focus modes (Work, Sleep, a custom Focus); any other System Events command (Wi-Fi, login items,
UI scripting); a menu-bar "Grant Automation…" item; giving the model new action kinds; shipping or importing the
Shortcuts for the user; signing with the hardened runtime or notarizing (see Signing below).

Anti-goals, which would make this a failure even if it works:

- Spoken words or model output become part of an AppleScript or a shell command.
- NoHands sends an Apple Event to any app other than System Events, or System Events gets anything but the one fixed
  script.
- The Automation prompt is shown at launch, in onboarding, or for any phrase other than the dark-mode ones.
- The first-run prompt blocks the pipeline, so `stop`, `press enter` or `show numbers` can't run while it is up.
- A denied permission fails silently, or the line doesn't say what to do.
- An existing phrase changes meaning (`dictation mode`, `command mode`, `switch to the youtube tab`,
  `spoken feedback on`, `open bluetooth settings`, `stop`).

## What the code forces

- **Grammar actions run inline.** `VoicePipeline.process` awaits `executor.execute` for a grammar phrase, and the job
  stream is serial: the next utterance, `stop` included, waits until it returns. Only model tasks and rewrites run in
  the task slot. So any wait on the Automation prompt (which waits for the user's answer) must not happen inside the
  action, or nobody can answer it by voice. This drives the permission flow below.
- **The Automation state can be read without asking.** `AEDeterminePermissionToAutomateTarget` with
  `askUserIfNeeded: false` returns at once: `noErr` (granted), `errAEEventNotPermitted` (-1743, denied),
  `errAEEventWouldRequireUserConsent` (-1744, never asked) or `procNotFound` (-600, System Events isn't running).
  With `askUserIfNeeded: true` it shows the macOS prompt and blocks its thread until the user answers.
- **System Events isn't always running.** It is at `/System/Library/CoreServices/System Events.app` and starts on
  demand; the check above needs it running, so the executor starts it (hidden) and checks again.
- **`SystemCommand` is grammar-only** (NH-52). The model's schema and decoder don't have it and packs can't express
  it, so a new case is out of the model's and packs' reach with no new guard.
- **Settings panes are a fixed table** (`SettingsPane`), with the URL built as `x-apple.systempreferences:` plus the
  raw value. The Automation list is `com.apple.preference.security?Privacy_Automation`, which fits that table, so
  `open automation settings` is the spoken fix for a denied permission.
- **Process launching exists.** `AgentDesktopClient` runs a child process with a deadline and kills it on timeout;
  the new runner follows that shape (absolute binary path, argument array, no shell, stdin closed).
- **Signing.** `scripts/bundle.sh` copies `Resources/Info.plist` into the app and signs it ad hoc (or with
  `CODESIGN_IDENTITY`) without `--options runtime`. The app is not sandboxed and has no hardened runtime, so it needs
  no entitlement to send Apple Events; only the `NSAppleEventsUsageDescription` key, which macOS shows in the prompt.

## Approach

**One new `SystemCommand` case for each, an `AutomationAccess` decision in Core, and a fixed-script runner in Mac
(chosen).** Core gets `SystemCommand.appearance(Appearance)` (`dark`, `light`, `toggle`) and
`SystemCommand.doNotDisturb(Bool)`, their phrases in `CommandGrammar.exact`, an `automation` row in `SettingsPane`,
and a pure `AutomationAccess` mapping from the permission check's status code to what the executor does next.
`SystemControlling` gets three methods: the permission check, the permission request (detached), and running the
fixed script or the fixed shortcut. `runSystem` handles the two cases.

Rejected:

- **`NSAppleScript` in the app.** It isn't safe off the main thread, and a System Events that hangs would hang the
  main thread until the Apple Event times out (two minutes). `osascript` in a child process can be killed on a
  deadline.
- **Writing `AppleInterfaceStyle` with `defaults`.** It changes the stored value but the running apps don't switch
  until logout; System Events is the documented route that switches at once.
- **Running dark mode in the task slot** so a prompt wait could be stopped. Other utterances are then held, not run,
  so the user still couldn't answer the prompt by voice.

### Phrases

| Say | Does |
|---|---|
| `dark mode`, `dark mode on`, `turn on dark mode`, `turn dark mode on`, `switch to dark mode` | Sets the appearance to Dark |
| `light mode`, `dark mode off`, `turn off dark mode`, `turn dark mode off`, `switch to light mode`, `light mode on` | Sets the appearance to Light |
| `toggle dark mode` | Switches between Dark and Light |
| `do not disturb`, `do not disturb on`, `turn on do not disturb` | Runs the shortcut `NoHands Do Not Disturb On` |
| `do not disturb off`, `turn off do not disturb` | Runs the shortcut `NoHands Do Not Disturb Off` |
| `open automation settings` (and the other pane forms) | Opens System Settings > Privacy & Security > Automation |

The row says `dark mode` or `light mode` when it worked (the value the script returns, so `toggle dark mode` says
which one it is now). If the appearance is set to Auto, setting Dark or Light turns Auto off; that is what System
Settings does too.

### The one script

NoHands sends exactly one AppleScript, a string literal compiled into the app, run as
`/usr/bin/osascript -e <script> <argument>` with no shell. The argument is the raw value of `Appearance` (`dark`,
`light` or `toggle`), from the enum, never from speech or the model:

```applescript
on run argv
    tell application "System Events" to tell appearance preferences
        if item 1 of argv is "toggle" then
            set dark mode to not dark mode
        else
            set dark mode to (item 1 of argv is "dark")
        end if
        return dark mode
    end tell
end run
```

No transcript, model text, pack text or config value reaches `osascript`'s arguments, and there is no other script.
The runner has a 5 s deadline and is killed on it (`System Events didn't answer: say it again`).

### The Automation permission

**What it lets NoHands do.** macOS grants Automation per target app. NoHands only ever targets System Events
(`com.apple.systemevents`), so the only prompt and the only row under Privacy & Security > Automation > NoHands is
System Events. The grant itself is broad: with it, an app may send System Events any Apple Event, which covers its
whole scripting dictionary: appearance, processes, login items, disk items and files, and (with Accessibility, which
NoHands already has) clicks and keystrokes in other apps. NoHands' code uses none of that: it sends the one script
above and nothing else, and the security review checks that no other Apple Event or `osascript` call exists. The
grant does not let NoHands script any other app directly; each other target would need its own prompt, and NoHands
never asks for one.

**When it is asked.** Never at launch or in onboarding. The first time the user says a dark-mode phrase:

1. The executor reads the state with `askUserIfNeeded: false`. If System Events isn't running (-600), it starts it
   hidden, waits up to 2 s for it, and reads again (`couldn't start System Events` if it doesn't come up).
2. **Granted** (`noErr`): run the script.
3. **Never asked** (-1744): start the request on a detached thread (`askUserIfNeeded: true`), which shows macOS's
   prompt "NoHands wants access to control System Events" with the usage string, and return at once with the line
   `allow NoHands in the prompt, then say dark mode again`. The pipeline is free, so the user can answer with
   `press enter` (OK is the default button), `show numbers` and a click, or by hand. Only one request runs at a time;
   saying the phrase again while the prompt is up gives the same line and no second request. The request only asks;
   it changes nothing, so a `stop` has nothing to undo.
4. **Denied** (-1743), or the script fails with -1743 because the grant was removed meanwhile: the row says
   `allow NoHands to control System Events: say open automation settings`. Nothing is retried.
5. Any other status: `couldn't change dark mode (error <n>)`.

The `NSAppleEventsUsageDescription` added to `Resources/Info.plist`:
`NoHands changes dark mode through System Events when you say "dark mode" or "light mode". It sends nothing else.`

The pure part (status code to next step, and the script's output to `dark` or `light`) lives in Core as
`AutomationAccess` and is unit tested; the calls themselves are manual checks.

### Signing and the bundled app

- `Resources/Info.plist` gains the usage string; `scripts/bundle.sh` already copies it, so the script doesn't change.
- No entitlements file: the app is neither sandboxed nor signed with the hardened runtime, and an app without either
  may send Apple Events after the user allows it. If a later ticket signs with `--options runtime` (needed for
  notarization), it must add an entitlements file with `com.apple.security.automation.apple-events` set to true and
  pass it to `codesign`, or every Apple Event fails as denied without a prompt. `docs/using-nohands.md` says so.
- As with Microphone and Accessibility, an ad-hoc signature makes every rebuild a new app to macOS, so the
  Automation grant is asked again after a rebuild (a stable `CODESIGN_IDENTITY` keeps it). To reset it:
  `tccutil reset AppleEvents dev.nohands.app`.
- Under `swift run` there is no bundle: the prompt names the terminal, not NoHands. That is a dev path only.

### Do Not Disturb through Shortcuts

Investigated as the ticket asks. macOS 14 has no public API for Focus; the Shortcuts action "Set Focus" can turn Do
Not Disturb on or off, and `/usr/bin/shortcuts run <name>` runs a shortcut by name with no extra permission.
NoHands runs exactly two fixed names, `NoHands Do Not Disturb On` and `NoHands Do Not Disturb Off`, as
`/usr/bin/shortcuts run <name>` with no shell and a 5 s deadline; the name comes from the enum, never from speech.
It is shipped because the cost is two phrases and a docs section, and the runner is shared with dark mode.

- The user (or a helper, once) builds the two shortcuts with one action each: Set Focus > Do Not Disturb > On (or
  Turn Off), and runs each once in Shortcuts. `docs/voice-commands.md` gives the steps.
- Exit 0: the row says `do not disturb on` or `do not disturb off`.
- A non-zero exit: NoHands runs `/usr/bin/shortcuts list` and looks for the exact name. Missing:
  `no shortcut called NoHands Do Not Disturb On: make it in Shortcuts`. Present: `the NoHands Do Not Disturb On
  shortcut failed`. Timeout: `the shortcut didn't finish`.
- Building a shortcut by voice alone is slow, which is the real cost of this route. If the manual check finds that
  `shortcuts run` from the app prompts or fails on macOS 14, the PR drops Do Not Disturb and records why, and the
  phrases stay unlisted.

## Testing

Per `AGENTS.md` § Testing:

- One grammar table test: each new phrase (and a filler form, `turn on the dark mode`) to its action, plus the
  unchanged phrases from the anti-goals, and `open automation settings` to its pane.
- One `AutomationAccess` table test: each status code (0, -1743, -1744, -600, another) to its next step and line,
  and the script output (`true`, `false`, junk) to `dark`, `light` or a failure.
- No test runs `osascript`, `shortcuts` or the permission check (they need the real system).
- Manual on macOS 14, listed in the PR: first `dark mode` shows the prompt and the line; `press enter` allows it;
  `dark mode`, `light mode`, `toggle dark mode` each do what they say; Don't Allow gives the denied line and
  `open automation settings` opens the list; System Events not running; the two Shortcuts phrases with the shortcuts
  present and missing; the prompt text shows the usage string from the bundled app.

## Docs

- `docs/voice-commands.md`: the rows above, the Shortcut steps, and the line at the NH-52 note that says dark mode and
  Do Not Disturb have no phrase is rewritten.
- `docs/using-nohands.md` and `README.md` first-run lists: a fourth, optional item, Automation, asked only the first
  time you say `dark mode`; the hardened-runtime note and the reset command in the signing section.
- `docs/privacy.md` if it lists permissions: what the Automation grant allows and that NoHands sends one script.

## Calls I made

- **The first dark-mode phrase only asks; it doesn't change the appearance.** The prompt can't be waited on inline
  without blocking `stop` and the answer, so the user says the phrase again after allowing. One extra phrase, once.
- **"Only one fixed script" is one AppleScript with a fixed argument** (`dark`, `light`, `toggle` from the enum)
  rather than three scripts.
- **Do Not Disturb is shipped** through two Shortcuts with fixed names the user builds, not dropped; dropped at
  build with the reason recorded if `shortcuts run` misbehaves from the app.
- **The script runs in `osascript`, not `NSAppleScript`**, so a hung System Events can be killed after 5 s and never
  holds the main thread.
- **`open automation settings` is added** as the spoken fix for a denied permission, via the existing pane table.
- **No menu-bar "Grant Automation…" item**: the permission is optional and only matters for one phrase; the denied
  line names the fix.
- **No entitlements file and no `scripts/bundle.sh` change**: not needed without the hardened runtime; the
  requirement for a later notarized build is written down.
- **`dark mode` alone means on, not toggle**; `toggle dark mode` toggles. `light mode` is off.
- **Extra spoken forms** beyond the ticket: `dark mode on/off`, `turn on/off dark mode`, `switch to dark/light mode`,
  `light mode on`, `do not disturb`, `turn on/off do not disturb`. No `focus on` (it reads like a click target) and no
  `dnd`.
- **Only Do Not Disturb**, not other Focus modes.
