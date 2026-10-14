#!/bin/bash
# Opt-in native inference on the authored repository WAV. Never opens a microphone.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PROVIDER=whisper
DOWNLOAD=0
RESULT_BUNDLE=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --provider)
            [ "$#" -ge 2 ] || { echo 'Missing --provider value' >&2; exit 2; }
            PROVIDER="$2"; shift 2 ;;
        --download-models) DOWNLOAD=1; shift ;;
        --result-bundle)
            [ "$#" -ge 2 ] || { echo 'Missing --result-bundle value' >&2; exit 2; }
            RESULT_BUNDLE="$2"; shift 2 ;;
        *) echo 'Usage: run-authored-speech-acceptance.sh [--provider whisper|parakeet] [--download-models] [--result-bundle PATH]' >&2; exit 2 ;;
    esac
done
case "$PROVIDER" in
    whisper) TEST_METHOD=testWhisperTinyRepeatedFinalRecognition ;;
    parakeet) TEST_METHOD=testParakeetV2RepeatedFinalRecognition ;;
    *) echo 'Provider must be whisper or parakeet' >&2; exit 2 ;;
esac
APP="$ROOT/DerivedData/Build/Products/Development/SayStone Development.app"
codesign --verify --deep --strict "$APP"
# macOS's Bash 3.2 can misparse quoted Python strings when a heredoc is
# nested inside command substitution. Keep the heredoc at shell scope.
MANIFEST_PATH_RECEIPT="$(mktemp "${TMPDIR:-/tmp}/saystone-speech-manifest.XXXXXX")"
TEST_MANIFEST=""
trap 'rm -f "$MANIFEST_PATH_RECEIPT"; [ -z "$TEST_MANIFEST" ] || rm -f "$TEST_MANIFEST"' EXIT
python3 - "$ROOT" "$DOWNLOAD" "$MANIFEST_PATH_RECEIPT" <<'PY'
import os, plistlib, sys, tempfile, uuid
from pathlib import Path
root = Path(sys.argv[1]).resolve()
products = root / 'DerivedData/Build/Products'
manifests = [p for p in products.glob('*.xctestrun') if not p.name.startswith('.authored-speech-')]
if len(manifests) != 1:
    raise SystemExit('Build native test products first; expected exactly one .xctestrun manifest.')
manifest = plistlib.loads(manifests[0].read_bytes())
targets = [t for c in manifest.get('TestConfigurations', []) for t in c.get('TestTargets', [])]
units = [t for t in targets if t.get('BlueprintName') == 'FluidDictationIntegrationTests']
if len(units) != 1:
    raise SystemExit('Expected exactly one hosted unit-test target.')
units = units[0]
host = units.get('TestHostPath', '').replace('__TESTROOT__', str(products))
expected = products / 'Development/SayStone Development.app'
if Path(host).resolve() != expected.resolve():
    raise SystemExit('The unit-test host must be this checkout\'s isolated Development product.')
info = plistlib.loads((expected / 'Contents/Info.plist').read_bytes())
if info.get('CFBundleIdentifier') != 'com.architech.saystone.development':
    raise SystemExit('Refusing acceptance with a non-development bundle identity.')
bundle = units.get('TestBundlePath', '').replace('__TESTHOST__', str(expected)).replace('__TESTROOT__', str(products))
expected_bundle = expected / 'Contents/PlugIns/FluidDictationIntegrationTests.xctest'
if Path(bundle).resolve() != expected_bundle.resolve():
    raise SystemExit('The hosted unit-test bundle must be inside this checkout\'s isolated Development product.')
if not expected_bundle.is_dir():
    raise SystemExit('Build native test products first; the hosted unit-test bundle is missing from the packaged app.')
arguments = units.get('CommandLineArguments', [])
if '--ui-testing' not in arguments:
    raise SystemExit('Acceptance requires synthetic --ui-testing startup.')
if '--ui-test-session' in arguments:
    raise SystemExit('Expected a generated manifest without a preconfigured test session.')
units['CommandLineArguments'] = [*arguments, '--ui-test-session', str(uuid.uuid4())]
environment = units.setdefault('EnvironmentVariables', {})
environment['SAYSTONE_RUN_AUTHORED_SPEECH_ACCEPTANCE'] = '1'
environment['SAYSTONE_ALLOW_AUTHORED_MODEL_DOWNLOAD'] = sys.argv[2]
# Keep __TESTROOT__ anchored to the generated products directory.
fd, name = tempfile.mkstemp(prefix='.authored-speech-', suffix='.xctestrun', dir=products)
with os.fdopen(fd, 'wb') as output:
    plistlib.dump(manifest, output)
Path(sys.argv[3]).write_text(name, encoding='utf-8')
PY
TEST_MANIFEST="$(cat "$MANIFEST_PATH_RECEIPT")"
rm -f "$MANIFEST_PATH_RECEIPT"
if [ -z "$RESULT_BUNDLE" ]; then
    RESULT_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/saystone-authored-speech.XXXXXX")"
    RESULT_BUNDLE="$RESULT_DIRECTORY/Acceptance.xcresult"
fi
printf 'Authored speech receipt: %s\n' "$RESULT_BUNDLE"
xcodebuild test-without-building -xctestrun "$TEST_MANIFEST" \
    -destination 'platform=macOS,arch=arm64' -parallel-testing-enabled NO \
    -only-testing:"FluidDictationIntegrationTests/DevelopmentSpeechFixtureTests/$TEST_METHOD" \
    -resultBundlePath "$RESULT_BUNDLE"
python3 - "$RESULT_BUNDLE" <<'PY'
import json, subprocess, sys
summary = json.loads(subprocess.run(
    ['xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', sys.argv[1]],
    check=True, capture_output=True, text=True
).stdout)
passed = summary.get('passedTests', 0)
failed = summary.get('failedTests', 0)
skipped = summary.get('skippedTests', 0)
if passed != 1 or failed or skipped:
    print(f'Authored speech NOT accepted: passed={passed}, failed={failed}, skipped={skipped}. See the receipt.', file=sys.stderr)
    raise SystemExit(3)
print('Authored speech accepted: one native test passed, with no failures or skips.')
PY
