# As-built: Pack marketplace

**Shipped:** in PR #168
**Ticket:** NH-85
**Spec:** [2026-11-16-nh-85-pack-marketplace-design.md](../specs/2026-11-16-nh-85-pack-marketplace-design.md)

## Differs from the spec

- A registry set in `config.json` with no `packRegistryKey` fetches nothing and the menu and CLI say "Registry has no key, set packRegistryKey in config.json" (`RegistryStatus`). The spec only said this for a missing key on a custom URL in the menu; the default placeholder URL still reads "none set".
- Registry entry `version` is capped at 20 characters, as pack files are, so a 4-part version of 6-digit parts is rejected. An entry whose `id` is a built-in pack id is rejected too.
- `PackFetcher` takes no `PackStore`; the caller installs after the yes. `FetchError` has two cases the spec has no sentence for: "Registry sent something unusable (...)" and "Couldn't save the registry's version".
- The fetcher records a serial only when it is higher than the one stored, and refuses a lower one; the same serial is accepted.
- The `PackFetcher` allowlist in `NetworkBoundaryTests` is `PackFetcher.swift`, `PackBrowser.swift` and `PackCommands.swift`. `AppDelegate.swift` only uses `PackBrowserController`, and `RegistryCommands.swift` does no fetching.
- `registry sign --packs <dir>` skips a listed pack whose file is not in the directory and fails only on a file that is there and wrong. `registry keygen` refuses a key file readable by other users when signing.
- The Browse window and the install alert pause listening while open (as the Remove alert does), so they are clicked, not spoken.
- Registry docs also add a failure table to `docs/app-packs.md`.
