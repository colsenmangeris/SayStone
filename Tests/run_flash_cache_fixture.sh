#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_OUTPUT="$(mktemp -d "${TMPDIR:-/tmp}/saystone-flash-cache.XXXXXX")"
trap 'rm -rf "$TEST_OUTPUT"' EXIT
if [ "$(uname -m)" != arm64 ]; then
    printf 'SKIP Flash cache fixture: requires Apple Silicon\n'
    exit 0
fi
xcrun swiftc -swift-version 5 -emit-library -emit-module -module-name FluidAudio \
    "$ROOT/Tests/FlashCacheFixture/FluidAudioStub.swift" \
    -emit-module-path "$TEST_OUTPUT/FluidAudio.swiftmodule" \
    -o "$TEST_OUTPUT/libFluidAudio.dylib"
xcrun swiftc -swift-version 5 -I "$TEST_OUTPUT" -L "$TEST_OUTPUT" -lFluidAudio \
    -Xlinker -rpath -Xlinker "$TEST_OUTPUT" \
    "$ROOT/Sources/Fluid/Services/TranscriptionProvider.swift" \
    "$ROOT/Sources/Fluid/Services/ParakeetRealtimeProvider.swift" \
    "$ROOT/Tests/FlashCacheFixture/ProviderFixture.swift" \
    -o "$TEST_OUTPUT/fixture"
"$TEST_OUTPUT/fixture" "$TEST_OUTPUT/authored-cache"
