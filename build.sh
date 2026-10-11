#!/bin/bash

# SayStone Build Profile Router
# Defaults to the public OSS build, which skips private Fluid Intelligence.
#
# Usage:
#   ./build.sh                    # signed public OSS build
#   ./build.sh public             # signed public OSS build
#   ./build.sh unsigned           # unsigned public OSS build (CI/fallback)
#   ./build.sh development        # signed, isolated development build
#   ./build.sh development-unsigned # isolated development build without signing
#   ./build.sh fi                 # private FI build

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROFILE="${1:-${BUILD_PROFILE:-public}}"
PRIVATE_FI_BUILD_SCRIPT="${PROJECT_DIR}/build_with_FI_incremental.sh"
DERIVED_DATA_PATH="${FLUIDVOICE_DERIVED_DATA_PATH:-${PROJECT_DIR}/DerivedData}"

resolve_development_team() {
    local identity
    identity="$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' \
        | awk 'NR == 1 { identity = $0 } END { print identity }')"
    [ -n "${identity}" ] || return 0

    if [ -n "${FLUIDVOICE_DEVELOPMENT_TEAM:-}" ]; then
        printf '%s\n' "${FLUIDVOICE_DEVELOPMENT_TEAM}"
        return
    fi

    security find-certificate -c "${identity}" -p 2>/dev/null \
        | openssl x509 -noout -subject -nameopt RFC2253 2>/dev/null \
        | sed -n 's/.*OU=\([^,]*\).*/\1/p'
}

run_public_build() {
    local signing_mode="$1"
    local configuration="${2:-Debug}"
    local product_name="${3:-SayStone}"
    local development_team
    local engine_xcconfig="${DERIVED_DATA_PATH}/SayStoneEngineManifest.xcconfig"
    local -a build_args=(
        -project SayStone.xcodeproj
        -scheme SayStone
        -configuration "${configuration}"
        -destination 'platform=macOS'
        -derivedDataPath "${DERIVED_DATA_PATH}"
        -xcconfig "${engine_xcconfig}"
        build
    )

    if [ "${SAYSTONE_REVIEWED_PACKAGE_PLUGINS:-0}" = "1" ]; then
        build_args+=( -skipPackagePluginValidation )
    fi

    cd "${PROJECT_DIR}"
    local -a manifest_args=(
        "${PROJECT_DIR}/scripts/local/generate-engine-xcconfig.py"
        --source-root "${PROJECT_DIR}"
        --output "${engine_xcconfig}"
    )
    if [ "${SAYSTONE_REQUIRE_ENGINE_MANIFEST:-0}" = "1" ]; then
        manifest_args+=( --require-model )
    fi
    if [ "${configuration}" = "Development" ]; then
        manifest_args+=( --model-directory "${HOME}/Library/Application Support/SayStone Development/Application Support/FluidAudio/Models/parakeet-tdt-0.6b-v2-coreml" )
    elif [ -n "${SAYSTONE_MODEL_DIRECTORY:-}" ]; then
        manifest_args+=( --model-directory "${SAYSTONE_MODEL_DIRECTORY}" )
    fi
    python3 "${manifest_args[@]}"

    if [ "${signing_mode}" = "unsigned" ]; then
        echo "Running unsigned public SayStone ${configuration} build..."
        echo "Accessibility permission may need to be granted again after rebuilding."
        exec xcodebuild "${build_args[@]}" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
    fi

    development_team="$(resolve_development_team)"
    if [ -z "${development_team}" ]; then
        if [ -n "${FLUIDVOICE_DEVELOPMENT_TEAM:-}" ]; then
            printf >&2 'FLUIDVOICE_DEVELOPMENT_TEAM is set to %s, but no Apple Development signing identity was found.\n\n' \
                "${FLUIDVOICE_DEVELOPMENT_TEAM}"
            printf >&2 '%s\n\n' \
                "The team override selects an installed signing identity; it does not replace a certificate."
        else
            printf >&2 'No Apple Development signing identity was found.\n\n'
        fi

        cat >&2 <<'EOF'
For stable Accessibility permission across rebuilds, add any Apple Account in:
  Xcode > Settings > Accounts

Then open Manage Certificates and create an Apple Development certificate.

A free Personal Team is sufficient for local development. If you have multiple
teams, set FLUIDVOICE_DEVELOPMENT_TEAM to the desired 10-character Team ID.

To build without signing instead, run:
  ./build.sh unsigned

Unsigned builds may require Accessibility permission again after rebuilding.
EOF
        exit 1
    fi

    echo "Running signed public SayStone ${configuration} build..."
    echo "Build product: ${DERIVED_DATA_PATH}/Build/Products/${configuration}/${product_name}.app"
    xcodebuild "${build_args[@]}" DEVELOPMENT_TEAM="${development_team}"

    # The upstream binary framework needs macOS versioned-framework symlinks
    # before strict bundle verification. Repair only this generated product.
    local app_path="${DERIVED_DATA_PATH}/Build/Products/${configuration}/${product_name}.app"
    local signing_identity signing_authority
    signing_authority="$(codesign --display --verbose=2 "${app_path}" 2>&1 \
        | awk '/^Authority=/ { if (!authority) authority = substr($0, 11) } END { print authority }')"
    signing_identity="$(security find-identity -v -p codesigning 2>/dev/null \
        | awk -v authority="${signing_authority}" \
            'index($0, "\"" authority "\"") { if (!identity) identity = $2 } END { print identity }')"
    if [ -z "${signing_identity}" ]; then
        echo >&2 "Could not resolve the certificate used to sign this build."
        return 1
    fi
    python3 "${PROJECT_DIR}/scripts/local/repair-framework-bundle.py" \
        "${app_path}" --identity "${signing_identity}"
    echo "Signed SayStone build verified: ${app_path}"
}

case "${PROFILE}" in
    public|oss|incremental|fast)
        run_public_build signed
        ;;
    unsigned|ci)
        run_public_build unsigned
        ;;
    development)
        run_public_build signed Development "SayStone Development"
        ;;
    development-unsigned)
        run_public_build unsigned Development "SayStone Development"
        ;;
    fi|private|dev|full)
        if [ ! -x "${PRIVATE_FI_BUILD_SCRIPT}" ]; then
            echo "Private Fluid Intelligence build script is missing:"
            echo "  ${PRIVATE_FI_BUILD_SCRIPT}"
            echo "Restore the private FI build setup, then run: sh build_with_FI_incremental.sh"
            exit 1
        fi
        exec "${PRIVATE_FI_BUILD_SCRIPT}"
        ;;
    *)
        echo "Unknown build profile: ${PROFILE}"
        echo "Valid profiles: public/oss/incremental/fast, unsigned/ci, development, development-unsigned, fi/private/dev/full"
        exit 1
        ;;
esac
