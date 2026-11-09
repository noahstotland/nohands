#!/bin/bash
# Generates the phrase set for `nohands-cli bench` with the macOS `say` command: 16 kHz 16-bit mono WAV, one phrase
# per file. Usage: scripts/make-bench-audio.sh [outdir]   (default: .build/bench-audio, which git ignores).
# The audio is synthesized, so its silence is cleaner than a room's; see Tests/Fixtures/audio/README.md for real
# recordings. The voice and rate are pinned so a re-run on one Mac produces the same set.
set -euo pipefail

VOICE="Samantha"
RATE=180
out="${1:-.build/bench-audio}"
mkdir -p "$out"

if ! say -v '?' | grep -q "^$VOICE "; then
    echo "make-bench-audio: the '$VOICE' voice is not installed (System Settings > Accessibility > Spoken Content)" >&2
    exit 1
fi

# speak "<phrase>" <file>
speak() {
    say -v "$VOICE" -r "$RATE" --file-format=WAVE --data-format=LEI16@16000 -o "$2" -- "$1"
}

phrases=(
    "new tab" "close tab" "next tab" "go back" "copy" "paste"
    "scroll down ten" "scroll up five" "click forty two" "click seven"
    "stop" "go to sleep" "wake up" "press command s"
    "please write a short note to remind me to call the dentist tomorrow morning"
)
for phrase in "${phrases[@]}"; do
    name="${phrase// /-}"
    # The dictation sentence gets a short name.
    [ "${#name}" -gt 40 ] && name="dictation-sentence"
    speak "$phrase" "$out/$name.wav"
done

# "click <600 ms pause> forty two": two utterances joined by silence, to see how a pause is handled.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
speak "click" "$tmp/a.wav"
speak "forty two" "$tmp/b.wav"
python3 -I - "$tmp/a.wav" "$tmp/b.wav" "$out/click-pause-forty-two.wav" <<'PY'
import sys, wave
a, b, dest = sys.argv[1:4]
with wave.open(a) as wa, wave.open(b) as wb, wave.open(dest, "wb") as wo:
    wo.setparams(wa.getparams())
    wo.writeframes(wa.readframes(wa.getnframes()))
    wo.writeframes(b"\0" * (wa.getframerate() * 600 // 1000) * wa.getsampwidth() * wa.getnchannels())
    wo.writeframes(wb.readframes(wb.getnframes()))
PY

echo "wrote the phrase set to $out"
