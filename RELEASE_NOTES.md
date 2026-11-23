# Release notes

## 2026-11-23 point agent docs at docs/ pages instead of the README (NH-148) (#178)

Merged 2026-11-23 11:05 pm UTC.

Agent docs now send readers to `docs/voice-commands.md`, `docs/cli.md` and `docs/configuration.md` instead of the README. Nothing to do.

## 2026-11-23 set up the agent team (#179)

Merged 2026-11-23 10:55 pm UTC.

Agent-team config refreshed for the latest collective-wisdom; no app change.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

## 2026-11-16 reject control characters in a vocabulary say and cap spellings per entry (NH-152) (#177)

Merged 2026-11-16 11:36 pm UTC.

A vocabulary entry whose `say` contains a newline, tab or other control character is now skipped (and counted in the launch log) rather than typed as a key press. Each `hear` list keeps at most its first 10 spellings. Nothing to do unless your config relies on either.

## 2026-11-16 list every built-in pack id in the pack and CLI docs (NH-151) (#176)

Merged 2026-11-16 11:36 pm UTC.

The CLI and pack docs now list every built-in pack id: `terminal`, `vs-code`, `mail`, `messages`, `safari`, `finder` and `chrome`.

## 2026-11-16 ask for a spoken yes before irreversible fixed phrases (NH-149) (#175)

Merged 2026-11-16 11:29 pm UTC.

Mail "send message", "delete message", Messages "delete conversation", Finder "move to trash", Chrome "delete browsing data" and "empty trash" now ask first: say "yes", "confirm" or "do it" within 30 seconds, or the phrase is dropped. Mail also accepts a bare "send". Pack authors can mark any phrase with `"confirm": true`, and phrases that send or delete are always marked.

## 2026-11-16 add the eval row to the CLI docs table (NH-158) (#174)

Merged 2026-11-16 8:42 pm UTC.

`docs/cli.md` now lists `nohands-cli eval`, which scores the configured backend on a fixture file.

## 2026-11-16 exact pack menu steps, negated quit/close and lookalike titles (NH-150) (#173)

Merged 2026-11-16 8:30 pm UTC.

Packs you install now press a menu item only when its title matches exactly, so a short title can no longer press a longer one. Saying "don't quit Safari" no longer lets a task quit it. Menu items disguised with lookalike letters are ignored.

## 2026-11-16 dark mode and Do Not Disturb by voice (NH-163) (#172)

Merged 2026-11-16 8:29 pm UTC.

Say `dark mode`, `light mode` or `toggle dark mode` to change the Mac's appearance. The first time, macOS asks to let NoHands control System Events; allow it and say the phrase again. `do not disturb on` and `do not disturb off` run two Shortcuts you make once, named `NoHands Do Not Disturb On` and `NoHands Do Not Disturb Off` (steps in the voice command docs).

## 2026-11-16 Chrome voice commands: windows, tabs, bookmarks, history and more (NH-74) (#171)

Merged 2026-11-16 8:28 pm UTC.

In Chrome you can now say `new window`, `new incognito window`, `reopen closed tab`, `bookmark this page`, `show history`, `downloads`, `developer tools`, `address bar` and dozens more, with or without "open" in front. `open settings` opens Chrome's settings while Chrome is in front, and browsing data is `delete browsing data`.

## 2026-11-16 Finder voice commands (NH-78) (#169)

Merged 2026-11-16 8:25 pm UTC.

In Finder you can now say `new folder`, `go to downloads`, `list view`, `get info`, `rename`, `move to trash`, `put back`, `show hidden files` and more; see the Finder rows in the voice command list. `open the downloads folder` still opens a folder as before, and moving to the Trash is undone with `undo`.

## 2026-11-16 Safari voice commands (NH-77) (#170)

Merged 2026-11-16 8:17 pm UTC.

