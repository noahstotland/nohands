# NH-85: Pack marketplace: Design

**Date:** 2026-11-16  **Ticket:** [NH-85](https://github.com/noahstotland/nohands/issues/85)
**Status:** Draft
**Builds on:** [NH-80 installable packs](2026-11-15-nh-80-installable-packs-design.md) ([as-built](../as-built/2026-11-15-nh-80-installable-packs.md))

## Intent

NH-80 lets the user install a pack from a file. This lets them find, install and update packs from a registry: a signed index file at one `https` URL. Getting a pack is the only new network use, and it happens only when the user asks for it (a menu item or a CLI command). Once installed, a pack runs from disk exactly as an NH-80 pack does, with the network off.

Non-goals: paid packs, ratings, accounts, uploading from the app; auto-update, background checks, launch-time checks; packs with code; hosting the registry; a voice phrase for browsing or installing.

Anti-goals: the voice pipeline, the grammar, `ActionExecutor` or the task loop reaching the fetcher; a pack written to `packs/` before every check passes; an install or update without a yes; a downgrade; a request that carries anything but the index or pack URL; a registry fetch over `http` or redirected to a private or non-`https` address; a registry whose signature the app can't check.

## What changes for the repo invariant

The invariant "Ordinary commands never touch the network" stays true as written: no spoken command, grammar match, model action or task step can start a fetch. What changes is its scope. Until now the only network calls were the intent backend (Claude, or Ollama on loopback). After this ticket there is a second one, the pack fetcher, which runs only from the **Packs** menu items and the `nohands-cli pack search|install|update` commands. `docs/agents/project.md` is not edited by this ticket; if the user wants the invariant to name the fetcher, that is a separate change on the approval path.

## Decision

Pure parts in `NoHandsCore` (index parsing, signature and hash checks with CryptoKit on bytes they are given, version order, the update diff), the network in exactly one new `NoHandsMac` type, `PackFetcher`, and the install through NH-80's `PackStore.install` after a yes. CryptoKit is not a network, AppKit or CoreGraphics dependency, so Core's rule holds.

Rejected: a detached `index.json.sig` (two fetches, two URLs to keep in step); signing canonical JSON (fragile, and Foundation's JSON writer is not canonical); TUF-style delegation and timestamp roles (far more than one hand-run registry needs).

## Registry format (version 1)

The registry URL serves one JSON **envelope**:

```json
{
  "format": 1,
  "keyID": "3f9a1c0d7e2b4a56",
  "index": "<base64 of the index bytes>",
  "signature": "<base64 Ed25519 signature>"
}
```

- `signature` is Ed25519 over the bytes `"nohands-pack-index-v1\n"` followed by the decoded `index` bytes. The prefix keeps a signature over anything else from passing as an index signature. The app checks the signature over the exact bytes before it parses the index, so there is no canonical-JSON question.
- `keyID` is the first 8 bytes of SHA-256 of the raw 32-byte public key, as 16 lowercase hex characters. It only picks a key; trust comes from the key itself.

The decoded **index**:

```json
{
  "format": 1,
  "serial": 42,
  "packs": [
    { "id": "notes-extras", "name": "Notes extras", "author": "Jane Doe", "version": "1.2.0",
      "description": "Pin, lock and move notes by voice.",
      "bundleIDs": ["com.apple.Notes"],
      "url": "https://packs.example.org/notes-extras-1.2.0.json",
      "sha256": "<64 lowercase hex>" }
  ]
}
```

`RegistryIndex.parse` (Core) rejects, naming the first rule broken: an envelope over 1 MiB, invalid JSON, a missing or unknown key at any level, `format` other than 1, a bad base64 field, an unknown `keyID`, a signature that fails, `serial` not a non-negative integer, more than 1,000 packs, a duplicate `id`, an entry whose `id`, `name`, `author`, `bundleIDs` break NH-80's pack rules, `description` over 300 characters or with a control character, a `version` that isn't 1 to 4 dot-separated numbers (`1`, `1.2`, `1.2.0`, each up to 6 digits), a `url` that isn't `https` with a public host (NH-80's `open_url` host rule, reused, no user or password, up to 2048 characters), or a `sha256` that isn't 64 lowercase hex. One bad entry rejects the whole index, as one bad command rejects a whole pack in NH-80.

### Versions

`PackVersion` compares dot-separated numbers numerically, missing parts as 0 (`1.2` = `1.2.0` < `1.10`). Registry versions must be numeric (above). An installed pack whose version isn't numeric (NH-80 allows any 20 characters) shows "installed from a file, can't compare" and is never offered an update; the user can remove it and install from the registry.

## Trust: where the signing key comes from

- **Keys the app trusts.** `PackRegistry.defaultKeys` in Core: a list of `(keyID, publicKey)` constants, used only for the default registry URL. It ships **empty**, because no registry exists yet (see the next section). A custom registry in `config.json` must bring its own key in `packRegistryKey` (base64 of the 32-byte public key); only that key is trusted for it, and the default keys never vouch for another registry. A registry with no trusted key is shown as "Registry has no key, set packRegistryKey" and nothing is fetched.
- **Making a key.** `nohands-cli registry keygen <path>` writes a new Ed25519 private key to `<path>` (raw 32 bytes, base64, mode 600, refused if the file exists or is a symlink) and prints the public key and its `keyID`. The private key never goes in this repo, `config.json`, the app or the log. The registry's owner keeps it off any server, ideally offline.
- **Signing.** `nohands-cli registry sign <index.json> --key <path>` checks the index with `RegistryIndex.parse`'s entry rules, checks each listed pack file it can read locally if `--packs <dir>` is given (hash and NH-80 validator), and prints the envelope. Publishing is: write or update `index.json`, bump `serial`, sign, upload the envelope and the pack files.
- **Rotation.** `defaultKeys` holds up to two keys, so rotation is: ship an app release that trusts the old and the new key; start signing with the new key; a later release drops the old one. A custom registry rotates by the user changing `packRegistryKey`.
- **Revocation.** A key is revoked by an app release that removes it from `defaultKeys` (or, for a custom registry, by the user changing `packRegistryKey`). There is no remote revocation: an app that hasn't updated keeps trusting a stolen default key. That is the honest limit, and it is bounded: a stolen key can only offer validated pack data (key chords, menu items, `https` pages; NH-80's rules), every install and update still needs the user's yes on a screen that shows every phrase and action, and a downgrade is refused.
- **Rollback.** The app remembers the highest `serial` it has accepted per registry URL in `~/.config/nohands/registry-state.json` (600, `ConfigFile`'s private-file steps) and refuses a lower one ("Registry is older than one already seen, nothing installed"). This stops a replayed old index from hiding a newer pack version. The file holds only URLs and integers.

## The default registry URL (decision for the user)

The ticket does not name a host, and none exists. The app ships with the placeholder constant

```swift
public static let defaultURLPlaceholder = "https://registry-not-chosen.invalid/index.json"
```

in `PackRegistry` (Core). `.invalid` is a reserved name that never resolves, and the app treats any `.invalid` host as **no registry set**: the menu shows "Registry: none set", Browse shows "No pack registry yet, set packRegistryURL in config", and nothing is fetched. **The user must decide** the real default URL and generate its key; until then the feature works only with a custom registry in `config.json`. Replacing the constant and filling `defaultKeys` is a one-line follow-up once those exist.

## Config

| Key | Default | Values |
|---|---|---|
| `packRegistryURL` | the placeholder above (none set) | an `https` URL with a public host, no user or password; `""` turns the registry off |
| `packRegistryKey` | none | base64 Ed25519 public key; required for any URL other than the default |

A bad `packRegistryURL` (not `https`, a private host) turns the registry off and the menu says why ("Registry URL must be https"), as the bad-Ollama-URL check falls back. Neither key is a secret. `AppConfig` parses them; the URL check is a Core function with a table-driven test.

## Fetching (`PackFetcher` in NoHandsMac)

The only new file that does network I/O. It owns its `URLSession` (passed in, so tests use the existing `HTTPStub`):

- `URLSessionConfiguration.ephemeral`: no cookies, cache, credential storage or URL cache. System proxy settings apply.
- Each request is a `GET` of the index or pack URL with fixed headers only: `User-Agent: NoHands-packs/1`, `Accept: application/json`. No query added, no body, no transcript, config, app or OS version, identifier or installed-pack list. The system may still add `Accept-Encoding` and `Accept-Language`; the registry host sees the Mac's IP address.
- Timeout 10 s per request, 30 s per fetch. Size cap read as the bytes arrive: 1 MiB + 1 byte for the envelope, `PackFile.maxBytes` + 1 for a pack; over the cap, it stops and refuses.
- Redirects: at most 3, each checked by `PackFetcher.allowsRedirect(to:)`: `https` and the same public-host rule as the URL. Anything else cancels the fetch.
- A status other than 200 refuses.

Install and update (menu or CLI), in this order, with no write anywhere under `packs/` until the last step:

1. Fetch the envelope; `RegistryIndex.parse` with the trusted key; check `serial` against `registry-state.json`.
2. Pick the entry. Refuse if the installed version is the same ("Already installed") or newer ("Older than installed, not installed").
3. Fetch the pack bytes into memory (at most 64 KiB, so no temp file is needed for the download itself); `RegistryIndex.verifyPack(bytes, entry)` (Core) checks SHA-256 against `sha256`, runs `PackFile.parse`, and checks the pack's `id`, `version` and `bundleIDs` equal the entry's.
4. Show the install summary (new pack) or the update screen (below) and ask.
5. On yes only: `PackStore.install(bytes)`, which validates again and writes with a temp file and rename (NH-80). Then record the `serial`.

Nothing is fetched after the yes, so what the user approved is exactly what is written. A failure at any step leaves installed packs and their on/off state untouched.

Failures say what to do next, in the row or on stderr: "No connection, installed packs still work", "Timed out, installed packs still work", "Registry signature failed, nothing installed", "Registry is older than one already seen, nothing installed", "Download didn't match the registry, nothing installed", "Pack failed checks: <reason>, nothing installed", "Older than installed, not installed", "Registry URL must be https".

## Updates (`PackDiff` in Core)

An update shows the summary of the new version plus what changed against the installed one: phrases added, removed, and phrases whose actions changed (with old and new action lines, `PackSummary.commandLines` style), apps added and removed, `open_url` hosts added and removed, `open_app` names added and removed. Everything printed goes through `PackSummary.printable`. It needs a yes again. An update keeps the pack's install order and on/off state (NH-80's in-place replace).

