#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_OUTPUT="$(mktemp -d "${TMPDIR:-/tmp}/saystone-isolation-tests.XXXXXX")"
trap 'rm -rf "$TEST_OUTPUT"' EXIT

for mode in development public; do
    flags=()
    if [ "$mode" = "development" ]; then
        flags+=( -D SAYSTONE_DEVELOPMENT )
    fi
    xcrun swiftc -swift-version 5 "${flags[@]}" \
        "$ROOT/Sources/Fluid/Persistence/AppStorage.swift" \
        "$ROOT/Sources/Fluid/Services/FailedDictationRecovery.swift" \
        "$ROOT/Tests/DevelopmentIsolationTests.swift" \
        -o "$TEST_OUTPUT/$mode"
    "$TEST_OUTPUT/$mode"
done
