# Release notes

## 2026-11-09 always-on status bar overlay with a menu setting (NH-66) (#68)

Merged 2026-11-09 01:10 UTC.

NoHands now shows a small status bar on screen that always says what it is doing, such as Listening, the step of a running task, Paused, or what permission to fix. Use the menu's Status Bar item to move it to the bottom or turn it off.

## 2026-11-07 install collective-wisdom f49afcc, reject a negated approval (NH-35) (#64)

Merged 2026-11-07 05:59 UTC.

The Chief of Staff no longer treats a message such as "don't approve 30 yet" or "approve 30, no rush" as an approval. Send a plain `approve N` to approve; `cancel N` and `resume` need the same plain form. `stop everything`, `hold N`, `changes N` and answers are not affected by a "don't" in the message.

## 2026-11-07 close pop-ups, overlays and tabs a page opened until the video plays (NH-42) (#65)

Merged 2026-11-07 05:41 UTC.

When you ask NoHands to play or watch something in a browser, it now closes pop-under tabs, windows and overlays that the page opened, and returns to the tab it was working in. It never closes tabs you already had open unless you say "close". An ad blocker in the browser is still the first line of defence.

## 2026-11-05 cache the Claude system prompt and log cache usage (NH-37) (#62)

Merged 2026-11-05 19:09 UTC.

Task steps and one-shot commands that go to Claude now reuse a cached copy of the long system prompt, which should cut the time to first token and the input cost of each step. The log shows `cache=<read>/<written>` for each Claude response.

## 2026-11-05 media-playing signal so a task knows the video plays (NH-43) (#63)

Merged 2026-11-05 19:09 UTC.

Tasks now know whether a video is actually playing: "turn on the latest video" no longer finishes when the page merely loads. Say "is it playing" to see `playing`, `paused` or `none` for the window in front.

## 2026-11-05 install collective-wisdom d3df944 so owner-authored PRs can merge (NH-29) (#30)

Merged 2026-11-05 16:33 UTC.

The agent team is updated to collective-wisdom `c8bf556`. `approve N` in the Chief of Staff thread is now the whole merge approval: no GitHub review is posted and no branch protection is needed, so owner-written PRs merge without a 422. The per-agent GitHub user setup is gone; rotate the Chief of Staff thread after this merges so it loads the new skill.

## 2026-11-05 optional attention word so stray speech is not acted on (NH-12) (#27)

Merged 2026-11-05 15:29 UTC.

New optional `attentionWord` setting in `~/.config/nohands/config.json`: set it (for example `"computer"`) and command mode only acts on speech that starts with it, so calls and background talk stop pressing keys. It is off by default; "stop", "wake up" and dictation work as before.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

## 2026-11-05 search for X on a site searches the open site (NH-15) (#28)

Merged 2026-11-05 15:27 UTC.

"Search for X on YouTube" (and the other sites NoHands knows) now searches inside that site when it is the page in front of you, in the same tab. If it is not open, the results still open in your default browser.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

## 2026-11-05 Start at Login and Open config.json menu items (NH-11) (#25)

Merged 2026-11-05 15:27 UTC.

The menu now has a Start at Login checkbox and an Open config.json item. Start at Login makes NoHands launch when you log in (run the bundled app, not `swift run`); Open config.json creates the file if needed and opens it, and changes apply after you restart NoHands.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

## 2026-11-05 spell command for letter-by-letter typing (NH-10) (#26)

Merged 2026-11-05 15:14 UTC.

Say "spell capital kilo nine x ray" to type `K9x` letter by letter, for passwords and codes. If a word isn't recognised, nothing is typed and the row tells you which word.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

## 2026-11-05 turn on echo cancellation on the microphone input (NH-13) (#24)

Merged 2026-11-05 13:45 UTC.

NoHands now cancels echo from your Mac's own speakers, so a video playing out loud should no longer be typed or acted on. Other people talking and very loud playback can still get through, so "go to sleep" is still the safe choice for calls. Set `"echoCancellation": false` in `~/.config/nohands/config.json` to turn it off.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

## 2026-11-05 scratch that and delete word in dictation (NH-9) (#21)

Merged 2026-11-05 05:34 UTC.

In dictation mode you can now say "scratch that" to delete what your last phrase typed, and "delete word" to delete the previous word. Saying them inside a longer sentence still types them as text.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

## 2026-11-05 land the prompt board and the search action (NH-3) (#23)

Merged 2026-11-05 05:25 UTC.

Every prompt you speak now gets a row at the top of the screen showing how it is going, and "search for <words>" searches in the page or app in front of you (YouTube, Finder, Amazon and more) instead of only the address bar. If a search does nothing, the log now names the route it tried. Text that looks like a script or browser address is refused with "can't search for that".

## 2026-11-05 install the collective-wisdom agent team (#16)

Merged 2026-11-05 04:27 UTC.

Internal: adds the agent-team tooling. No app behaviour change.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