## Entry points

- **Menu bar, Packs submenu** gains, above the installed list: "Registry: <host>" (or "none set" or "off", greyed), **Browse…** and **Check for pack updates**.
- **Browse…** opens one small window: a list of the index's packs (name, version, author, description, apps; "installed", "update to 1.3.0" or "installed from a file" on installed ones) with an **Install** or **Update** button per row, and a status line. The index is fetched when the window opens and on its **Reload** button, never otherwise.
- **Check for pack updates** opens the same window with updatable packs first and the status line "2 updates" or "All packs up to date".
- **Install** / **Update** runs steps 3 to 5 and shows the summary in an alert whose default (Return) button is **Cancel** and whose other button is **Install** or **Update**, so a stray "press return" never installs. A failure shows in that pack's row.
- `nohands-cli pack search [<words>]`: fetches the index and lists id, version, name, apps and installed state, filtered by words in id, name or description.
- `nohands-cli pack install <id>`: steps 1 to 5 with the NH-80 summary and `Install? [y/N]`.
- `nohands-cli pack update [<id>]`: one pack, or every installed pack with a newer version; for each, the diff and `Update? [y/N]`. No `--yes` on any of them.
- `nohands-cli registry keygen <path>` and `registry sign <index.json> --key <path> [--packs <dir>]` for publishers (above). They do no network I/O.

