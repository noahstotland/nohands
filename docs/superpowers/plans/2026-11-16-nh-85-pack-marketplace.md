# Pack marketplace Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Browse, install and update app packs from a signed registry, only when the user asks, with every fetch inside one `NoHandsMac` type.

**Architecture:** Pure registry logic (envelope and index parsing, Ed25519 verify with CryptoKit on given bytes, versions, diff) in `NoHandsCore`. One `PackFetcher` in `NoHandsMac` does all network I/O and hands verified bytes to NH-80's `PackStore.install` after a yes. UI is the Packs menu, a Browse window and `nohands-cli pack search|install|update` plus publisher commands `registry keygen|sign`.

**Tech Stack:** Swift 6 strict concurrency, CryptoKit, URLSession (stubbed in tests with `Tests/NoHandsMacTests/HTTPStub.swift`).

**Spec:** `docs/superpowers/specs/2026-11-16-nh-85-pack-marketplace-design.md` (read it first; it fixes every value below). NH-80 as-built: `docs/superpowers/as-built/2026-11-15-nh-80-installable-packs.md`.

## Global Constraints

- Swift 6 strict concurrency: no `@unchecked Sendable`, no `@preconcurrency`. (The existing test `StubProtocol` already carries one; do not add new ones.)
- `NoHandsCore` imports no AppKit, no network API (`URLSession`, `URLRequest`, `Network`, `CFNetwork`). CryptoKit is allowed.
- Network I/O only in `PackFetcher.swift`. `PackFetcher` is created only in the Packs menu handlers, the Browse window and `nohands-cli` `pack search|install|update`. `VoicePipeline`, `CommandGrammar`, `ModeMachine`, `TaskRunner`, `ActionExecutor*` never mention it.
- No new `Action` case, no intent-schema kind, no voice phrase. Do not edit `docs/agents/project.md`.
- Requests: `GET` only, headers `User-Agent: NoHands-packs/1` and `Accept: application/json`, no query, no body. Timeout 10 s per request, 30 s per fetch, at most 3 redirects, each `https` with a public host. Caps: envelope 1 MiB, pack `PackFile.maxBytes`.
- Signature input: `"nohands-pack-index-v1\n"` + decoded index bytes. `keyID` = first 8 bytes of SHA-256 of the raw 32-byte public key, 16 lowercase hex.
- Nothing under `packs/` is written before every check passes and the user says yes; install goes through `PackStore.install`. Nothing is fetched after the yes.
- No `--yes` flag anywhere. The app's confirm alert has Cancel as the default button.
- Default registry constant is the placeholder `https://registry-not-chosen.invalid/index.json`; any `.invalid` host means "none set". `defaultKeys` ships empty. Never commit a private key; tests generate keys with CryptoKit.
- Tests: `AGENTS.md` § Testing (table-driven, one per rule; test lines not above feature lines). `swift test` needs no network.
- Commit style: `feat:` / `docs:`, ending with the attribution line from the session reminder.

## Review Focus

- A registry URL with userinfo, a private or IP host, or `http`: refused before any request (test in Task 1 table and Task 3).
- A pack whose hash is right but whose `id`/`version`/`bundleIDs` differ from its index entry: refused (Task 1).
- Same-version and older-version entries: "Already installed" / "Older than installed", nothing written (Task 3).
- Installed pack with a non-numeric version: never offered an update, no crash (Task 1 `PackVersion`, Task 4 search output).
- Replayed old index (lower `serial`): refused, state file untouched (Task 3).

---

### Task 1: Core registry logic

**Files:**
- Create: `Sources/NoHandsCore/PackRegistry.swift` (URL check, defaults, key ids), `Sources/NoHandsCore/RegistryIndex.swift` (envelope/index parse, `verifyPack`), `Sources/NoHandsCore/PackVersion.swift`, `Sources/NoHandsCore/PackDiff.swift`
- Test: `Tests/NoHandsCoreTests/RegistryIndexTests.swift`, `Tests/NoHandsCoreTests/PackDiffTests.swift`