In Safari you can now say "new private window", "reopen closed tab", "address bar", "bookmark this page", "add to reading list", "show reading list", "show history", "show downloads", "tab overview", "reader", "view source" and more. Tab, reload, back, forward, find and zoom phrases work in Safari as before.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

## 2026-11-16 pack marketplace, browse, install and update packs from a registry (NH-85) (#168)

Merged 2026-11-16 7:54 pm UTC.

You can now browse and install app packs from a registry, and update them, from the Packs menu or with `nohands-cli pack search|install|update`. Nothing is fetched unless you ask, installed packs work with the network off, and no registry is set up by default yet (set `packRegistryURL` and `packRegistryKey` in `config.json`).

## 2026-11-16 spoken feedback (NH-60) (#167)

Merged 2026-11-16 6:55 pm UTC.

NoHands can now speak how a task ended ("Done: open the menu", "Stuck: no Raptors game listed"). Choose Speak Feedback in the menu or say "spoken feedback on"; it is off until you do. "All" also speaks questions and what it read, and "stop" cuts it off.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

## 2026-11-16 pack new drafts an app pack from the menu bar (NH-98) (#166)

Merged 2026-11-16 6:38 pm UTC.

`nohands-cli pack new` writes a starter pack file from the menus of the app in front, for you to edit and install with `pack add`. Items NoHands already handles, irreversible items and anything the pack checker rejects are left out and listed.

## 2026-11-16 pointer and page grammar: drag, page edges, zoom, centre (NH-59) (#164)

Merged 2026-11-16 6:18 pm UTC.

You can now say "drag 5 to 12", "click 12 and hold", "top of page", "zoom in", "actual size" and "move to center". Saying "stop" now also lets go of a mouse button you were holding.

## 2026-11-16 open files, folders and recent documents by voice (NH-58) (#165)

Merged 2026-11-16 6:16 pm UTC.

You can now say "open the downloads folder", "open the budget spreadsheet" or "open my last Keynote". If several files match, NoHands lists up to six and you say the number. Apps, scripts and hidden or library files never open this way.

## 2026-11-16 rewrite the selection with the model (NH-55) (#160)

Merged 2026-11-16 4:38 pm UTC.

You can now say "make that shorter", "fix the grammar" or "translate that to French" to have Claude (or your local model) rewrite the selected text in place; "undo" brings the original back. The selected text is sent to the model when you do.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

## 2026-11-16 system controls by voice (NH-52) (#161)

Merged 2026-11-16 4:34 pm UTC.

Say `lock screen`, `screenshot`, `mission control`, `next space`, `open settings for bluetooth` and similar to do Mac chores by voice. `empty trash` uses Finder's own confirm: say `enter` or `escape`.

## 2026-11-16 remember routes that worked (NH-46) (#162)

Merged 2026-11-16 4:28 pm UTC.

NoHands now remembers how a finished task went and offers those steps to the model the next time you say a similar goal. They are kept in `~/.config/nohands/routes.json` (only you can read it). Say "forget that route" or "forget all routes" to clear them, or set `routeMemory` to `false` to turn it off.

## 2026-11-16 voice macros (NH-57) (#159)

Merged 2026-11-16 3:39 pm UTC.

You can now name a sequence in `~/.config/nohands/config.json` under `macros` (for example `"night game": ["open chrome", "go to streameast.app", "find raptors", "click"]`) and say the name to run it. A failed step or a stop ends it, and the row says which step.

## 2026-11-16 Messages voice commands (NH-82) (#143)

Merged 2026-11-16 2:53 pm UTC.

In Messages you can now say "new message", "next conversation", "search", "show details", "mark as unread", "emoji", "tapback", "close window" and "delete conversation". Nothing changes in other apps.

## 2026-11-16 harness minors from the PR #2 review (NH-7) (#147)

Merged 2026-11-16 2:36 pm UTC.

Dragging to a point left of or above the main display now works with the agent-desktop backend, and saying "stop" during a traced task closes the trace session.

## 2026-11-16 follow-up commands that refer to the last task (NH-48) (#146)

