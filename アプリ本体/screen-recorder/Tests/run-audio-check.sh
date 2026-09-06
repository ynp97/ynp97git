#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
CHECK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/screenrec-check.XXXXXX")"
trap 'rm -rf "$CHECK_DIR"' EXIT
python3 - "$CHECK_DIR" <<'PY'
import sys, wave, math, struct
from pathlib import Path
for i, frequency in enumerate([440, 880]):
    with wave.open(str(Path(sys.argv[1])/f'tone{i}.wav'), 'wb') as w:
        w.setparams((1, 2, 48000, 0, 'NONE', 'not compressed'))
        w.writeframes(b''.join(struct.pack('<h', int(16000*math.sin(2*math.pi*frequency*j/48000))) for j in range(144000)))
PY
swiftc -parse-as-library -O -o "$CHECK_DIR/check" Tests/AudioMixCheck.swift Sources/ScreenRecorder/RecordingFinalizer.swift
for GAINS in "0.5 0.5" "0.2 0.8" "0 1" "1 0"; do
  CASE_DIR="$CHECK_DIR/case-${GAINS// /-}"
  mkdir "$CASE_DIR"
  cp "$CHECK_DIR/"*.wav "$CASE_DIR/"
  read -r SYSTEM_GAIN MIC_GAIN <<< "$GAINS"
  "$CHECK_DIR/check" "$CASE_DIR" "$SYSTEM_GAIN" "$MIC_GAIN"
done
