# NoHands: Voice-Only macOS Control — Design Spec

**Date:** 2026-11-04
**Status:** Draft, written from the user's brief without a brainstorming session. Decisions marked *(assumption)* were made by the planner and are the ones most worth challenging.

## 1. Goal

A menu-bar macOS app that operates the whole computer by voice alone (dictation, keys, mouse, natural-language commands), fast enough to replace a keyboard and mouse. Targets macOS 14.5+, Apple Silicon. Only the LLM path uses the network.

## 2. Non-goals

- Wake word. The app always listens; "go to sleep" / "wake up" gate it (optional attention word, NH-12).
- Vision fallback (shipped later, NH-41), LLM polish of dictation, custom vocabulary, Intel, notarization.

## 3. Architecture

Mic (16 kHz mono, echo cancellation unless `echoCancellation` is false) → Silero VAD → Parakeet TDT v2 → mode machine → dictation formatter, or command grammar (unmatched text goes to the Claude resolver) → action executor.

- **One vocabulary.** `Action` is the enum every stage produces or consumes. A new capability adds a case in grammar, LLM decoder and executor.
- **Grammar first, LLM second.** The common path is local (< 1 ms) and works offline. An untypeable `spell` phrase is rejected, not sent to the LLM.
- **Targets resolve late.** `numbered(42)` means grid cell or label, by which overlay is visible.

## 4. Modes and menu

- `command` (default): every utterance is a command (with `attentionWord` set, only those starting with it).
- `dictation`: everything is typed except "stop dictating", "command mode", "scratch that", "delete word".
- `sleep`: everything ignored except "wake up".

The menu bar shows `CMD` / `DICT` / `ZZZ`. The menu has Start at Login, Status Bar, Model (`Claude|Local|Off`, no restart, saves `intentBackend`), Open config.json…, Recent commands (last 50) and View Logs…. The log is `~/.config/nohands/command-log.json`, local only, mode 600.

## 5. Command grammar and dictation

Input is lowercased and stripped of `.,!?`. In a number slot "to"/"too" mean 2 and "for" means 4. Phrases are in the README.
- `spell` takes letters, NATO words, digits and symbol words; one unknown token or a dangling `capital` types nothing.
- `find <words>` and `scroll to <words>` find on the page; bare `find` is ⌘F.
- `move` defaults to 50 px; `scroll` to 5 lines, max 50. `zoom <n>` puts a fresh 10×8 grid inside cell n.
- Dictation: spoken punctuation becomes characters; capitalize the utterance start and after `.`, `?`, `!`, newline; add a leading space between utterances when both sides touch words.

## 6. Mouse targeting

- **Grid:** 10×8 on the screen with the pointer, cells 1–80; zoomed cells are about 15×12 px.
- **Labels:** numbered badges on actionable accessibility elements of the frontmost app. Depth limit 12, budget 150 ms and 2000 nodes (browser: 600 ms and 5000, web area first), deduplicated by frame, capped at 200.
- **By name:** `click <name>` matches title, description or value: exact, then prefix, then contains.
- **Typing:** `CGEvent` Unicode events, at most 20 UTF-16 units per chunk, split on `Character` boundaries so emoji are never torn. No clipboard use.

## 7. LLM intent resolution

- **Provider:** Anthropic Messages API over raw HTTPS (no Swift SDK), `anthropic-version: 2026-10-21`, beta `server-side-fallback-2026-07-01`.
- **Model:** default `claude-haiku-5-5` at effort `low` (NH-95, for cost); `intentModel` and `intentEffort` override. Haiku has no fallback, so a declined request fails.
- **Request:** cacheable `system` prompt; one user turn with frontmost app, mode, up to 60 visible element titles with label numbers, then the transcript. `max_tokens` 2048. Output is forced to a JSON schema.
- **Schema:** `{intent, status, actions}`, all required; `actions.items` is an `anyOf` of 13 closed branches, every field required (`""` or `0` means omitted). Anthropic rejects one flat 32-field object and one branch per kind (NH-104 spec). Ollama still gets flat `ActionJSON`. No recursion or numeric constraints.
- **Prompt rules:** fewest actions; ambiguous requests return `ignore`.
- **Failures:** timeout 4 s. Any refusal, error or undecodable reply gives no actions and "didn't catch that". A missing key disables the path with a one-time notice.

## 8. Configuration

`~/.config/nohands/config.json`, all keys optional (the README lists them); `ANTHROPIC_API_KEY` wins over `anthropicAPIKey`. Defaults: `asrModelVersion` `v2` (English; `v3` multilingual), `silenceMs` 1000 (raised from 350 to allow pauses mid-command), `earlySilenceMs` 350 (ends a complete grammar command or "stop" early; 0 = off), grid 10×8, `moveStepPx` 50, `scrollStepLines` 5.

## 9. Latency budget (grammar path)

- End of speech 350 ms (`earlySilenceMs`; others wait `silenceMs`). Parakeet on ≤ 5 s, M1 Pro: ≤ 250 ms. Grammar plus executor ≤ 20 ms.
- Browser `show numbers` and `click <name>` add up to about 450 ms, plus a 600 ms settle the first time a Chromium browser is walked.
- **Total ≤ 650 ms**. The LLM path adds 1–3 s.

## 10. Permissions and packaging

`scripts/bundle.sh` builds `NoHands.app` (`LSUIElement`, `dev.nohands.app`), signed with `$CODESIGN_IDENTITY` (default ad-hoc). Accessibility trust follows the signature, so ad-hoc builds need re-granting each rebuild.
