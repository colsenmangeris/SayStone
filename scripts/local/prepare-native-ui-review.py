#!/usr/bin/env python3
"""Prepare, but never launch, a signed background synthetic review app."""
import argparse
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import uuid


def run(*arguments):
    return subprocess.run(arguments, check=True, text=True, capture_output=True).stdout.strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--identity', required=True, help='Exact installed signing certificate name or SHA-1')
    args = parser.parse_args()
    if args.identity == '-':
        raise SystemExit('Use an installed signing certificate; ad-hoc signing is not a trusted launch identity.')
    root = Path(__file__).resolve().parents[2]
    source = root / 'DerivedData/Build/Products/Development/SayStone Development.app'
    identifier = 'com.architech.saystone.development'
    production_paths = ['Sources/Fluid', 'Info.plist', 'SayStone.xcodeproj', 'build.sh']
    dirty = run('git', '-C', str(root), 'status', '--porcelain', '--', *production_paths)
    if dirty:
        raise SystemExit('Commit production source changes and rebuild before preparing a review copy.')
    commit = run('git', '-C', str(root), 'rev-parse', 'HEAD')
    with (source / 'Contents/Info.plist').open('rb') as stream:
        metadata = plistlib.load(stream)
    if metadata.get('CFBundleIdentifier') != identifier:
        raise SystemExit('Review source must have the exact isolated Development bundle identity.')
    if metadata.get('SayStoneEngineRuntimeCommit') != commit:
        raise SystemExit('Review source is stale: run the signed Development build at current HEAD first.')
    if 'SayStoneSyntheticUISession' in metadata or (source / 'Contents/PlugIns').exists():
        raise SystemExit('Use a fresh ordinary app-only Development build, without a test marker or hosted test plug-ins.')
    executable = source / 'Contents/MacOS' / metadata['CFBundleExecutable']
    images = [executable, executable.with_name(executable.name + '.debug.dylib')]
    if not any(b'SayStoneSyntheticUISession' in image.read_bytes() for image in images if image.is_file()):
        raise SystemExit('Review source lacks the embedded-session startup guard; rebuild current sources.')
    run('codesign', '--verify', '--deep', '--strict', str(source))

    session = str(uuid.uuid4()).upper()
    directory = Path(tempfile.mkdtemp(prefix='saystone-native-review-')).resolve()
    directory.chmod(0o700)
    review = directory / 'SayStone Native Review.app'
    try:
        shutil.copytree(source, review, symlinks=True)
        metadata.update({
            'SayStoneSyntheticUISession': session,
            'CFBundleName': 'SayStone Native Review',
            'CFBundleDisplayName': 'SayStone Native Review',
            'LSUIElement': True,
        })
        # Executable and guarded bundle identity deliberately remain unchanged.
        with (review / 'Contents/Info.plist').open('wb') as stream:
            plistlib.dump(metadata, stream)
        run('python3', str(root / 'scripts/local/repair-framework-bundle.py'),
            str(review), '--identity', args.identity)
        run('codesign', '--verify', '--deep', '--strict', str(review))
        receipt = {
            'appPath': str(review),
            'executablePath': str(review / 'Contents/MacOS' / metadata['CFBundleExecutable']),
            'bundleIdentifier': identifier,
            'session': session,
            'preferencesDomain': f'{identifier}.ui-tests.{session}',
            'utilityDirectory': str((Path(run('getconf', 'DARWIN_USER_TEMP_DIR')) / 'SayStone-UITests' / session).resolve()),
            'pasteboard': f'SayStone.UITests.{session}',
            'sourceCommit': commit,
            'backgroundSynthetic': True,
            'strictSignatureVerified': True,
            'launched': False,
        }
        receipt_path = directory / 'review.json'
        receipt_path.write_text(json.dumps(receipt, indent=2) + '\n')
        receipt_path.chmod(0o600)
        print(json.dumps({'receipt': str(receipt_path), **receipt}, indent=2))
    except BaseException:
        shutil.rmtree(directory)
        raise


if __name__ == '__main__':
    main()
