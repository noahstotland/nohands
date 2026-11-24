# NH-150: Press only the exact title for pack menu steps, and close two guard gaps: Design

**Date:** 2026-11-16  **Ticket:** [NH-150](https://github.com/noahstotland/nohands/issues/150)
**Status:** Shipped
**Shipped:** in PR #173, with differences: [as-built](../as-built/2026-11-16-nh-150-exact-menu-steps.md)

## Intent

Three gaps found in the #80 review:

1. An installed pack's `menu_item` step is matched like the user's own "menu <words>": exact title, then titles whose words start with it, then titles holding every word. A third-party pack titled "Again" can press "Send Again".
2. `ShortcutGuard` allows command-Q, command-W, `close_app` and the "Quit …" / "Close …" menu items whenever the goal holds a quit or close word, even negated: "don't quit Safari" counts as asking to quit.
3. Menu titles are compared with no check for lookalike letters. A title like "Sеnd" (Cyrillic е) is not the word "send" to the guards, so an app or page that names an item that way slips past the irreversible and shortcut guards when a step names it.

## Scope

Builds:

- **Exact-only menu steps for installed packs.** A `menu_item` step from an installed pack (parsed by `PackFile`, which covers local installs and the marketplace) presses only the item whose title equals the pack's title, natively and through the agent-desktop fallback. Built-in packs keep today's closest match.
- **Negation in `ShortcutGuard`.** A quit or close word after a negation in the same clause ("don't quit Safari", "never close this") no longer allows command-Q, command-W, `close_app` or a quit or close menu item. The clause rule is `IrreversibleGuard.goalVerbs`, reused, not copied.
- **Lookalike titles never match.** A menu entry or step title that is a mixed-script lookalike of an ASCII title is never pressed, and an installed pack whose `menu_item` title is one is rejected at parse.

Non-goals: a pack-file field to opt back into closest matching; changes to the built-in packs' titles; the model-step path (already exact-only); pack signing and the registry (#85).

Anti-goals: rejecting legitimate non-English menus (a French, Russian or Japanese app must keep working, see § Lookalikes); a new `Action` case that a `default:` branch in a guard could silently skip.

NH-155 (`click_in` on the menu bar skips the quit, close and Apple menu checks): **not touched.** It is a separate path (`case .clickIn` in `ActionExecutor+Harness.swift`, `MenuBarGuard`) and stays its own ticket. Its acceptance test does get the negation fix for free once it calls `ShortcutGuard`, since NH-155 will route `.clickIn(.menubar, …)` through the same `blocked` function.

## Design

### 1. Exact flag on the step (`Action`, NoHandsCore)

`case menuItem(String)` becomes `case menuItem(String, exact: Bool = false)`. The default keeps every built-in literal (`.menuItem("Step Into")`) as it is, and the compiler finds every pattern match (about 20 sites: guards, summaries, `RouteMemory`, `SettlePolicy`, `SpokenFreeText`, `PackFile`, `PackSet`, the executor), so no guard can miss the new form behind a `default:` branch. `Equatable` stays synthesized.

- `PackFile.parseAction` returns `.menuItem(title, exact: true)` for `"kind": "menu_item"`. No new JSON field: every installed pack is exact. `PackFile.encode` writes the same JSON as today (the flag is not stored), so `pack new` drafts and re-encoded packs are unchanged on disk.
- The grammar's "menu <words>" stays `exact: false`. `IntentDecoder` stays as is; model steps are already exact through `labelSnapshot`.
- Executor (`ActionExecutor+Harness.swift`, `case .menuItem`): `pressMenuItem(name, exactOnly: exact || labelSnapshot != nil)`, and the agent-desktop fallback's "may press only the title it named" check (`plain(m.name) != plain(last)`) applies when `exact || labelSnapshot != nil`.
- `PackFile`'s `namesLoosely` hold on short titles stays: with exact matching it is no longer needed for installed packs, but it costs nothing and still guards the fallback path.

Why not exact for built-ins too: Mail's "Mailbox > Go to Favorite Mailbox > Sent" and the in-flight Chrome, Safari and Finder packs (NH-74, NH-77, NH-78) were written against the closest match, and their real titles can't be checked by `swift test`. Built-ins are our code, reviewed in our PRs, so the third-party risk the ticket names doesn't apply. The table below says whether exact matching would still find each one, so a later ticket can flip built-ins with evidence.

### Built-in `menu_item` titles on main

| Pack | Title | Real menu item (macOS 14) | Exact still finds it? |
|---|---|---|---|
| VS Code | `Step Into` | Run > Step Into | Yes |
| Mail | `Mailbox > Go to Favorite Mailbox > Sent` | Mailbox > Go to Favorite Mailbox > Sent | Yes if the favorite is titled "Sent"; a renamed or account-qualified favorite ("Sent — iCloud") needs the closest match. Unverified, manual check |
| Messages | `Mark as Unread` | Conversation > Mark as Unread | Yes |
| Messages | `Mark as Read` | Conversation > Mark as Read | Yes |
| Messages | `Emoji & Symbols` | Edit > Emoji & Symbols | Yes (`&` survives `plain`, folds to a space) |
| Messages | `Delete Conversation…` | File > Delete Conversation… | Yes (`plain` drops the trailing `…`) |

Terminal has no `menu_item` steps. Slack is not on main (`AppPacks.all` is Terminal, VS Code, Mail, Messages). Titles for NH-74/77/78 ("Move Tab to New Window" and others) are those tickets' to list; they stay on closest matching under this design, so nothing they rely on changes. "Real menu item" is from the apps' documented menus, not a run on this machine; the PR lists it under Not proven.

### 2. Negation in `ShortcutGuard` (NoHandsCore)

`IrreversibleGuard.goalVerbs` goes from `private` to `internal` (same module). `ShortcutGuard.blocked` and `ShortcutGuard.allowsClose` use `IrreversibleGuard.goalVerbs(goal)` in place of `Set(CommandGrammar.normalize(goal))`. The rule: a negation ("not", "never", "don't", "won't", "no", "without" and the rest of that list) removes every later word in its clause; a comma, full stop, semicolon, "!", "?", "but" or "then" ends the clause.

- "don't quit Safari", "never close this" → blocked.
- "quit Safari", "close this tab", "don't save, just quit" → allowed (the comma ends the negated clause).
- `allowsClose` feeds `TabGuard` (`BrowserTabs.swift`), so "don't close the tabs" no longer lets the tab closer act either. Same rule, same words.

### 3. Lookalikes (`MenuMatch`, NoHandsCore)

`MenuMatch.isLookalike(_ title: String) -> Bool`: true when the title's letters are not all ASCII but its **skeleton** is. The skeleton maps each letter through NFKC (fullwidth `Ｓ`, mathematical `𝐒` become `S`) and a small table of Cyrillic, Greek and Armenian letters that look like Latin ones (Cyrillic а е о р с у х ѕ і ј һ ԁ ԛ ԝ and their capitals, Greek ο α ν ρ τ ι κ and capitals, Armenian օ ս). Only letters count, so "Save…", "Emoji & Symbols" and curly quotes are not lookalikes.

So a title is rejected only when it is an ASCII title in disguise. Legitimate non-English menus keep working:

| Title | Letters ASCII? | Skeleton ASCII? | Lookalike? |
|---|---|---|---|
| `Sаve` (Cyrillic а) | No | Yes | **Yes** |
| `Ｑｕｉｔ` (fullwidth) | No | Yes | **Yes** |
| `Enregistrer sous…` (French) | Yes | — | No |
| `Envoyer à nouveau` (French, `à`) | No | No (`à` is not in the table) | No |
| `Закрыть Safari` (Russian) | No | No (з, к, ы…) | No |
| `Safari を終了` (Japanese) | No | No | No |

A Russian or Greek title made only of letters in the table (a two-letter word like "со") would be flagged; that is a title no real menu uses alone, and the cost is "no menu item called …", not a wrong press.

Where it applies:

- `MenuMatch.firstMatch` skips entries whose title is a lookalike, in every tier and for every caller (grammar, pack, model).
- The agent-desktop fallback in the executor rejects a found item whose name is a lookalike.
- `PackFile` rejects a pack whose `menu_item` title (any part of the path) is a lookalike: `bad menu_item title (lookalike letters)`.
- A model step whose title is a lookalike finds nothing, so it fails with "no menu item called …". No guard change is needed for it.

## Tests

One table-driven test per rule (`AGENTS.md` § Testing), all in `NoHandsCoreTests`:

- **Exact-only:** `firstMatch` with `exactOnly: true`: "Again" misses `[Send Again]`, hits `Again` in `[Send Again, Again]`; and `PackFile.parse` gives `.menuItem(_, exact: true)`, while `AppPacks.all` entries stay `exact: false` (the built-in rule).
- **ShortcutGuard negation:** "don't quit Safari" + command-Q, "never close this" + command-W, "don't quit" + `close_app`, "don't close it" + menu "Close Window" block; "quit Safari", "close this tab", "don't save, just quit" allow.
- **Lookalikes:** the table above through `isLookalike`; `firstMatch("Save")` misses an entry titled `Sаve`; `PackFile.parse` rejects a lookalike `menu_item`.

Manual (PR Not proven): an installed pack's short title in a real app, the Mail Sent favorite, a French-language Safari menu.

## Docs

`docs/app-packs.md`: the `menu_item` row says installed packs press only the exact title (after case, `…` and whitespace), and that lookalike titles are rejected; the "short form of an irreversible item" bullet notes it still applies. No voice phrase changes, so `docs/voice-commands.md` is unchanged.

## Calls I made

- **Built-in packs stay on closest matching.** Only `PackFile`-parsed packs (local installs and the marketplace) are exact. The Mail "Sent" favorite can't be proven exact in `swift test`, and NH-74/77/78 are building against closest matching now.
- **No opt-out field in the pack format.** An installed pack can't ask for closest matching; the author names the full title (`pack new` already writes full titles).
- **The flag lives on `Action.menuItem` with a default**, not in a new case, so the compiler finds every match site and no guard's `default:` can skip it.
- **The negation fix also reaches the tab closer** (`TabGuard` via `allowsClose`), not only the shortcut guard, since both read the same close words.
- **Lookalike = ASCII title in disguise** (non-ASCII letters, ASCII skeleton through NFKC and a short Cyrillic/Greek/Armenian table), not "any mixed-script word": Japanese titles mix scripts inside a word ("URLを開く"), so a mixed-script rule would break them.
- **The lookalike check applies to every caller**, grammar and model steps included, not only packs: a lookalike item is never pressed by name.
- **`namesLoosely` stays** on installed-pack titles even though exact matching makes it mostly redundant.
- **NH-155 is not touched.**