The CLI summary text moves from `PackCommands.swift` to a shared formatter both the CLI and the app's alert use, so the app's screen shows the same lines as `pack add`.

No voice phrase is added and none changes; `docs/voice-commands.md` is untouched. A voice user reaches Browse through the menu with the existing click and label commands.

## Keeping the fetcher away from commands

- No new `Action` case and no intent-schema kind: the decoder rejects anything the model could name for it, so neither the model nor a pack can ask for a fetch.
- `PackFetcher` has no shared or static instance. It is created only in the Packs menu action handlers (`AppDelegate` and the Browse window) and in `nohands-cli`'s `pack search|install|update`. `VoicePipeline`, `TaskRunner` and `ActionExecutor` are not given one and have no initializer parameter for one.
- **Source-scan test** (`NoHandsMacTests`, reads `Sources/` through `#filePath` as `TaskScenarioTests` already does):
  - The only files that mention `PackFetcher` are an allowlist: `PackFetcher.swift`, the Browse window file, `AppDelegate.swift` and `nohands-cli/PackCommands.swift`.
  - `VoicePipeline.swift`, `CommandGrammar.swift`, `ModeMachine.swift`, `TaskRunner.swift` and every `ActionExecutor*.swift` mention none of `PackFetcher`, `URLSession`, `URLRequest`, `RegistryIndex` or `PackRegistry`.
  - No file in `Sources/NoHandsCore` mentions `URLSession`, `URLRequest`, `NWConnection`, `import Network` or `CFNetwork`.
  - `URLSession` appears only in an allowlist of files (today's Claude, Ollama, rewrite and connection-check files plus `PackFetcher.swift`), so a new network call site anywhere fails the test until someone adds it on purpose.
  The allowlist form catches a new caller, which a "these files don't call it" list alone would miss. It is a text check, so it can be dodged on purpose; it guards against accidents, and review covers the rest.
- Installed packs load through `PackStore.loadEnabled` (disk only, unchanged), so with the network off, or the registry off in config, every installed pack works.

## Tests

- Core, table-driven: `RegistryIndex.parse` accepts a good signed envelope and rejects each rule (bad JSON, missing key, unknown key, bad base64, unknown `keyID`, signature over different bytes, signature without the prefix, bad version, `http` pack URL, private host, duplicate id, oversize); `verifyPack` rejects a hash mismatch, a validator failure and an id, version or bundle ID mismatch; `PackVersion` order including `1.2` = `1.2.0` < `1.10` and a downgrade refused; `serial` rollback refused; the registry URL check (`https`, private host, `.invalid` = none set, `""` = off); `PackDiff` reports added, removed and changed phrases, apps and hosts.
- Mac, with `HTTPStub` and a temp `PackStore`: a good install writes the pack only after verification; a hash mismatch, a bad signature and a `serial` rollback leave `packs/` unchanged; an `http` URL is refused without a request; an off-`https` or private-host redirect is refused; a body over the cap is refused; a timeout leaves installed packs and on/off state untouched; requests carry only the fixed headers and no body.
- The source-scan test above.
- `swift test` needs no network: every fetch in tests goes to `HTTPStub`. Test keys are generated in the test with CryptoKit; no private key is committed.
- Manual (in the PR): sign a small index with `registry keygen` and `registry sign`, serve it over `https` (for example a GitHub Pages or gist raw URL), set `packRegistryURL` and `packRegistryKey`, browse, install a pack, say its phrase with Wi-Fi off, publish a new version and update it, try an older version and see it refused, set `packRegistryURL` to `""` and see installed packs still work.

## Docs

- `docs/app-packs.md`: a "Get packs from a registry" section (Browse, the CLI commands, what is checked, failures) and a "Publish a registry" section (envelope and index format, keygen, sign, rotation and revocation, the serial rule). The ticket says `README.md`; NH-119 moved pack reference material to `docs/app-packs.md`, so it goes there and the README's App packs line mentions the registry.
- `docs/cli.md`: rows for `pack search`, `pack install`, `pack update`, `registry keygen`, `registry sign`.
- `docs/configuration.md`: `packRegistryURL` and `packRegistryKey`.
- `docs/privacy.md` and the README Privacy section: a line that the app reaches the network for packs only when you open Browse, check for updates or run a `pack` registry command; the request carries only the index or pack URL and fixed headers; the registry host sees your IP address; nothing is fetched in the background.

## Calls I made

- **The default registry URL is a placeholder that means "none set"** (`https://registry-not-chosen.invalid/index.json`) and `defaultKeys` ships empty. You need to pick the host and generate the key; until then only a custom registry in `config.json` works.
- **No remote key revocation.** A key is revoked by an app release (or by changing `packRegistryKey`). Bounded by validated pack data, the yes screen and the downgrade rule. A signed expiry date was left out so a hand-run registry doesn't have to re-sign on a schedule.
- **A custom registry must bring its own key** in `packRegistryKey`; the built-in keys only cover the default URL. A registry with no key fetches nothing.
- **Publisher tools in the CLI**: `registry keygen` and `registry sign` (not in the ticket), so the format can be produced without outside tooling. The private key is a file the publisher keeps; never in the repo or config.
- **Rollback guard**: a per-registry highest `serial` kept in a new `~/.config/nohands/registry-state.json`. The ticket didn't ask for it.
- **One signed envelope** (base64 index plus signature, domain-separated) rather than a detached signature file or canonical JSON.
- **Pack downloads are held in memory** (at most 64 KiB) and written to `packs/` only through `PackStore.install`'s temp-file-and-rename after the yes. The ticket says "downloads go to a temp file first"; the effect it wants, nothing in `packs/` before every check passes, holds.
- **The pack must match its index entry** in `id`, `version` and `bundleIDs`, not only the hash, so Browse can't show one thing and install another.
- **Registry versions must be numeric** (`1.2.0`); an installed pack with a non-numeric version is never offered an update.
- **The Browse window and update check are new app UI**; NH-80 kept install CLI-only. The confirmation alert's default button is Cancel so a stray "press return" never installs.
- **No voice phrase** for Browse or updates, so nothing spoken can start a fetch; voice users use the menu.
- **Registry and pack URLs use NH-80's public-host rule**, so a registry can't point the fetcher at `localhost` or the local network. Names are not looked up.
- Limits are mine: envelope 1 MiB, 1,000 packs, description 300 characters, 10 s per request, 30 s per fetch, 3 redirects.
- Registry docs go in `docs/app-packs.md`, not `README.md`, after NH-119.
- `docs/agents/project.md`'s invariant is not edited (see "What changes for the repo invariant").
