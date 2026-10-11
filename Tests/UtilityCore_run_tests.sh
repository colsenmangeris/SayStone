#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_OUTPUT="$(mktemp -d "${TMPDIR:-/tmp}/saystone-utility-core.XXXXXX")"
trap 'rm -rf "$TEST_OUTPUT"' EXIT

xcrun swiftc -swift-version 5 -parse-as-library \
    "$ROOT/Tests/UtilityCoreProcessFixture.swift" \
    -o "$TEST_OUTPUT/process-fixture"
xcrun swiftc -swift-version 5 -default-isolation MainActor \
    "$ROOT/Sources/Fluid/MacUtilities/UtilityAction.swift" \
    "$ROOT/Sources/Fluid/MacUtilities/UtilityClipboard.swift" \
    "$ROOT/Sources/Fluid/MacUtilities/UtilityProcessRunner.swift" \
    "$ROOT/Tests/UtilityCoreTests.swift" \
    -o "$TEST_OUTPUT/utility-core-tests"
"$TEST_OUTPUT/utility-core-tests" "$TEST_OUTPUT/process-fixture"