**Interfaces:**
- Produces:
  - `struct PackVersion: Comparable, Sendable { init?(_ s: String); static func < }` (1 to 4 numeric parts, up to 6 digits, missing = 0).
  - `enum PackRegistry { static let defaultURLPlaceholder: String; static let defaultKeys: [TrustedKey]; struct TrustedKey { keyID: String; publicKey: Data }; static func keyID(of publicKey: Data) -> String; enum Setting: Equatable { case none, off, url(URL), invalid(String) }; static func setting(urlString: String?) -> Setting; static func trustedKeys(url: URL, customKey: String?) -> [TrustedKey]; static func signingInput(_ index: Data) -> Data }` (`urlString` nil = default placeholder = `.none`; `""` = `.off`; `invalid` carries the user-facing reason like "Registry URL must be https").
  - `struct RegistryEntry: Equatable, Sendable { id, name, author, version, description: String; bundleIDs: [String]; url: URL; sha256: String }`; `struct RegistryIndex: Sendable { serial: Int; packs: [RegistryEntry]; static func parse(envelope: Data, trusting: [PackRegistry.TrustedKey]) throws(RegistryError) -> RegistryIndex; static func verifyPack(_ bytes: Data, against: RegistryEntry) throws(RegistryError) -> AppPack }`; `struct RegistryError: Error, Equatable, Sendable { let reason: String }`.
  - `enum PackDiff { static func lines(old: AppPack, new: AppPack) -> [String] }`: added/removed/changed phrases (changed shows old and new action lines via `PackSummary` command-line style), apps, `open_url` hosts, `open_app` names added/removed; every string through `PackSummary.printable`; empty array when nothing differs.

- [ ] **Step 1: Failing tests.** `RegistryIndexTests` builds envelopes in-test with `Curve25519.Signing.PrivateKey`. Table `rejects`: bad JSON, missing key, unknown key, bad base64, unknown keyID, signature over different bytes, signature without the domain prefix, oversize (> 1 MiB), `format` 2, bad `version` ("1.x"), `http` pack URL, private/IP/`localhost` host, userinfo in URL, duplicate id, bad `sha256`, bad id; one case accepts a good envelope. `verifyPack` table: hash mismatch, `PackFile.parse` failure, id mismatch, version mismatch, bundleIDs mismatch rejected; good accepted. `PackVersion`: `1.2 == 1.2.0`, `1.2.0 < 1.10`, `"1.x"` and `"1.2.3.4.5"` nil. `PackRegistry.setting`: nil → `.none`, `""` → `.off`, placeholder → `.none`, `http://x.org/` / `https://localhost/` / `https://user@x.org/` → `.invalid`, `https://packs.example.org/i.json` → `.url`. `trustedKeys`: default URL uses `defaultKeys`; other URL uses only the custom key (base64 32 bytes), empty when missing or malformed. `PackDiffTests`: added, removed, changed phrase, added app, added host, identical → `[]`.
- [ ] **Step 2: Run** `swift test --filter RegistryIndexTests` and `--filter PackDiffTests`: FAIL (types missing).
- [ ] **Step 3: Implement** the Interfaces above. Reuse NH-80's public-host rule: find the host check inside `PackFile.swift` (`isLocalHost` and the `open_url` host rules) and expose it as an internal `PackFile.isPublicHTTPSURL(_:) -> Bool` (https, host rule, no userinfo, length ≤ 2048) instead of copying it. Verify the signature before parsing the index; parse with `JSONSerialization`-style strict key checks as `PackFile` does.
- [ ] **Step 4: Run** the same filters: PASS; run `swift build` clean.
- [ ] **Step 5: Commit** `feat(core): registry index, signature and version checks (NH-85)`.

### Task 2: Config keys

**Files:**
- Modify: `Sources/NoHandsCore/AppConfig.swift` (`packRegistryURL: String?`, `packRegistryKey: String?`, CodingKeys, decode as the other optional strings; nothing else changes)
- Test: `Tests/NoHandsCoreTests/AppConfigTests.swift` (extend the existing table-driven config test if there is one; else a small new table)

**Interfaces:**
- Consumes: `PackRegistry.setting`, `PackRegistry.trustedKeys` (Task 1).
- Produces: `AppConfig.packRegistry: PackRegistry.Setting` and `AppConfig.packRegistryTrustedKeys: [PackRegistry.TrustedKey]`.

- [ ] **Step 1: Failing test:** missing keys → `.none` and default keys; `"packRegistryURL": ""` → `.off`; custom https URL with and without `packRegistryKey`; `http` URL → `.invalid`; invalid JSON still falls back to defaults.
- [ ] **Step 2: Run** `swift test --filter AppConfig`: FAIL.
- [ ] **Step 3: Implement** the two stored keys and the two computed properties.
- [ ] **Step 4: Run:** PASS.
- [ ] **Step 5: Commit** `feat(core): packRegistryURL and packRegistryKey config (NH-85)`.

### Task 3: PackFetcher and the rollback state