Merged 2026-11-16 2:29 pm UTC.

Say "no, the other one", "the next one" or "also mute it" within 30 seconds of a task and NoHands continues that task instead of starting over. Set `followUpWindowMs` to `0` in the config to turn it off.

## 2026-11-16 custom vocabulary for misheard words (NH-56) (#145)

Merged 2026-11-16 2:25 pm UTC.

Add a `vocabulary` list to `config.json` to fix words NoHands mishears: `{"hear": "raptures", "say": "Raptors"}`. Every command and dictation then uses your spelling. Restart NoHands after editing the file.

## 2026-11-16 Mail voice commands (NH-79) (#140)

Merged 2026-11-16 2:24 pm UTC.

In Mail you can now say "new message", "reply", "reply all", "forward", "send message", "archive", "delete message", "next message" and more. "Send" needs two words so a stray word cannot send a draft; "undo send" takes it back during Mail's undo delay.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

## 2026-11-16 installable app packs (NH-80) (#142)

Merged 2026-11-16 1:38 pm UTC.

You can add voice commands for more apps by installing a pack file with `nohands-cli pack add <file>`, no new build needed. NoHands shows what the pack does and asks before installing; packs only act in their own apps and can't type text, click, or touch "stop". Turn packs off or remove them from the new Packs menu.

## 2026-11-16 VS Code voice commands (NH-83) (#144)

Merged 2026-11-16 1:33 pm UTC.

Say `command palette`, `go to definition`, `toggle terminal`, `step over` and many more while VS Code is in front. They only work in VS Code and need its default keybindings.

## 2026-11-16 short README, reference pages and refreshed contributing guide (NH-119) (#139)

Merged 2026-11-16 12:44 am UTC.

The README is now a short guide to installing and trying NoHands. The full voice command list, CLI tools, config keys and privacy details are on pages under `docs/`.

## 2026-11-16 cut the repo docs to a fraction of their length (NH-99) (#135)

Merged 2026-11-16 12:28 am UTC.

The repo docs are about 57% shorter. Nothing changes for users of the app.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

## 2026-11-16 text editing by voice (NH-54) (#136)

Merged 2026-11-16 12:23 am UTC.

You can now edit text by voice: say "select the last sentence", "delete meeting", "replace meeting with call", "go to the end of the line" or "uppercase that" in any text field, in command or dictation mode. "delete line" now deletes the whole line.

## 2026-11-15 media controls by voice (NH-51) (#137)

Merged 2026-11-15 8:47 pm UTC.

You can now say "pause", "play", "next track", "skip ahead 30 seconds", "mute", "volume up", "volume 30 percent", "full screen video" and "exit full screen" to control video and music without touching anything. On YouTube, play, pause, next, skip and full screen use the player's keys; elsewhere play, pause and next use the Mac's media keys and full screen uses the window's. Volume and mute set the Mac's output volume anywhere. Skip works on YouTube only.

## 2026-11-15 Terminal voice commands (NH-84) (#138)

Merged 2026-11-15 8:38 pm UTC.

In Terminal you can now say "new window", "clear", "clear scrollback", "scroll to top", "split pane", "bigger font" and "interrupt" (control-C). They work only while Terminal is in front.

## 2026-11-15 log Claude token usage and show a session total in the menu (NH-112) (#134)

Merged 2026-11-15 7:58 pm UTC.

The menu now shows how many tokens Claude has used this session (calls, input, cached and output), and each Claude call logs its output tokens. Nothing to do; it resets when you restart NoHands.

## 2026-11-15 command log and View Logs window (NH-111) (#132)

Merged 2026-11-15 7:48 pm UTC.

NoHands now remembers your last 50 commands. Open "View Logs…" from the menu bar to see each one step by step, with how long each step took and, for Claude commands, the tokens used. The log stays on this Mac.

## 2026-11-15 browser tabs by name and number (NH-53) (#133)

