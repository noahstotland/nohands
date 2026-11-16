# CLI tools

Back to the [README](../README.md).

`nohands-cli` exercises the pieces without the menu-bar app (`swift run nohands-cli <subcommand>`). Subcommands acting on other apps need Accessibility for your terminal and wait a few seconds so you can focus the target.

| Subcommand | Does |
|---|---|
| `type "<text>"` | Waits 2 s, then types |
| `key "<chord>"` | Presses a chord, e.g. `"command shift s"` |
| `click-at <x> <y>` | Clicks at screen coordinates |
| `move <x> <y>` | Moves the pointer |
| `transcribe <wav>` | Transcribes a file, prints timings |
| `vad-test <wav>` | Prints voice-activity events |
| `endpoint-test <wav>…` | Replays files through VAD, early close and recognizer; prints early and full text and timing |
| `bench <dir>` | Dry-run latency benchmark over each `.wav`: p50 and p95 per stage; no model backend. Phrases: `Tests/Fixtures/audio/README.md` |
| `elements` | Lists the frontmost app's actionable elements |
| `click "<name>"` | Clicks the named element |
| `grid` | Shows the 10×8 grid, zooms into cell 35 |
| `labels` | Shows numbered badges |
| `parse "<text>" [--app <bundle id>]` | Dry run: the grammar's actions (with ` (asks first)` after them when the phrase waits for a spoken yes), "no match -> LLM", or "rejected: ...". `--app` puts that app in front, so its built-in or installed pack applies |
| `pack add <file>` | Checks a pack file, shows its summary (apps, every phrase with what it does, sites and apps it opens, phrases it replaces or loses to an earlier pack), and installs only if you answer `y` or `yes` at `Install? [y/N]`. No `--yes`. Exits 1 if declined or invalid. See [App packs](app-packs.md) |
| `pack list` | Installed packs: id, version, on or off, phrase count, shadowed or invalid note |
| `pack remove <id>` | Removes an installed pack, no prompt |
| `pack builtin <id>` | Prints a built-in pack (`terminal`, `chrome`, ...; an unknown id lists them) as a pack file, as a template |
| `pack new [--app <name or bundle id>] [--out <file>]` | Reads the app's top-level menu items (the app in front after 3 s, or a running app by name or bundle ID) and writes a draft pack file, listing the items it left out and why. Never overwrites a file and never installs; edit it, then `pack add`. Needs Accessibility. See [App packs](app-packs.md) |
| `pack search [words]` | Fetches the pack registry's signed list and prints each pack whose id, name or description contains all the words (all packs with no words): id, version, name, apps, and `installed` or `update to <version>`. Reaches the network, only because you ran it. See [App packs](app-packs.md#get-packs-from-a-registry) |
| `pack install <id>` | Fetches that pack from the registry, checks it, shows its summary and installs only if you answer `y` or `yes` at `Install? [y/N]`. No `--yes`. If the pack is already installed it tells you to use `pack update` |
| `pack update [<id>]` | For the named pack, or each installed pack, with a newer registry version: fetches it, shows what changed and updates only on `y` or `yes` at `Update? [y/N]`. Prints `all packs are up to date` when there is nothing to do |
| `registry keygen <path>` | For registry publishers: writes a new signing key to `<path>` (mode 600, refuses an existing file) and prints the public key and its key id. No network. See [Publish a registry](app-packs.md#publish-a-registry) |
| `registry sign <index.json> --key <path> [--packs <dir>]` | For registry publishers: checks the index, and with `--packs` each pack file in `<dir>` against its hash and the pack rules, then prints the signed file. Refuses to sign if a file is wrong. No network |
| `menu "<words>"` / `menu --list` | After 2 s (3 s for `--list`) presses the frontmost app's named menu item, or lists them |
| `run "<phrase>"...` | Executes grammar phrases in order; a phrase that asks first (`empty trash`) is refused with `asks first: not run from the CLI` |
| `observe` | Prints what the task loop sends the model: title, URL, `Media:` line, numbered elements |
| `resolve "<text>"` | Dry run: sends text and labels to the backend, prints the step (`intent`, `status`, actions); spends API credit |
| `task "<goal>"` | Waits 3 s, runs the goal as a task for real, printing each step. Ctrl-C stops it, a second quits (130); exits 2 when stuck, failed or stopped |
| `scenarios [file] [--only name]` | Waits 3 s, runs each goal in `scripts/task-scenarios.json` for real, scored against a fresh screen check: `pass`, `false-done`, `unclaimed`, `fail`, `stopped`, `start-failed`, `not-run`. Exits 0 only when all pass, 2 otherwise (1 for a bad file or name). Takes over screen, mouse and keyboard. Ctrl-C stops; a second quits (130). Details: `docs/superpowers/specs/2026-11-09-nh-49-task-scenarios-design.md` |
| `eval <file> [--runs N]` | Dry run: sends each phrase in the fixture file (e.g. `scripts/intent-eval.json`) to the configured backend `N` times (default 1), prints `PASS` or `FAIL` with the time of each call, then accuracy, median time (without the first 2 calls) and model. Executes nothing; spends API credit with the Claude backend. Exits 0 even when cases fail; 1 for a bad file or `--runs`, or with the backend off |
| `listen` | Microphone to recognition, printing transcripts |
| `claude-check` | One-token request with your key; prints connected, key rejected, model not found, request rejected, rate limited, unavailable, timed out, no network, or no key. The key is never shown. Exit 0 only when connected |
| `desktop-status` | Where agent-desktop was found, version, Accessibility, harness in use |
| `snapshot [app]` | Waits 3 s, prints the task-loop observation as agent-desktop sees it |