**Files:**
- Create: `Sources/NoHandsMac/PackFetcher.swift`, `Sources/NoHandsMac/RegistryState.swift`
- Test: `Tests/NoHandsMacTests/PackFetcherTests.swift`, `Tests/NoHandsMacTests/NetworkBoundaryTests.swift`

**Interfaces:**
- Consumes: Task 1 and 2 types, `PackStore`, `ConfigFile` private-file helpers.
- Produces:
  - `struct RegistryState: Sendable { init(path: URL = default ~/.config/nohands/registry-state.json); func serial(for url: URL) -> Int?; func record(serial: Int, for url: URL) throws }` (600, `ConfigFile.replaceFile`; a corrupt file reads as empty).
  - `struct PackFetcher: Sendable { init(registry: URL, trusting: [PackRegistry.TrustedKey], session: URLSession, state: RegistryState); func fetchIndex() async throws(FetchError) -> RegistryIndex; func fetchVerifiedPack(_ entry: RegistryEntry) async throws(FetchError) -> (data: Data, pack: AppPack); static func allowsRedirect(to: URL) -> Bool; static func session() -> URLSession }` where `session()` is ephemeral with no cache/cookies/credentials and 10 s request / 30 s resource timeouts. `FetchError: Error, Equatable` has a `userMessage: String` using the spec's exact failure sentences (no connection, timed out, signature failed, older than seen, download mismatch, pack failed checks with reason, registry URL must be https). `fetchIndex` records the serial only after verification and refuses a lower one than recorded. Install/update decision helper: `static func decision(entry: RegistryEntry, installedVersion: String?) -> Decision` with `.install, .update, .alreadyInstalled, .older, .cannotCompare`.

- [ ] **Step 1: Failing tests** (stub session via `URLSessionConfiguration` with `StubProtocol`, temp dirs for state and `PackStore(postsChanges: false)`): good fetch returns index and records serial; bad signature, lower serial, over-cap body (1 MiB + 1), non-200, timeout (`URLError.timedOut`), no-connection each map to the right `userMessage` and write nothing; `http` registry URL throws with zero requests recorded; off-https redirect and private-host redirect refused; every recorded request has exactly the two fixed headers, `GET`, no body, no query; `fetchVerifiedPack` refuses hash mismatch and a body over `PackFile.maxBytes`; `decision` table (new, newer, same, older, non-numeric installed). Core of the invariant: after each failure `PackStore.list()` is unchanged. `NetworkBoundaryTests` (source scan via `#filePath`, as `TaskScenarioTests` does): `PackFetcher` is mentioned only in an allowlist (`PackFetcher.swift`, the Browse window file, `AppDelegate.swift`, `nohands-cli/PackCommands.swift`, `nohands-cli/RegistryCommands.swift`); `VoicePipeline.swift`, `CommandGrammar.swift`, `ModeMachine.swift`, `TaskRunner.swift`, every `ActionExecutor*.swift` mention none of `PackFetcher`, `URLSession`, `URLRequest`, `RegistryIndex`, `PackRegistry`; no `NoHandsCore` file mentions `URLSession`, `URLRequest`, `NWConnection`, `import Network`, `CFNetwork`; `URLSession` appears only in an allowlist of the files that use it today plus `PackFetcher.swift` (list them from `grep -l URLSession Sources`).
- [ ] **Step 2: Run** `swift test --filter PackFetcherTests` and `--filter NetworkBoundaryTests`: FAIL (the scan passes only once the allowlist matches reality; write it first from the grep).
- [ ] **Step 3: Implement** `PackFetcher` with a streaming read through `URLSession.bytes(for:)` stopping at the cap, a `URLSessionTaskDelegate` redirect check calling `allowsRedirect`, and the 30 s overall deadline via a task group or `withTimeout`-style race. `RegistryState` as described.
- [ ] **Step 4: Run** both filters, then full `swift test`: PASS.
- [ ] **Step 5: Commit** `feat(mac): PackFetcher with signed-index checks (NH-85)`.

### Task 4: CLI commands and shared summary text

**Files:**
- Create: `Sources/NoHandsMac/PackSummaryText.swift` (move `summaryText` from `Sources/nohands-cli/PackCommands.swift`, public), `Sources/nohands-cli/RegistryCommands.swift`
- Modify: `Sources/nohands-cli/PackCommands.swift` (`search`, `install`, `update`), `Sources/nohands-cli/main.swift` (route `registry`; update usage text)
- Test: `Tests/NoHandsMacTests/PackSummaryTextTests.swift` (moved text still renders the same lines); signing round trip in `Tests/NoHandsCoreTests/RegistryIndexTests.swift` or a Mac test of `RegistrySigner`

