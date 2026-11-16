# Voice commands

Everything NoHands understands without a model. Anything else goes to Claude or the local model as a task (see [Tasks](tasks.md)). Back to the [README](../README.md); settings are in [Configuration](configuration.md).

| Say | Does |
|---|---|
| `type <words>` | Types the words, spoken punctuation applied |
| `spell <letters>` | Letters, NATO words (`kilo`, `x ray`), digits, `space`, `dash`, `dot`, `underscore`, `at sign` as one string; `capital` uppercases the next letter (`spell capital kilo nine x ray` types `K9x`) |
| `press command shift s` | Presses a key chord |
| `enter`, `tab`, `escape`, `delete`, arrow names | Presses that key |
| `undo`, `redo`, `copy`, `paste`, `cut`, `select all`, `save`, `find` | Standard shortcuts |
| `select word`, `select line`, `select sentence`, `select paragraph`, `select the last word`, `select the last sentence` | Selects that unit at the caret in the focused text field (the last whole word or sentence that ends before the caret). The same with `delete` removes it (`delete the last sentence`, `delete line` takes the whole line and its newline). Without a text field the row says `no text field: click into one first` |
| `select <words>`, `delete <words>`, `replace <words> with <words>`, `go before <words>`, `go after <words>` | Finds the words in the focused text field (case does not matter, whole words only, a leading `the`, `a`, `an` or `my` is optional) and selects, deletes, replaces or puts the caret next to them. The nearest match before the caret wins, else the nearest after it (with a selection, a match inside it does not count as after); no guess at near matches: a miss says `no "<words>" in the text`. `replace coffee with tea` splits at the first `with`; a replacement keeps a capital the old words started with. The words must be in a text field you have focused, so `select the second option` in a list still goes to the model |
| `go to the end of the line`, `go to the start of the line` (`beginning`), `go to the end of the document`, `go to the start of the document` (`top`, `bottom`) | Moves the caret with the arrow keys, in any text field, with no read |
| `capitalize that`, `uppercase that`, `lowercase that` | Changes the case of the selection, or of the word before the caret when nothing is selected (`capitalize` raises each word's first letter) |
| `make that shorter`, `longer`, `clearer`, `simpler`, `more concise`, `more formal`, `more casual`, `more polite`, `more professional`, `friendlier`; `say it more politely` (`formally`, `casually`, `clearly`, `simply`, `concisely`, `professionally`); `fix the grammar`, `fix the grammar in that`, `fix the spelling`, `proofread that`; `translate that to French`; `rewrite that`, `rewrite that as a list` | Asks the model to rewrite the selection (with nothing selected, the last sentence before the caret) and types the answer over it, so `undo` takes it back. **The selected text is sent to Claude, or to the local model on this Mac** ([Privacy](privacy.md)). Command mode only, in a text field you have focused; at most 2,000 characters. The row shows `rewriting…`, then the first words of the answer; `stop` cancels it before anything is typed |
| `new tab`, `close tab`, `close window`, `quit app`, `switch app`, `spotlight` | App and window shortcuts; filler ignored (`close the current tab`, `close this window`) |
| `no, the other one`, `the next one`, `also …`, `instead …` (within 30 s of a task) | A follow-up that refers to the task that just ended: the model sees its goal and steps. Goes to the model as a task, not the grammar; see [Tasks](tasks.md#multi-step-tasks) |
| `minimize`, `full screen`, `hide app`, `reload` / `refresh` | Window and app shortcuts |
| `left half`, `right half`, `snap left`, `top left`, `maximize`, `center window` | Moves and resizes the front window; richer phrasing such as `make the window half width and snap to the left side of the screen` goes to the model |
| `go back`, `go forward`, `next tab`, `previous tab` | Browser and tab navigation |
| `tab 3`, `tab number 3`, `switch to tab 3`, `go to tab 3`, `first tab`, `last tab` | Tab 1 to 99; outside a browser `no browser in front` |
| `switch to the YouTube tab`, `go to the YouTube tab`, `open the YouTube tab` | Tab by title; miss: `no tab called …` |
| `close the other tabs`, `close other tabs`, `close all other tabs` | Close Other Tabs menu item; none (Chrome): `no Close Other Tabs menu item in …` |
| `list tabs`, `list the tabs`, `list my tabs` | Board line for a few seconds: `1 YouTube · 2* Inbox · 3 GitHub` |
| `go to <site>` | Site or domain in the default browser; other text goes to the address bar |
| `search for <words>` | The page's or app's search box, else a known results page (YouTube, Google, Amazon, Reddit, Wikipedia…), else the address bar. Refused: `javascript:`, `file:`, `chrome:`, any `scheme:text`: `can't search for that` |
| `search for <words> on <site>`, `search <site> for <words>` | That site's search box if in front, else its results page |
| `is it playing`, `is the video playing`, `is anything playing` | Row says `playing`, `paused` or `none` |
| `play`, `resume`, `pause`, `play pause`, `toggle play` (also `play the music`, `pause the video`, `pause the music`; `play the video` goes to the model) | In a browser on a YouTube page, presses the player's `k`; anywhere else, the Mac's play key, which goes to the app macOS treats as Now Playing (Music, Spotify, a browser tab), not necessarily the window in front. `pause` does nothing (`nothing is playing`) unless the front window or the Mac shows playing (a window with no visible Pause or Play button is judged by sound from any app, so `pause` may say `nothing is playing` while a quiet player is open), and `play` does nothing (`already playing`) while it plays, so neither turns into its opposite; `play pause` always toggles. If a text box has focus on the YouTube page, the system play key is used so no letter is typed |
| `next track`, `next song`, `next video`, `previous track`, `previous song`, `previous video` | On YouTube, shift-N and shift-P; anywhere else, the Mac's next and previous keys. With a text box focused on YouTube it fails with `a text box has focus: click the video first` |
| `skip ahead`, `skip forward`, `skip back`, `skip backward`, each with an optional `<n> seconds` | YouTube only (`j` and `l`, 10 seconds a press; the default is 10 seconds, `<n>` is 1 to 600 and is rounded to the nearest 10, so 1 to 4 seconds still moves 10); elsewhere the row says `skip works on YouTube only`. Bare `skip` is not a command |
| `full screen video`, `video full screen`, `make the video full screen` | On YouTube, the player's `f`; elsewhere, the window's full screen (command-control-F), unless the window is already full screen (`already full screen`). Bare `full screen` is still command-control-F |
| `exit full screen`, `leave full screen` | Leaves full screen only when the front window is in it (YouTube: escape, then command-control-F if the window is still full screen; elsewhere command-control-F); otherwise it says `not in full screen` and presses nothing |
| `volume up`, `volume down`, `turn it up`, `turn it down`, each with an optional `<n>` | Steps the Mac's output volume by 10 points, or `<n>` steps (1 to 10); `volume up 20 percent` moves by that many points (1 to 100). Any level above 0 also unmutes |
| `volume 40`, `volume 40 percent`, `volume 40%`, `set volume to 40`, `set the volume to 40 percent` | Sets the output volume (0 to 100, a larger number becomes 100) and shows `volume 40%`. A device with no volume control (some displays and HDMI outputs) says `this speaker has no volume control` |
| `mute`, `mute sound`, `unmute`, `unmute sound` | Mutes or unmutes the Mac's speakers (the output device), not a call's microphone; saying `mute` twice stays muted. An output with no mute switch says `this speaker can't be muted` |
| `click`, `double click`, `right click`, `middle click` | Clicks at the pointer |
| `click 42` | Clicks label or grid cell 42 |
| `click save` | Clicks the element named "save" |
| `click first video`, `click the second result`, `click the 3rd link`, `click last video` | With no exact title, the position among numbered elements (`first` to `tenth`, `1st`, `2nd`, … `last`); too few: `no element named …; say its label number from the list` |
| `hold click` / `release click` | Press and release the button (drag) |
| `move up 100`, `move to 12` | Moves the pointer |
| `scroll down 10` | Scrolls |
| `find <words>` | Scrolls until text or an element with those words shows, pointer left on it; bare `find` is command-F; none: `no match for <words> on this page` |
| `scroll to <words>` | Same as `find <words>`; `scroll to the top` and `scroll to the bottom` go to the model |
| `grid`, `zoom 35`, `show numbers`, `hide` | Targeting overlays |
| `open safari` | Opens or focuses an app |
| `open youtube`, `open youtube.com`, `open reddit in safari` | Website in the default or named browser (any `name.com` works) |
| `start dictating` / `stop dictating` | Switch between command and dictation mode |
| `scratch that` (dictation) | Deletes what your last dictated phrase typed |
| `delete word` (dictation) | Deletes the previous word |
| `delete that` | Presses Delete (it removes what is selected) |
| `go to sleep` / `wake up` | Pause and resume listening |
| `menu <words>` | Presses the front app's menu item through Accessibility, e.g. `menu bookmark this tab`, `menu save as`; none: `no menu item called <words>`; greyed: `menu item <title> is disabled`; the Apple menu is never searched (no `menu shut down`) |
| `<macro name>` (from `macros` in config) | Runs its steps in order on one row (`step 2 of 4 · go to …`); a failure or a stop ends it at that step |

Details: `docs/superpowers/specs/2026-11-05-nh-10-spell-command-design.md`, `docs/superpowers/specs/2026-11-15-nh-53-browser-tabs-design.md`, `docs/superpowers/specs/2026-11-05-nh-15-search-on-site-design.md`, `docs/superpowers/specs/2026-11-15-nh-93-ordinal-click-target-design.md`, `docs/superpowers/specs/2026-11-15-nh-44-find-on-page-design.md`.

- With `attentionWord` set, start each command with it: `computer, new tab`.
- In a browser `show numbers` and `click <name>` can take about half a second longer (a second on the first per launch in Chromium).
- In dictation mode, say `period`, `comma`, `question mark`, `new line`, `new paragraph`, `open quote` and similar to insert punctuation. The text-editing commands work while you dictate too, and `scratch that` forgets what it can no longer undo after one. A phrase command (`delete the old files`, `replace meeting with call`) edits only when those words are in the field; otherwise the words you said are typed like any other dictation.

**How text editing works.** The app reads the focused field through Accessibility (the field's text stays on the Mac and is never logged), works out the range, selects it and types the replacement or presses Delete, so the app's own undo (`undo`) takes the edit back. Reading the field takes at most half a second, and a field over 200,000 characters counts as unreadable, as do password fields. Where the field cannot be read or will not take a selection (some web editors, Google Docs), `select`/`delete` of a word, line or paragraph use keyboard shortcuts instead; sentences, `<words>` and case changes need a readable field and say `can't read the text here: select it by hand or say "select line"`. `go to the end of the line` and the other caret moves always use keyboard shortcuts.

**How rewriting works.** It reads the focused field as the editing commands do, sends only the selection (or the last sentence) and a short instruction, then checks the field is unchanged before typing the answer; if you typed or clicked meanwhile it types nothing and says `the text changed: say it again`. A line break in the answer becomes a space when the selection had none, so a rewrite never presses Return in a chat box. When the selection had line breaks, a multi-line answer is typed line by line with Shift-Return between them, and tabs in the answer become spaces. In TextEdit, Notes, Mail and Pages a multi-line answer comes back as one paragraph with soft line breaks (Shift-Return). In a spreadsheet cell or a one-line field a selection with line breaks is not worth rewriting. A `stop` while it is typing leaves what was typed so far (say `undo`). It needs a model (`rewrite needs a model: add a Claude key or set up the local model`; `rewrite is off` when `intentBackend` is `off`) and a field NoHands can read (`can't read the text here: rewrite needs a field NoHands can read`). It is not a dictation command: while dictating, `make it shorter` is typed as words. Phrases outside this list (`make it bigger`, `make the window wider`) work as before.

## Per-app commands

An app can have phrases that work only while it is in front and win on a shared phrase. Leading `open`, `go to` and `a` / `the` are ignored in lookup (`open a new tab`, `go to the new tab`, `new tab` are the same); where the app lacks the phrase, `open <phrase>` (two or more words) runs the global one (`open a new tab` presses command-T). Each app adds its rows below. Details: `docs/superpowers/specs/2026-11-15-nh-76-per-app-commands-design.md`.

| App | Say | Does |
|---|---|---|
| Terminal | `new window` | Opens a new Terminal window |
| Terminal | `clear`, `clear all` | Clears the screen and the scrollback (command-K) |
| Terminal | `clear screen` | Clears the screen only |
| Terminal | `clear scrollback`, `clear history` | Clears the scrollback only |
| Terminal | `scroll to top`, `scroll to bottom` | Jumps to the start or end of the scrollback |
| Terminal | `split pane`, `close pane` | Splits the window, or closes the split pane |
| Terminal | `bigger font`, `smaller font`, `default font size` | Changes the font size |
| Terminal | `interrupt`, `cancel command` | Sends control-C to the running command |
| Mail | `new message`, `compose` | Opens a new message |
| Mail | `reply`, `reply all`, `forward` | Replies to, replies to all on, or forwards the selected message |
| Mail | `send message`, `send email` | Sends the open draft (two words on purpose: a bare `send` does nothing) |
| Mail | `undo send` | Takes the send back while Mail's undo delay runs |
| Mail | `next message`, `previous message` | Moves the selection in the message list |
| Mail | `get mail`, `check mail` | Checks for new mail |
| Mail | `mark as read`, `mark as unread` | Toggles read and unread |
| Mail | `flag`, `unflag` | Toggles the flag |
| Mail | `archive`, `junk` | Archives the message, or moves it to Junk |
| Mail | `delete message`, `trash message` | Moves the message to Trash (`undo` brings it back) |
| Mail | `show mailboxes`, `hide mailboxes` | Toggles the mailbox list |
| Mail | `go to inbox`, `go to sent` | Opens the Inbox, or Sent |
| Mail | `search mail` | Focuses the search field (then say or type what to find) |
| Mail | `attach a file` | Opens the Attach Files sheet |
| Mail | `close message` | Closes the front Mail window (a draft shows Mail's own save sheet) |
| VS Code | `command palette`, `quick open`, `go to line` | Opens the palette, the file picker, or the line box (then say `type 42`, `enter`) |
| VS Code | `go to definition`, `find references` | Jumps to the definition, or peeks the references |
| VS Code | `next editor`, `previous editor`, `close editor`, `split editor` | Moves along, closes or splits editors |
| VS Code | `toggle sidebar`, `explorer`, `source control`, `extensions`, `problems` | Shows the side bar or a view in it |
| VS Code | `save all`, `format document`, `rename symbol`, `toggle comment` | Edits the file |
| VS Code | `move line up`, `move line down`, `duplicate line` | Moves or copies the current line |
| VS Code | `find in files`, `find and replace`, `replace in files` | Searches, or replaces in the file or the project |
| VS Code | `toggle terminal`, `new terminal` | Shows the integrated terminal, or opens a new one |
| VS Code | `start debugging`, `toggle breakpoint`, `step over`, `step into`, `step out` | Drives the debugger |
| VS Code | `zen mode`, `new window`, `settings` | Window and settings |
| Messages | `new message`, `compose` | Starts a new message (command-N) |
| Messages | `next conversation`, `previous conversation` | Moves between conversations |
| Messages | `search`, `search messages` | Focuses the conversation search field |
| Messages | `show details`, `info` | Shows the conversation details |
| Messages | `mark as unread`, `mark as read` | Marks the conversation through the Conversation menu |
| Messages | `emoji`, `add emoji` | Opens the emoji picker |
| Messages | `tapback`, `react` | Opens the tapback picker |
| Messages | `close window` | Closes the Messages window (command-W) |
| Messages | `delete conversation` | Opens Messages' own delete confirm |

The global `new tab`, `close tab`, `close window`, `next tab`, `previous tab`, `find`, `page up` and `page down` also work in Terminal. Closing a tab or window with a running command shows Terminal's own confirm, which NoHands does not answer (say `enter` or `escape`). `stop` never interrupts a shell command; say `interrupt`.

The global `find`, `next tab`, `previous tab` and `search for <name>` also work in Messages. `delete conversation` asks first, and NoHands does not answer that question for you (say `enter` or `escape`). Sending stays `enter` (or `press return`), so there is no `send` phrase. Pin and unpin are not phrases yet: say them as a request and the model handles them.

In Mail, read, flag, junk and the mailbox list are toggles. `go to inbox` and `go to sent` open the first Favorites mailbox and the Sent favorite, so they need Inbox and Sent in the Favorites bar. `next message` and `previous message` move the selection while the message list has focus. The global `delete`, `undo`, `find`, `up` and `down` keep their meaning while writing a message.

In VS Code the global `save`, `find`, `close tab`, `close window`, `full screen`, `undo`, `redo`, `copy`, `paste` and `select all` work as elsewhere, and `new tab`, `next tab`, `previous tab`, `go back` and `go forward` do the VS Code thing (new file, next or previous editor, navigate back or forward). VS Code phrases that start with `find`, `go to` or `open` (`find references`, `go to line`, `open extensions`) win over the page search, the address bar and app opening while it is in front. `open settings` opens VS Code's settings while it is in front (`open system settings` still opens System Settings). Show, hide and toggle `sidebar` and `terminal` are all one toggle, so `hide sidebar` on a hidden side bar shows it. There is no spoken "stop debugging" (`stop` always halts NoHands): use the debug toolbar or `menu stop debugging`.

More apps: install a pack file with `nohands-cli pack add`; see [App packs](app-packs.md).
