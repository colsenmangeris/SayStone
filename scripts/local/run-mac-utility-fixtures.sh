#!/bin/bash
# Synthetic local fixtures only; never starts either installed SayStone app.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FIXTURES=(
    Tests/run_development_isolation_tests.sh
    Tests/run_development_runtime_fixture.sh
    Tests/run_flash_cache_fixture.sh
    Tests/UtilityCore_run_tests.sh
    Tests/run_clipboard_library_tests.sh
    Tests/run_utility_workflow_fixtures.sh
    Tests/run_utility_shortcut_fixtures.sh
)
for fixture in "${FIXTURES[@]}"; do
    if [ ! -f "$ROOT/$fixture" ]; then
        printf 'Required fixture runner is missing: %s\n' "$fixture" >&2
        exit 1
    fi
    printf 'Running %s\n' "$fixture"
    bash "$ROOT/$fixture"
done