**Interfaces:**
- Produces: `PackSummaryText.text(_ s: PackSummary, id: String, shadowed: [PackSet.Shadowed], replaces: PackStore.Entry?) -> String` (public, in NoHandsMac); `RegistrySigner.keygen(to path: String) throws -> (publicKeyBase64: String, keyID: String)` and `RegistrySigner.sign(indexJSON: Data, privateKey: Data) throws -> Data` (envelope) in NoHandsMac (no network); CLI: `pack search [words]`, `pack install <id>`, `pack update [id]`, `registry keygen <path>`, `registry sign <index.json> --key <path> [--packs <dir>]`.

- [ ] **Step 1: Failing tests:** `RegistrySigner.sign` output parses with `RegistryIndex.parse` under the matching key and fails under another; `keygen` writes mode 600, refuses an existing file and a symlink; `--packs` check path rejects a hash mismatch (test the function behind it, not the CLI).
- [ ] **Step 2: Run** the new filters: FAIL.
- [ ] **Step 3: Implement.** `pack install`/`update` follow spec steps 1 to 5: print `PackSummaryText` (update also prints `PackDiff.lines`), ask `Install? [y/N]` / `Update? [y/N]`, install only on `y`/`yes` through `PackStore.install`, then `RegistryState` already recorded the serial. `search` filters by words in id, name, description and marks installed state, "update to X" or "installed from a file". Failures print `FetchError.userMessage` and exit 1. When the registry is `.none`/`.off`/`.invalid`, print the reason and exit 1 without fetching. Keep CLI code thin.
- [ ] **Step 4: Run** `swift test`; manually run `swift run nohands-cli registry keygen`/`sign` against a temp index to see the envelope.
- [ ] **Step 5: Commit** `feat(cli): pack search, install, update and registry keygen, sign (NH-85)`.

### Task 5: App menu and Browse window

**Files:**
- Create: `Sources/NoHands/PackBrowser.swift` (window with list, status line, Reload, per-row Install/Update)
- Modify: `Sources/NoHands/AppDelegate.swift` (Packs submenu: "Registry: <host>" / "none set" / "off" greyed line, "Browse…", "Check for pack updates"; `reloadPacks()` unchanged otherwise)
- Test: none (UI; spec lists it as manual). Keep decision logic in `PackFetcher.decision` (Task 3, already tested).

**Interfaces:**
- Consumes: `AppConfig.packRegistry`, `.packRegistryTrustedKeys`, `PackFetcher`, `PackSummaryText`, `PackDiff`, `PackStore`.

- [ ] **Step 1: Implement** the window: fetch the index when it opens and on Reload only; rows show name, version, author, description, apps and installed state; Install/Update fetches and verifies the pack, shows an `NSAlert` with the summary (and diff for an update) whose default button is **Cancel** and second button **Install**/**Update**, installs only on the second; errors show in the row via `FetchError.userMessage`. "Check for pack updates" opens the same window listing updatable packs first, status "N updates" or "All packs up to date". A `.none`/`.off`/`.invalid` registry shows its reason and fetches nothing. HUD/menu copy stays short.
- [ ] **Step 2: Run** `swift build` and `scripts/bundle.sh` (build only, no launch needed); confirm no AppKit in Core.
- [ ] **Step 3: Commit** `feat(app): Browse packs and check for updates from the Packs menu (NH-85)`.

### Task 6: Docs

**Files:** Modify `docs/app-packs.md` (sections "Get packs from a registry" and "Publish a registry": envelope and index format, keygen/sign, rotation, revocation limit, serial rule, failure messages), `docs/cli.md` (five rows), `docs/configuration.md` (two keys), `docs/privacy.md` and the README Privacy section (network only on Browse, update check and `pack search|install|update`; only fixed headers and the URL; registry host sees your IP; no background fetch), README App packs line mentions the registry.

- [ ] **Step 1: Write the docs** per the spec's Docs section. Plain language, no em dashes.
- [ ] **Step 2: Run** the doc links check if the repo has one (`grep -n "app-packs" README.md`); otherwise skip.
- [ ] **Step 3: Commit** `docs: pack registry, CLI rows, config keys and privacy (NH-85)`.

---

## Self-review

- Spec coverage: format, trust, default placeholder, config, fetcher limits, install order, updates diff, entry points, boundary scan, tests, docs are each in a task. Closeout docs (as-built, release note) are added at PR time per `open-pr`.
- Types: `PackRegistry.Setting`, `TrustedKey`, `RegistryEntry`, `FetchError`, `PackFetcher.decision` are defined once and used with the same names in Tasks 2 to 5.
