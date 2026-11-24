# NH-150 plan: exact pack menu steps and two guard gaps

Spec: `docs/superpowers/specs/2026-11-16-nh-150-exact-menu-steps-design.md`. Test: `swift test`; typecheck: `swift build`.

1. **Action flag.** `case menuItem(String, exact: Bool = false)`; fix every match site the compiler flags. `PackFile` parse returns `exact: true`; encode unchanged. Executor presses with `exactOnly: exact || labelSnapshot != nil`, same for the agent-desktop fallback title check.
2. **ShortcutGuard negation.** `IrreversibleGuard.goalVerbs` becomes internal; `ShortcutGuard.blocked` and `allowsClose` use it. Table test.
3. **Lookalikes.** `MenuMatch.isLookalike` (NFKC + Cyrillic/Greek/Armenian table; only letters count); `firstMatch` skips lookalike entries; executor fallback rejects them; `PackFile` rejects a lookalike `menu_item` title. Table test, including French, Russian, Japanese titles as non-lookalikes.
4. **Exact-only test**, `docs/app-packs.md` `menu_item` row update.
