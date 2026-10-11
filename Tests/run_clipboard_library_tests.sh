#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_OUTPUT="$(mktemp -d "${TMPDIR:-/tmp}/saystone-clipboard-library.XXXXXX")"
trap 'rm -rf "$TEST_OUTPUT"' EXIT

xcrun swiftc -swift-version 5 -D SAYSTONE_DEVELOPMENT \
    "$ROOT/Sources/Fluid/Persistence/AppStorage.swift" \
    "$ROOT/Sources/Fluid/MacUtilities/ClipboardLibrary.swift" \
    "$ROOT/Tests/ClipboardLibraryTests.swift" \
    -o "$TEST_OUTPUT/clipboard-library"
"$TEST_OUTPUT/clipboard-library"
