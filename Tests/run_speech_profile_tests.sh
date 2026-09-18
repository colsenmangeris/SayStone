#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT="${TMPDIR:-/tmp}/saystone-speech-profile-tests"
xcrun swiftc \
  "$ROOT/Sources/Fluid/Services/SayStoneSpeechProfile.swift" \
  "$ROOT/Tests/SayStoneSpeechProfileTests.swift" \
  -o "$OUT"
"$OUT"
