# NH-58: Open files, folders and recent documents by voice

**Date:** 2026-11-16
**Status:** Shipped
**Ticket:** [NH-58](https://github.com/noahstotland/nohands/issues/58)
**Shipped:** in PR #165, with differences: [as-built](../as-built/2026-11-16-nh-58-open-files.md)

## Goal

"Open the downloads folder", "open the budget spreadsheet" and "open my last Keynote" work by voice. Today the grammar opens only apps and sites, and the model has only `open_app` and `open_url`. Spotlight answers the name queries on the Mac. Nothing goes over the network.

## Phrases (grammar)

Each rule runs inside `parsePattern`'s `open` case, before `parseOpenSite` and the `openApp` fallback. `parseTab` still runs first, so `open the YouTube tab`, `open the last tab` and `open the new tab` keep their meaning. No phrase today that starts with `open` and names an app or site changes. The one exception is `open file <words>` (see Calls I made).

| Say | Does |
|---|---|
| `open the downloads folder`, `open downloads folder`, `open my documents folder` | Opens a standard folder in Finder. Folders: Desktop, Documents, Downloads, Pictures, Music, Movies, Home, Applications, Trash. Singular and plural both work (`download folder`), and so do `home folder` and `apps folder` |
| `open the trash`, `open trash` | Opens the Trash in Finder. No other folder has a bare form: `open music`, `open home` and `open photos` stay apps |
| `open the <words> folder` (`<words>` not a standard folder) | Spotlight query for folders whose name contains every word |
| `open file <words>`, `open the <words> file` | Spotlight query for files (not folders) whose name contains every word |
| `open the <words> document`, `… spreadsheet`, `… presentation`, `… pdf` (`the` or `my` required) | The same query, limited to that kind |
| `open my last <kind>`, `open the last <kind>`, `open my latest <kind>`, `open my most recent <kind>` | Opens the most recently used file of that kind, with no list. Kinds: `file`, `document`, `spreadsheet`, `presentation`, `pdf`, `keynote`, `pages`, `numbers`, `word`, `excel`, `powerpoint`. A trailing `file` or `document` is optional (`my last word document`). None: `no recent <kind>` |
| `<n>`, `number <n>`, `open <n>`, `first` … `sixth` (while a file list is shown) | Opens that row of the list |
| `cancel` or any stop phrase (while a file list is shown) | Closes the list: `cancelled` |

A compound marker (`and`, `then`, `in`, `on` and the rest of `compoundMarkers`) inside `<words>` sends the phrase to the model, as `open` does today. Words are matched as the user said them, after the vocabulary and normalizer. Every word must appear in the item's display name, ignoring case and accents. An empty `<words>` is not a match, so `open file` keeps today's routing.

NH-59 (pointer and page grammar) adds `move`, `scroll` and `page` phrases and none that start with `open`, so the two do not overlap. If NH-59 merges first, the build rebases and checks again. The kind words never include `tab`.

## One hit, several, none

- **Zero hits:** the row says `no file called "<words>"` (or `no folder called …`).
- **One hit:** it opens with its default app (folders in Finder). The row says `opened`.
- **Several hits:** the top six by rank show as numbered rows in the corner panel under the prompt, for example `1 Budget 2026.xlsx · Documents`: the display name and the parent folder's name, never the full path. The prompt's row says `say 1 to 6, or cancel` (with the real count). If there were more than six, it says `say 1 to 6, or cancel (more: say more words)`.
- **Rank:** first, a name that is exactly the spoken words, compared with no extension and ignoring case and accents. Then the most recently used (`kMDItemLastUsedDate`, else the content modification date; with no date, last), then the shorter name, then the path, so the order is stable. This lives in `NoHandsCore` and is unit tested.

## The pick wait

A `FilePick` value in `NoHandsCore` holds the hits, the prompt's row id and a 30 s deadline, the same as the NH-61 and NH-47 answer waits. Its `reply(_:)` is pure and table tested, and returns one of:

- **Any stop phrase** (`StopWords.isStop`, which includes `cancel`, `cancel that` and `never mind`) gives `cancel`. The list closes and the row says `cancelled`. A stop is checked first, never read as a number and never merged with another utterance (`MergeBuffer` does not change). A task cannot be running while a pick is open (below), so stop has nothing else to halt. The pipeline still runs its normal stop path, so nothing about stop gets weaker.
- **A number from 1 to N** (digits, number words, `number <n>`, `open <n>`, `first` to `sixth`) gives `open(i)`.
- **A number outside 1 to N** gives `retry`. The row says `say 1 to N, or cancel`. The deadline does not restart.
- **Anything else** gives `passThrough`. The list closes (the row says `dropped`) and the utterance routes as normal: grammar, macro or model.
- **With the attention word on,** unaddressed speech is dropped and the list keeps waiting, as for an NH-47 question.
- **Timeout:** the list closes and the row says `no pick: say it again`.

The pipeline checks for an open pick at the top of `process`, before routing. A pick opens only from a grammar utterance with no task running. Inside a macro step, and in a model task, several hits fail the step with `several files match: say open file <words>`. No list is shown and no names go to the model. Starting a task, Pause, sleep, a mode switch and `stop()` all close an open pick.

## Model action `open_file`

A new native kind. The model passes words or a fixed key. It never passes a path.

- **Fields:** `name` (the words; 1 to 100 characters, no `/`, `\`, `~`, `:` or control characters), `kind` (optional: `file`, `document`, `spreadsheet`, `presentation`, `pdf`, `folder`, `keynote`, `pages`, `numbers`, `word`, `excel`, `powerpoint`) or `folder` (one of the standard folder keys). Send either `name` (with an optional `kind`), or `folder` alone, or `kind` alone (most recent of that kind). Any other mix, an unknown key value, or a `path` or `url` field makes the decoder reject the action. A rejected action fails the response as for any invalid action.
- `Action.openFile(FileRequest)` with `FileRequest` = `.folder(StandardFolder)`, `.named(String, kind: FileKind)`, `.recent(FileKind)`. The grammar builds the same values, so one executor path runs both the grammar and the model.
- **The result returned to the model:** `opened a file`, `opened a folder`, `no file matched`, or `several files match: ask the user to say open file <words>`. It never contains a hit's name or path.
- **Prompt rule:** "To open a file, document or folder the user names, use open_file with the words they said. Never invent a path or a file name." The local model gets one few-shot turn. Two new eval fixtures: `open the quarterly report document` and `open my downloads folder` (the second is grammar-matched, but the model must handle it too when called directly). Existing fixtures are not touched.
- The guard below runs on every hit before the list is built, and again on the chosen hit right before opening. The model cannot reach a file the grammar could not.
- **Not in packs:** `PackFile` keeps rejecting unknown kinds, so an installed pack cannot open files. A macro step can, because macros are grammar phrases.

## Which paths may open (`FileOpenGuard`, NoHandsCore)

A pure decision over facts the Mac side reads with `URLResourceValues` and `UTType`. The table test covers every rule. A hit may open only when all of these hold:

1. **Resolved inside home.** The path with every symlink resolved (`realpath`) is under the resolved home folder. The check compares path components, not string prefixes, so `/Users/noah2` is not under `/Users/noah`. A symlink inside home that points outside home is refused. So is a symlink whose target is hidden.
2. **No hidden or dot part.** No component after home, in the path as found or as resolved, starts with `.`. This keeps out `~/.config` (and so `~/.config/nohands`), `~/.ssh`, `~/.Trash` and any dot folder. It also refuses items with the hidden flag (`isHiddenKey`).
3. **Not `~/Library`.** Nothing under `~/Library` (mail, keychains, app data, caches). `~/.config/nohands` is refused by name as well, so it stays out even if rule 2 changes.
4. **Never executable.** Refused when the item conforms to `public.executable` (apps, command-line tools, bundles). Also refused: a regular file with any execute bit set; a package that does not conform to `public.content` (so Keynote and Pages packages pass and `.app`, `.plugin` and `.prefPane` do not); and a file whose extension is on a fixed deny list. The list: `app command tool sh bash zsh csh ksh fish py pl rb js jar terminal workflow action pkg mpkg dmg mobileconfig prefpane saver kext plugin bundle qlgenerator scpt scptd applescript osascript webloc inetloc fileloc url shortcut`. That last group opens other links or installs things.
5. **Exists and is readable,** at the time it opens.

Refusal on the row: `won't open <display name>: it can run as a program` (rule 4), or `won't open that file` (rules 1 to 3). The name is shown only for rule 4: the hit was on the list, so the name is already on screen.

**Standard folders are exempt from rules 1 to 3.** They come from a constant table, not from input. They are Applications (`/Applications`), Trash (`~/.Trash`) and the seven home folders, and they open only in Finder (`NSWorkspace.open(_:withApplicationAt:)` with Finder). Opening a folder never runs anything inside it.

## Spotlight query (NoHandsMac)

- `SpotlightFileSource` uses `NSMetadataQuery`, scoped to `NSMetadataQueryUserHomeScope`. Its predicate requires each word with `kMDItemDisplayName CONTAINS[cd]`, plus the kind's content types through `kMDItemContentTypeTree` (folders: `public.folder`; `file`: anything but folders). It drops paths under `~/Library` and dot paths before ranking. It reads at most 200 results and stops after 2 s; a timeout counts as zero hits. A recent query sorts by `kMDItemLastUsedDate`, newest first.
- A `FileSource` protocol puts it behind an interface, so a Mac unit test can use a fake source and a fake opener. The test covers one hit opening and several hits listing. It needs no permissions, no Spotlight and no files.
- Spotlight is local, so the "ordinary commands never touch the network" invariant holds. If Spotlight indexing is off, every query returns zero hits.

## Logging and privacy

- **Command log** (`command-log.json`): the phrase as spoken, plus an action of `open file`, `open folder <standard key>`, `open recent <kind>` or `open file pick <n>`. It never holds a hit's name or path.
- **Unified log:** the transcript stays under the private marker, as today. The outcome and detail lines carry the action names and the hit count only. No hit names or paths are logged at any level.
- **Route memory:** `open_file` is saved as `open_file` plus `folder <key>` or `kind <kind>`. The `name` words are dropped, like typed text.
- **The board and corner panel:** they show the listed names and parent folder names while the list is open, and nothing after it closes.
- **The model:** gets only the user's words, which it already had, and the result strings above. After a file opens, later task steps see its window title, as for any app today. The privacy docs say so.
- `docs/privacy.md` gets one bullet: Spotlight runs on the Mac; file names show only on screen; what the log keeps. The README Privacy line does not change, because it says nothing about files.

## Docs

- `docs/voice-commands.md`: the rows in the phrase table above. Every existing row stays.
- `docs/tasks.md`: one line on `open_file` in the model's kinds, if that page lists them.
- `docs/configuration.md`: nothing. There are no new config keys.

## Tests

Following `AGENTS.md` § Testing, one table-driven test per rule:

- Grammar: the phrase table, including the phrases that must not change (`open music`, `open home`, `open the YouTube tab`, `open youtube`, `open chrome and go to youtube`).
- The standard folder table and its aliases.
- Ranking.
- `FilePick.reply`: stop and cancel, in range, out of range, pass-through.
- `FileOpenGuard`: each of the five rules, with symlink-out, dot path, Library, app bundle, execute bit, deny-listed extension, and a Keynote package allowed.
- `IntentDecoder` for `open_file`: the valid shapes; a path field, a slash in `name`, an unknown folder key and a bad mix are all rejected.
- One Mac test: the executor with a fake source (one hit opens, several list, zero fails).

Manual checks, listed in the PR: `open the downloads folder`, a PDF by name, a list of three hits picked by `two`, `cancel` on a list, and `open my last keynote`.

## Leaves out

- Browsing a folder's contents by voice (Finder's list with number badges already covers it).
- Per-app recent documents and the system Recents list (not public). "Last" means Spotlight's last-used date.
- Opening with a chosen app (`open budget in Numbers`): the phrase goes to the model as today.
- Paths spoken aloud, `go to <folder>`, and Finder's Go to Folder.
- A model-side list: the model never sees hit names.
- New config keys.

## Calls I made

- **The model never passes a path.** `open_file` takes words, a kind or a fixed folder key, and the Mac runs the same Spotlight query and guard the grammar does. The ticket said "with a path". A path the model made up, or one taken from a page, is the riskiest input, and the model has no reliable way to know paths anyway.
- **Any execute bit refuses a file.** So does a deny list of link and installer types. A PDF copied from a FAT USB stick or a Windows share often has execute bits set, so it will not open by voice, and the row says why.
- **`~/Library` is refused,** along with dot folders, even though the ticket said only "user folders".
- **`open file <words>` wins over an app whose spoken name starts with "file".** For example, "file merge" said as two words. Saying `open filemerge` as one word, or the model, still works.
- **The trailing-kind form needs `the` or `my`** (`open the budget spreadsheet`), so app names ending in a kind word stay apps.
- **`open the <words> folder` also finds folders by name,** not only the standard nine. It reuses the same query and list.
- **"Open my last Keynote" is included,** because the ticket title names recent documents. It uses Spotlight's last-used date across home and opens the newest, with no list.
- **The list shows the name and the parent folder's name,** never the full path. Up to six rows; a hint asks for more words when there were more.
- **The pick wait is 30 s, like the other answer waits.** Unaddressed speech is dropped, as for an NH-47 question. Any other addressed command closes the list and runs as normal. An out-of-range number keeps the list open.
- **No list inside macros or model tasks.** Several hits fail the step with a message that names no files.
- **Bare `open <folder>` stays an app,** except `open trash`, because Music and Home are apps.
- **Spotlight limits:** 200 results and a 2 s timeout.
