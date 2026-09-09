#!/usr/bin/env python3
"""Repair the upstream binary framework layout in a generated app, then sign it."""
import argparse
from pathlib import Path
import shutil
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('app', type=Path)
parser.add_argument('--identity', required=True)
args = parser.parse_args()
app = args.app.resolve()
framework = app / 'Contents/Frameworks/CTranscribe.framework'
assert (framework / 'Versions/A/CTranscribe').is_file(), 'Unexpected framework layout'
for relative, target in [('Versions/Current', 'A'), ('CTranscribe', 'Versions/Current/CTranscribe'),
                         ('Resources', 'Versions/Current/Resources')]:
    path = framework / relative
    if path.is_symlink():
        assert str(path.readlink()) == target
        continue
    if path.is_dir():
        shutil.rmtree(path)
    else:
        path.unlink()
    path.symlink_to(target)
for component in [framework, app]:
    subprocess.run(['codesign', '--force', '--sign', args.identity, '--options', 'runtime',
                    '--timestamp=none', '--preserve-metadata=identifier,entitlements,flags',
                    str(component)], check=True)
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
