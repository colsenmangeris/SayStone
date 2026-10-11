#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURE_OUTPUT="$(mktemp -d "${TMPDIR:-/tmp}/saystone-runtime-fixture.XXXXXX")"
trap 'rm -rf "$FIXTURE_OUTPUT"' EXIT

for mode in development public; do
    flags=()
    if [ "$mode" = "development" ]; then
        flags+=( -D SAYSTONE_DEVELOPMENT )
    fi
    xcrun swiftc -swift-version 5 -default-isolation MainActor "${flags[@]}" \
        "$ROOT/Sources/Fluid/Persistence/AppStorage.swift" \
        "$ROOT/Sources/Fluid/MacUtilities/DevelopmentRuntime.swift" \
        "$ROOT/Tests/DevelopmentRuntimeFixtureTests.swift" \
        -o "$FIXTURE_OUTPUT/$mode"
    "$FIXTURE_OUTPUT/$mode"
done
