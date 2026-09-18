#!/bin/sh
set -eu

task_developer_dir="${DEVELOPER_DIR:-$(xcode-select -p)}"
case "$task_developer_dir" in
    */Xcode*.app/Contents/Developer) ;;
    *) echo "Set DEVELOPER_DIR to an installed full Xcode before running tests." >&2; exit 1 ;;
esac
export DEVELOPER_DIR="$task_developer_dir"
task_repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
task_test_dir=$(mktemp -d /tmp/fluidvoice-dictation-api-tests.XXXXXX)

xcrun swiftc -O \
    "$task_repo_dir/Sources/Fluid/Services/LocalAPI/LocalAPIModels.swift" \
    "$task_repo_dir/Sources/Fluid/Services/LocalAPI/DictationAPI.swift" \
    "$task_repo_dir/Sources/Fluid/Services/DictationPipeline/SharedDictationPipeline.swift" \
    "$task_repo_dir/Sources/Fluid/Services/DictationPipeline/EngineIdentity.swift" \
    "$task_repo_dir/Sources/Fluid/Services/DictationPipeline/SpokenPunctuationFormatter.swift" \
    "$task_repo_dir/Sources/Fluid/Services/DictationPipeline/DictationLiteralFormatter.swift" \
    "$task_repo_dir/Sources/Fluid/Services/LocalPunctuationCleanup.swift" \
    "$task_repo_dir/Tests/DictationAPITests.swift" \
    -o "$task_test_dir/dictation-api-tests"
"$task_test_dir/dictation-api-tests"
