#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_OUTPUT="$(mktemp -d "${TMPDIR:-/tmp}/saystone-workflow-tests.XXXXXX")"
trap 'rm -rf "$TEST_OUTPUT"' EXIT
xcrun swiftc -swift-version 5 -D SAYSTONE_DEVELOPMENT \
    "$ROOT/Sources/Fluid/Persistence/AppStorage.swift" \
    "$ROOT/Sources/Fluid/MacUtilities/UtilityAction.swift" \
    "$ROOT/Sources/Fluid/MacUtilities/UtilityWorkflow.swift" \
    "$ROOT/Sources/Fluid/MacUtilities/UtilityWorkflowStore.swift" \
    "$ROOT/Tests/UtilityWorkflowFixtureTests.swift" \
    -o "$TEST_OUTPUT/workflows"
"$TEST_OUTPUT/workflows"
