# Benchmark audio

`nohands-cli bench <dir>` replays every `.wav` file directly in a folder (not subfolders) through the voice-activity
detector, the early close, the speech recognizer and the command grammar, and prints the latency of each stage.
No audio is checked in here. `swift test` does not use any.

## The phrase set

Sixteen files, one phrase each, named after the phrase:

| File | You say |
|---|---|
| `new-tab.wav` | new tab |
| `close-tab.wav` | close tab |
| `next-tab.wav` | next tab |
| `go-back.wav` | go back |
| `copy.wav` | copy |
| `paste.wav` | paste |
| `scroll-down-ten.wav` | scroll down ten |
| `scroll-up-five.wav` | scroll up five |
| `click-forty-two.wav` | click forty two |
| `click-seven.wav` | click seven |
| `stop.wav` | stop |
| `go-to-sleep.wav` | go to sleep |
| `wake-up.wav` | wake up |
| `press-command-s.wav` | press command s |
| `dictation-sentence.wav` | one sentence of dictation, for example "please write a short note to remind me to call the dentist tomorrow morning" |
| `click-pause-forty-two.wav` | click, a pause of about 600 ms, forty two |

## Generate a synthesized set

```sh
scripts/make-bench-audio.sh            # writes .build/bench-audio/
.build/debug/nohands-cli bench .build/bench-audio
```

The script uses the macOS `say` command with a pinned voice and rate. Synthesized speech has cleaner silence than a
room, so real numbers may differ.

## Record your own

- One phrase per file, 16 kHz or any rate the macOS audio converter reads, but the file must be named `.wav`.
- A quiet room. Background noise above the 0.005 RMS threshold makes the tool think speech ended later than it did,
  so the lag reads low or negative.
- Stop after the last word: under half a second of audio after it.
- Put the files in a folder and run `.build/debug/nohands-cli bench <folder>`. A few MB of your own recordings may be
  committed here if you want them in the repo.

The run uses your `~/.config/nohands/config.json` except that the attention word is ignored, and it loads the speech
model, so it needs the downloaded Parakeet model but no permissions and no microphone.
