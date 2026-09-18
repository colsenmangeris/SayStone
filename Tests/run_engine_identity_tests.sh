#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT="${TMPDIR:-/tmp}/saystone-engine-model-digest-tests"
xcrun swiftc \
  "$ROOT/Sources/Fluid/Services/DictationPipeline/EngineModelDigest.swift" \
  "$ROOT/Tests/EngineModelDigestTests.swift" \
  -o "$OUT"
"$OUT"
