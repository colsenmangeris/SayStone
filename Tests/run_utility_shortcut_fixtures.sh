#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
task_directory="$(mktemp -d /tmp/saystone-shortcut-fixtures.XXXXXX)"
trap 'rm -rf "$task_directory"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library \
  "$task_root/Sources/Fluid/Models/HotkeyShortcut.swift" \
  "$task_root/Sources/Fluid/MacUtilities/UtilityShortcutRules.swift" \
  "$task_root/Sources/Fluid/MacUtilities/UtilityShortcutStore.swift" \
  "$task_root/Tests/UtilityShortcutFixtureTests.swift" \
  -o "$task_directory/tests"
"$task_directory/tests"