Merged 2026-11-15 7:30 pm UTC.

You can now say "tab 3", "last tab", "switch to the YouTube tab", "close the other tabs" and "list tabs" in a browser.

## 2026-11-15 green checkmark by the Claude status when Claude works (NH-109) (#131)

Merged 2026-11-15 7:12 pm UTC.

After "Check Claude connection" succeeds, the menu shows a green checkmark by "Claude: connected at HH:mm".

## 2026-11-15 per-app voice commands, packs and menu items by name (NH-76) (#129)

Merged 2026-11-15 6:51 pm UTC.

Say `menu <name>` in any app (for example `menu bookmark this tab`) to run that menu command without opening the menu. "open a new tab" now works like "new tab". Apps can now bring their own phrases; none ship yet.

## 2026-11-15 a task asks the user a question and takes the answer by voice (NH-47) (#130)

Merged 2026-11-15 6:36 pm UTC.

When a request fits two things on screen, like two games or two drafts, NoHands now asks which one and takes your next words as the answer. Say "stop" to cancel; 30 seconds of silence ends the task.

## 2026-11-15 read page text for the model (NH-50) (#128)

Merged 2026-11-15 5:38 pm UTC.

NoHands can now read the visible text of a web page when it plans a task, so on a schedule page it can tell which "Watch" link belongs to which game. Nothing to set up.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

## 2026-11-15 find on page, scroll until a named element or text is visible (NH-44) (#126)

Merged 2026-11-15 5:15 pm UTC.

Say "find <words>" or "scroll to <words>" and NoHands scrolls the page until that link, heading or label is on screen and leaves the pointer on it, so "click" opens it. Long task goals can use the same find instead of guessing scroll amounts.

## 2026-11-15 status bar in the bottom-right corner, no idle Listening line (NH-92) (#127)

Merged 2026-11-15 5:07 pm UTC.

The status bar now sits in the bottom-right corner and only shows when NoHands has something to say; the always-on "Listening" line is gone. The Status Bar menu offers Off or Bottom Right, and an old Top or Bottom choice becomes Bottom Right.

## 2026-11-15 show the step number alone in the task panel (NH-110) (#125)

Merged 2026-11-15 4:58 pm UTC.

The task panel now shows just the step you are on ("step 2") instead of "step 2 of 12", because NoHands cannot know how many steps a task will need.

## 2026-11-15 action-aware settle waits after each task step (NH-38) (#124)

Merged 2026-11-15 4:50 pm UTC.

Multi-step tasks now wait less after each step: typing, scrolling and similar local steps re-check the screen once instead of polling for up to 3 seconds, and a changing value such as a clock or counter no longer holds the task. Page loads still wait as before. Nothing to configure; `settleMs` is still the most a step can wait.

## 2026-11-15 show the model's phase while it works, with a spinner and fades (NH-118) (#123)

Merged 2026-11-15 4:40 pm UTC.

While NoHands works on a command, the corner panel now says what stage it is in (reading the screen, thinking, acting) with a small spinner, and everything fades out smoothly about a second or two after a result (a little longer after a failure). Saying "stop" clears the panel at once.

## 2026-11-15 site playbooks, fixed routes for common sites in the task request (NH-45) (#122)

Merged 2026-11-15 4:19 pm UTC.

When you ask for something on YouTube, Google, Wikipedia, Amazon or Reddit, the model now gets a short, fixed route for that site, such as "search for the channel, open its Videos tab, play the first video". Nothing for you to do.

## 2026-11-15 confirm before irreversible task steps (NH-61) (#120)

Merged 2026-11-15 4:18 pm UTC.

NoHands now asks "say yes to send" before a multi-step task clicks Send, Delete, Pay, Place order and similar buttons you didn't mention in your request. Say "yes" to go ahead; saying anything else, or nothing for 30 seconds, stops the task. If you use an attention word, start your yes with it.

## 2026-11-15 resolve ordinal click targets like "first video" (NH-93) (#121)

