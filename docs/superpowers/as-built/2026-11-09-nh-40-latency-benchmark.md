# NH-40: A repeatable latency benchmark — As built

**Shipped:** in PR #TBD, with differences
**Ticket:** [NH-40](https://github.com/noahstotland/nohands/issues/40)
**Spec:** [design](../specs/2026-11-09-nh-40-latency-benchmark-design.md)

## Differs from the spec

- **A spoken "stop" prints `-> stop`, not `no match -> LLM`.** The grammar does not parse "stop" (the pipeline halts on it
  before the grammar sees it), so the spec's rule "reads as `nohands-cli parse` does" would have shown the stop phrase as
  a model call. The row uses `config.attentionGate.isStop`.
- **The measured pass is the latest close in the file by audio time,** not "the accepted early pass if there is one".
  For a one-utterance file the two are the same. When a pause splits a file, the last utterance is timed, which is what
  the spec's call 10 says, even when an earlier utterance closed early.
- **`LatencyStats.format(_:)` is public.** The per-file rows use the same millisecond formatting as the summary lines.
- **A file that throws prints `skipped: <error description>`,** a case the spec's list did not name.
- **File names are padded to the longest name** in the row, and actions print in Swift's debug form (as
  `nohands-cli parse` does).
- **FluidAudio's `[INFO]` log lines appear between the rows,** because the replay builds a fresh VAD for each file. They
  are not part of the table.

## First run

Synthesized speech, not recordings: `scripts/make-bench-audio.sh` (macOS `say`, voice Samantha, rate 180, 16 kHz 16-bit
mono), then `.build/debug/nohands-cli bench .build/bench-audio`. The ticket's recordings are still owed, so
`bench Tests/Fixtures/audio` exits asking for them. Synthesized speech has cleaner silence than a room, so real numbers
may differ.

- Mac: MacBookPro18,3 (MacBook Pro, Apple M1 Pro, 10 cores, 16 GB), macOS 14.5 (23F79).
- Build: debug (`swift build`), Parakeet v2 on cpuAndGPU.
- Config: `~/.config/nohands/config.json` is empty, so defaults: `silenceMs=1000`, `earlySilenceMs=350`, `asr=v2`.
  The attention word was ignored for the run.
- Model load plus two warm-up passes: 4373 ms, counted in no stage. The run took about one minute (the replay is paced to
  real time).
- Actions are shortened below (the `NoHandsCore.` prefix and `KeyChord` details left out).

```
silenceMs=1000 earlySilenceMs=350 asr=v2 attentionWord=ignored load=4373ms
click-forty-two.wav        close=early lag=320ms asr=148ms parse=0.02ms e2e=468ms utts=1 "Click 42" -> [click(numbered(42))]
click-pause-forty-two.wav  close=early lag=484ms asr=152ms parse=0.04ms e2e=636ms utts=1 "Click 42." -> [click(numbered(42))]
click-seven.wav            close=early lag=364ms asr=137ms parse=0.04ms e2e=501ms utts=1 "Click 7" -> [click(numbered(7))]
close-tab.wav              close=early lag=364ms asr=141ms parse=0.03ms e2e=505ms utts=1 "Close tab" -> [pressKey(command w)]
copy.wav                   close=early lag=308ms asr=133ms parse=0.02ms e2e=441ms utts=1 "Copy" -> [pressKey(command c)]
dictation-sentence.wav     close=full lag=1068ms asr=166ms parse=0.05ms e2e=1234ms utts=1 "Please write a short note to remind me to call the dentist tomorrow morning." -> no match -> LLM
go-back.wav                close=early lag=504ms asr=136ms parse=0.02ms e2e=640ms utts=1 "Go back." -> [pressKey(command [)]
go-to-sleep.wav            close=early lag=324ms asr=140ms parse=0.01ms e2e=464ms utts=1 "Go to sleep." -> [setMode(sleep)]
new-tab.wav                close=early lag=464ms asr=140ms parse=0.01ms e2e=604ms utts=1 "New tab" -> [pressKey(command t)]
next-tab.wav               close=early lag=344ms asr=142ms parse=0.04ms e2e=486ms utts=1 "Next tab" -> [pressKey(control tab)]
paste.wav                  close=early lag=348ms asr=134ms parse=0.01ms e2e=482ms utts=1 "Paste" -> [pressKey(command v)]
press-command-s.wav        close=early lag=320ms asr=130ms parse=0.04ms e2e=450ms utts=1 "Press Command S" -> [pressKey(command s)]
scroll-down-ten.wav        close=early lag=496ms asr=155ms parse=0.02ms e2e=651ms utts=1 "Scroll down 10." -> [scroll(down, amount: 10)]
scroll-up-five.wav         close=early lag=360ms asr=155ms parse=0.04ms e2e=515ms utts=1 "Scroll up 5" -> [scroll(up, amount: 5)]
stop.wav                   close=early lag=328ms asr=128ms parse=0.02ms e2e=456ms utts=1 "Stop." -> stop
wake-up.wav                close=early lag=564ms asr=137ms parse=0.02ms e2e=701ms utts=1 "Wake up." -> [setMode(command)]
summary: files=16 measured=16 skipped=0 early=15 full=1
lag        p50=360ms p95=1068ms
asr        p50=140ms p95=166ms
parse      p50=0.02ms p95=0.05ms
end-to-end p50=501ms p95=1234ms
```

Reading it:

- Fifteen of sixteen files close early, at about 350 ms of silence plus up to one 256 ms chunk of granularity. The one full
  close is the dictation sentence, which is not a command, so its p95 sets the p95 of every stage. Compare p50s.
- `click-pause-forty-two.wav` did not split: the 600 ms pause is shorter than `silenceMs`, and the early pass on "click"
  was not accepted, so the file is one utterance and closes early on "Click 42.".
- The lag column includes the VAD's chunk size (4096 samples, 256 ms), so values between 308 and 564 ms differ by
  where the true end falls in a chunk, not only by the early-close rule.

## Checks that ran

- `swift build`: clean. `swift test`: 451 tests pass (includes `LatencyStatsTests`), with no audio, models or permissions.
- `nohands-cli bench /nonexistent`, and `bench` on an empty folder: exit 1 with the message.
- `bench` on a folder with one silent file: `skipped: no utterance`, all percentiles `n/a`, exit 1.
