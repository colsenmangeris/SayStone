#!/usr/bin/env python3
"""Generate signed build metadata for the pinned SayStone speech engine.

The resulting xcconfig is consumed by Info.plist expansion. Because Info.plist
is inside the signed app bundle, these values describe the exact source and
model artifact used for that build. The running app separately hashes the
installed model and refuses a shared-engine readiness claim on any mismatch.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys


MODEL_KEY = "parakeet-v2"
MODEL_DIRECTORY_NAME = "parakeet-tdt-0.6b-v2-coreml"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(4 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def sha256_tree(root: Path) -> str:
    files = sorted(path for path in root.rglob("*") if path.is_file())
    if not files:
        raise ValueError(f"model directory has no files: {root}")
    manifest = "".join(
        f"{sha256_file(path)}  {path.relative_to(root).as_posix()}\n" for path in files
    )
    return hashlib.sha256(manifest.encode("utf-8")).hexdigest()


def git_head(root: Path) -> str:
    return subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=root, text=True
    ).strip()


def fluid_audio_revision(root: Path) -> str:
    resolved = root / "Fluid.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
    data = json.loads(resolved.read_text())
    for pin in data.get("pins", []):
        if pin.get("identity", "").lower() == "fluidaudio":
            revision = pin.get("state", {}).get("revision")
            if isinstance(revision, str) and revision:
                return revision
    raise ValueError("FluidAudio revision is missing from Package.resolved")


def swift_constant(path: Path, name: str) -> str:
    match = re.search(
        rf"static\s+let\s+{re.escape(name)}\s*=\s*(?:\"([^\"]+)\"|(\d+))",
        path.read_text(),
    )
    if match is None:
        raise ValueError(f"could not read {name} from {path}")
    return match.group(1) or match.group(2)


def write_xcconfig(output: Path, values: dict[str, str]) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("".join(f"{key} = {value}\n" for key, value in values.items()))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--model-directory", type=Path)
    parser.add_argument("--require-model", action="store_true")
    args = parser.parse_args()

    root = args.source_root.resolve()
    model_directory = args.model_directory or (
        Path.home()
        / "Library/Application Support/FluidAudio/Models"
        / MODEL_DIRECTORY_NAME
    )

    values = {
        "SAYSTONE_ENGINE_MODEL_KEY": "",
        "SAYSTONE_ENGINE_MODEL_REVISION": "",
        "SAYSTONE_ENGINE_MODEL_SHA256": "",
        "SAYSTONE_ENGINE_RUNTIME_COMMIT": git_head(root),
        "SAYSTONE_ENGINE_PIPELINE_REVISION": swift_constant(
            root / "Sources/Fluid/Services/DictationPipeline/SharedDictationPipeline.swift",
            "revision",
        ),
        "SAYSTONE_ENGINE_PROFILE_SCHEMA_REVISION": swift_constant(
            root / "Sources/Fluid/Services/SayStoneSpeechProfile.swift",
            "currentSchemaRevision",
        ),
        "SAYSTONE_ENGINE_FLUIDAUDIO_REVISION": fluid_audio_revision(root),
    }

    try:
        model_digest = sha256_tree(model_directory)
    except (OSError, ValueError) as error:
        if args.require_model:
            print(f"engine manifest generation failed: {error}", file=sys.stderr)
            return 1
        print(
            f"warning: shared-engine manifest is incomplete because the pinned model is unavailable: {error}",
            file=sys.stderr,
        )
    else:
        values["SAYSTONE_ENGINE_MODEL_KEY"] = MODEL_KEY
        values["SAYSTONE_ENGINE_MODEL_REVISION"] = (
            f"fluidaudio-{values['SAYSTONE_ENGINE_FLUIDAUDIO_REVISION'][:12]}-tree-{model_digest[:12]}"
        )
        values["SAYSTONE_ENGINE_MODEL_SHA256"] = model_digest

    write_xcconfig(args.output, values)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