Merged 2026-11-15 4:03 pm UTC.

Saying "click the first video" (or "second result", "third link", "last video") now clicks that item on the page instead of failing with "no element named".

🤖 Generated with [Claude Code](https://claude.com/claude-code)

## 2026-11-10 number badges and click-by-name reach web page content (NH-17) (#20)

Merged 2026-11-10 1:49 am UTC.

- Number badges and "click <name>" now cover the links, buttons and fields on a web page in Chrome and other browsers, not just the toolbar.
- The first number-badge or click-by-name command in a Chromium browser such as Chrome can take about a second longer while the page is prepared (once per launch of the browser).

## 2026-11-10 Model menu toggle between Claude and the local model (NH-116) (#117)

Merged 2026-11-10 12:57 am UTC.

The menu now has a **Model** item that shows whether NoHands is using Claude or the local model and switches between them with one choice, no restart. The choice is saved in `config.json`; Claude is greyed out until an API key is in effect (a key saved from the menu applies after a restart).

## 2026-11-09 set approval risk tolerance to permissive (NH-113) (#115)

Merged 2026-11-09 9:15 pm UTC.

The team now approves Low and Medium risk specs and merges on its own in this repo. High risk ones still wait for your approve. To go back, set the `Approval risk tolerance` row in `docs/agents/project.md` to `balanced` or `strict`.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

## 2026-11-09 full-colour app icon for NoHands.app (NH-33) (#114)

Merged 2026-11-09 9:05 pm UTC.

NoHands now has its own app icon, the winking green face, in Finder, Get Info, Launchpad and a Dock tile you pin yourself. It is still a menu-bar app, so it doesn't show a Dock tile or a Cmd-Tab entry while running.

## 2026-11-09 set the Claude API key from the menu (NH-94) (#107)

Merged 2026-11-09 8:24 pm UTC.

You can now paste your Claude API key from the menu (Set Claude API key…) instead of editing `config.json` by hand. Restart NoHands to apply it.

## 2026-11-09 model-written task plans run and checked in code (NH-91) (#106)

Merged 2026-11-09 8:22 pm UTC.

Some multi-step web goals, like "put on the latest video from a channel", are now planned once up front: the model picks the site and search words, and NoHands runs and checks each step on screen. If a check fails, the usual step-by-step loop takes over.

## 2026-11-09 send Claude a step schema Anthropic accepts (NH-104) (#108)

Merged 2026-11-09 8:21 pm UTC.

Claude commands work again. Every Claude request was being rejected by Anthropic, so natural-language commands and tasks failed whenever Claude was the backend. Nothing to change on your side.

## 2026-11-09 Claude status in the menu and Check Claude connection (NH-103) (#105)

Merged 2026-11-09 7:36 pm UTC.

The menu now shows whether Claude is set up and which key it uses. `Check Claude connection` (or `nohands-cli claude-check`) sends one small request and tells you whether Claude commands will work; it spends about one step's input tokens.

## 2026-11-09 repeatable latency benchmark, nohands-cli bench (NH-40) (#102)

Merged 2026-11-09 5:58 am UTC.

none. This is a developer command; users will not notice.

## 2026-11-09 task scenario suite with pass/fail and step counts (NH-49) (#101)

Merged 2026-11-09 5:39 am UTC.

New `nohands-cli scenarios` command runs scripted multi-step goals on your Mac and scores each against the screen, with steps and time. It takes over the screen and keyboard while it runs.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

## 2026-11-09 winking logo and menu-bar icon (NH-32) (#100)

Merged 2026-11-09 5:14 am UTC.

NoHands has a new logo, a winking face with its tongue out. It is in the README and replaces the microphone symbol in the menu bar. The mode text beside it is unchanged.

## 2026-11-09 small-model slip guards for the task loop (NH-90) (#97)

Merged 2026-11-09 4:55 am UTC.

Small local models now recover better in multi-step tasks: a typed web address is opened instead of typed, a stray click on the app's menu bar is refused, and a model that repeats a step is told to try something else. Nothing for you to do.

## 2026-11-09 default the Claude model to Haiku at low effort (NH-95) (#96)

Merged 2026-11-09 4:49 am UTC.

NoHands now asks Claude Haiku at low effort by default instead of Opus, which cuts API cost. If you want the stronger model back, set `"intentModel": "claude-opus-5-5"` and `"intentEffort": "medium"` in `~/.config/nohands/config.json` and restart.

## 2026-11-09 Apache-2.0 licence, third-party notices and community files (NH-31) (#89)

Merged 2026-11-09 3:59 am UTC.

NoHands now has an Apache-2.0 licence, a list of third-party licences, and contributing and security guides. Nothing changes in the app.

## 2026-11-09 vision fallback for the task loop (NH-41) (#86)

Merged 2026-11-09 3:59 am UTC.

With `visionFallback` turned on and a Claude key, NoHands can look at the focused window when it cannot find a control by name (an unnamed play button or close box) and click what it sees. It is off by default; turn it on in `config.json` and grant Screen Recording from the menu. Pixels leave your Mac only on those steps, only to Claude.

## 2026-11-09 close short grammar commands at 350 ms of silence (NH-36) (#87)

Merged 2026-11-09 3:33 am UTC.

Short commands such as "new tab", "scroll down", "click 12" and "stop" now run about half a second after you stop talking instead of after a full second. Free-text commands and anything unclear still wait as before. If you pause inside a short command and it fires early, set `earlySilenceMs` to 0 in `~/.config/nohands/config.json`.

## 2026-11-09 keep the status bar up and warn on stale builds (NH-75) (#88)

Merged 2026-11-09 3:24 am UTC.

The status bar no longer disappears when "show numbers" has nothing to label, and `scripts/bundle.sh` now warns when you build from a checkout that is behind `main`. If the bar is missing, rebuild from an up-to-date `main`.

## 2026-11-09 corner panel with the phrase, step trail and progress bar (NH-70) (#73)

Merged 2026-11-09 2:22 am UTC.

While a request runs, a panel at the bottom right of the screen now shows what you said, the steps done so far and a "step 3 of 12" progress bar, then keeps the outcome for a few seconds. It has no setting.

## 2026-11-09 turn on No Hands with 10 ticket and $200 caps (NH-71) (#72)

Merged 2026-11-09 2:11 am UTC.

No Hands runs can now be started in this repo: after this merges, send `no hands` in the Chief of Staff thread. Each run is capped at 10 tickets and $200.

## 2026-11-09 move to the collective-wisdom v0.2 machine install (#69)

Merged 2026-11-09 1:30 am UTC.

The agent team now runs from the machine install of collective-wisdom v0.2. To update it later, check out a newer release in the clone and rerun `./install.sh`.

## 2026-11-09 always-on status bar overlay with a menu setting (NH-66) (#68)

Merged 2026-11-09 1:10 am UTC.

NoHands now shows a small status bar on screen that always says what it is doing, such as Listening, the step of a running task, Paused, or what permission to fix. Use the menu's Status Bar item to move it to the bottom or turn it off.

## 2026-11-07 install collective-wisdom f49afcc, reject a negated approval (NH-35) (#64)

Merged 2026-11-07 5:59 am UTC.

The Chief of Staff no longer treats a message such as "don't approve 30 yet" or "approve 30, no rush" as an approval. Send a plain `approve N` to approve; `cancel N` and `resume` need the same plain form. `stop everything`, `hold N`, `changes N` and answers are not affected by a "don't" in the message.

## 2026-11-07 close pop-ups, overlays and tabs a page opened until the video plays (NH-42) (#65)

Merged 2026-11-07 5:41 am UTC.

When you ask NoHands to play or watch something in a browser, it now closes pop-under tabs, windows and overlays that the page opened, and returns to the tab it was working in. It never closes tabs you already had open unless you say "close". An ad blocker in the browser is still the first line of defence.

## 2026-11-05 cache the Claude system prompt and log cache usage (NH-37) (#62)

Merged 2026-11-05 7:09 pm UTC.

Task steps and one-shot commands that go to Claude now reuse a cached copy of the long system prompt, which should cut the time to first token and the input cost of each step. The log shows `cache=<read>/<written>` for each Claude response.

## 2026-11-05 media-playing signal so a task knows the video plays (NH-43) (#63)

Merged 2026-11-05 7:09 pm UTC.

Tasks now know whether a video is actually playing: "turn on the latest video" no longer finishes when the page merely loads. Say "is it playing" to see `playing`, `paused` or `none` for the window in front.

## 2026-11-05 install collective-wisdom d3df944 so owner-authored PRs can merge (NH-29) (#30)

Merged 2026-11-05 4:33 pm UTC.

The agent team is updated to collective-wisdom `c8bf556`. `approve N` in the Chief of Staff thread is now the whole merge approval: no GitHub review is posted and no branch protection is needed, so owner-written PRs merge without a 422. The per-agent GitHub user setup is gone; rotate the Chief of Staff thread after this merges so it loads the new skill.

## 2026-11-05 optional attention word so stray speech is not acted on (NH-12) (#27)

Merged 2026-11-05 3:29 pm UTC.

New optional `attentionWord` setting in `~/.config/nohands/config.json`: set it (for example `"computer"`) and command mode only acts on speech that starts with it, so calls and background talk stop pressing keys. It is off by default; "stop", "wake up" and dictation work as before.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

## 2026-11-05 search for X on a site searches the open site (NH-15) (#28)

Merged 2026-11-05 3:27 pm UTC.

"Search for X on YouTube" (and the other sites NoHands knows) now searches inside that site when it is the page in front of you, in the same tab. If it is not open, the results still open in your default browser.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

## 2026-11-05 Start at Login and Open config.json menu items (NH-11) (#25)

Merged 2026-11-05 3:27 pm UTC.

The menu now has a Start at Login checkbox and an Open config.json item. Start at Login makes NoHands launch when you log in (run the bundled app, not `swift run`); Open config.json creates the file if needed and opens it, and changes apply after you restart NoHands.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

## 2026-11-05 spell command for letter-by-letter typing (NH-10) (#26)

Merged 2026-11-05 3:14 pm UTC.

Say "spell capital kilo nine x ray" to type `K9x` letter by letter, for passwords and codes. If a word isn't recognised, nothing is typed and the row tells you which word.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

## 2026-11-05 turn on echo cancellation on the microphone input (NH-13) (#24)

Merged 2026-11-05 1:45 pm UTC.

NoHands now cancels echo from your Mac's own speakers, so a video playing out loud should no longer be typed or acted on. Other people talking and very loud playback can still get through, so "go to sleep" is still the safe choice for calls. Set `"echoCancellation": false` in `~/.config/nohands/config.json` to turn it off.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

## 2026-11-05 scratch that and delete word in dictation (NH-9) (#21)

Merged 2026-11-05 5:34 am UTC.

In dictation mode you can now say "scratch that" to delete what your last phrase typed, and "delete word" to delete the previous word. Saying them inside a longer sentence still types them as text.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

## 2026-11-05 land the prompt board and the search action (NH-3) (#23)

Merged 2026-11-05 5:25 am UTC.

Every prompt you speak now gets a row at the top of the screen showing how it is going, and "search for <words>" searches in the page or app in front of you (YouTube, Finder, Amazon and more) instead of only the address bar. If a search does nothing, the log now names the route it tried. Text that looks like a script or browser address is refused with "can't search for that".

## 2026-11-05 install the collective-wisdom agent team (#16)

Merged 2026-11-05 4:27 am UTC.

Internal: adds the agent-team tooling. No app behaviour change.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
