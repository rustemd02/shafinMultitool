#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd -P)"
WORKSPACE="$REPO_ROOT/shafinMultitool.xcworkspace"
SCHEME="shafinMultitool"
SOURCE_MANIFEST="$REPO_ROOT/shafinMultitool/PrivacyInfo.xcprivacy"
PRIVACY_VALIDATOR="$REPO_ROOT/scripts/validate_privacy_manifest.sh"
BUNDLE_VALIDATOR="$REPO_ROOT/scripts/validate_release_bundle.sh"
FIXTURE_TEST="$REPO_ROOT/scripts/tests/test_release_bundle_gate.sh"
LLAMA_PROVENANCE_VALIDATOR="$REPO_ROOT/scripts/validate_llama_framework_provenance.py"
CIRCLE_PROVENANCE_VALIDATOR="$REPO_ROOT/scripts/validate_circle_asset_provenance.py"
COMPONENT_STATUS_VALIDATOR="$REPO_ROOT/scripts/validate_release_component_status.py"
COMPONENT_STATUS_RECORD="$REPO_ROOT/docs/implementation/provenance/release-component-status.json"
DERIVED_DATA_ROOT_ARG=""
DERIVED_DATA_ROOT=""
OWNED_ROOT=""
DEBUG_DERIVED_ROOT=""
RELEASE_DERIVED_ROOT=""

usage() {
    cat <<'EOF'
Usage:
  scripts/run_release_gates.sh --derived-data-root /absolute/existing/path

The command owns only <derived-data-root>/shafin-release-gates, and it writes each
run into its own run-<UTC>-<pid> subdirectory: an earlier run's logs and derived
data are never removed to make room for this one. It does not discover
DerivedData, use a developer-home path, install dependencies, or access the network.
EOF
}

fail() {
    printf 'FAIL: stage=%s reason=%s\n' "$1" "$2" >&2
    exit 1
}

require_tool() {
    local tool="$1"

    if ! command -v "$tool" >/dev/null 2>&1; then
        fail "preflight" "required macOS tool is missing: $tool"
    fi
}

validate_derived_data_root() {
    local requested="$1"
    local resolved_root
    local owned_parent

    if [ -z "$requested" ]; then
        fail "preflight" "--derived-data-root is empty"
    fi
    case "$requested" in
        /*)
            ;;
        *)
            fail "preflight" "--derived-data-root must be an absolute path: $requested"
            ;;
    esac
    case "$requested" in
        */../*|../*|*/..|..)
            fail "preflight" "--derived-data-root must not contain parent traversal: $requested"
            ;;
    esac
    if [ ! -d "$requested" ] || [ -L "$requested" ]; then
        fail "preflight" "--derived-data-root must be an existing non-symlink directory: $requested"
    fi

    resolved_root="$(CDPATH= cd -- "$requested" && pwd -P)"
    case "$resolved_root" in
        /|/tmp|/private/tmp|/var|/private/var|/private|/Users|/System|/Library|/Applications|"$REPO_ROOT")
            fail "preflight" "--derived-data-root is an unsafe broad root: $resolved_root"
            ;;
    esac

    OWNED_ROOT="$resolved_root/shafin-release-gates"
    owned_parent="$(CDPATH= cd -- "$(dirname -- "$OWNED_ROOT")" && pwd -P)"
    if [ "$owned_parent" != "$resolved_root" ]; then
        fail "preflight" "owned output path is not directly under the validated root: $OWNED_ROOT"
    fi
    if [ -L "$OWNED_ROOT" ]; then
        fail "preflight" "owned output path must not be a symlink: $OWNED_ROOT"
    fi
    if [ -e "$OWNED_ROOT" ] && [ ! -d "$OWNED_ROOT" ]; then
        fail "preflight" "owned output path is not a directory: $OWNED_ROOT"
    fi
    DERIVED_DATA_ROOT="$resolved_root"
}

run_logged_command() {
    local stage="$1"
    local label="$2"
    local log_path="$3"
    local status
    shift 3

    printf 'STAGE %s: %s\n' "$stage" "$label"
    if (CDPATH= cd -- "$REPO_ROOT" && "$@") > "$log_path" 2>&1; then
        printf 'PASS %s\n' "$label"
        return 0
    else
        status=$?
    fi
    printf 'FAIL: stage=%s reason=%s exited %s; log=%s\n' "$stage" "$label" "$status" "$log_path" >&2
    tail -n 80 "$log_path" >&2 || true
    exit "$status"
}

resolve_exact_app() {
    local search_root="$1"
    local inventory="$2"
    local candidate
    local count=0
    local result=""

    if ! find "$search_root" -type d -name 'shafinMultitool.app' -prune -print0 > "$inventory"; then
        fail "product-resolution" "could not enumerate shafinMultitool.app under $search_root"
    fi
    while IFS= read -r -d '' candidate; do
        count=$((count + 1))
        result="$candidate"
    done < "$inventory"
    if [ "$count" -ne 1 ]; then
        fail "product-resolution" "expected exactly one shafinMultitool.app under $search_root, found $count"
    fi
    case "$result" in
        "$search_root"/*)
            ;;
        *)
            fail "product-resolution" "resolved app escaped derived-data path: $result"
            ;;
    esac
    printf '%s\n' "$result"
}

extract_metric() {
    local key="$1"
    local log_path="$2"
    local value

    value="$(awk -F= -v wanted="$key" '$1 == wanted { value=$2 } END { if (value != "") print value }' "$log_path")"
    if [ -z "$value" ]; then
        fail "release-validation" "validator did not emit $key"
    fi
    printf '%s\n' "$value"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --derived-data-root)
            [ "$#" -ge 2 ] || fail "argument" "--derived-data-root requires a path"
            DERIVED_DATA_ROOT_ARG="$2"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            usage >&2
            fail "argument" "unknown argument: $1"
            ;;
    esac
done

[ -n "$DERIVED_DATA_ROOT_ARG" ] || fail "argument" "--derived-data-root is required"

printf 'STAGE 1: preflight\n'
for tool in xcodebuild xcrun plutil python3 find du sort git; do
    require_tool "$tool"
done
if [ ! -d "$WORKSPACE" ] || [ ! -f "$WORKSPACE/contents.xcworkspacedata" ]; then
    fail "preflight" "workspace is missing or malformed: $WORKSPACE"
fi
if [ ! -f "$REPO_ROOT/shafinMultitool.xcodeproj/xcshareddata/xcschemes/$SCHEME.xcscheme" ]; then
    fail "preflight" "shared scheme is missing: $SCHEME"
fi
if [ ! -f "$SOURCE_MANIFEST" ]; then
    fail "preflight" "source privacy manifest is missing: $SOURCE_MANIFEST"
fi
for required_script in "$PRIVACY_VALIDATOR" "$BUNDLE_VALIDATOR" "$FIXTURE_TEST"; do
    if [ ! -f "$required_script" ] || [ ! -x "$required_script" ]; then
        fail "preflight" "required release script is missing or not executable: $required_script"
    fi
done
for required_validator in "$LLAMA_PROVENANCE_VALIDATOR" "$CIRCLE_PROVENANCE_VALIDATOR"; do
    if [ ! -f "$required_validator" ] || [ -L "$required_validator" ]; then
        fail "preflight" "required offline provenance validator is missing or is a symlink: $required_validator"
    fi
done
if [ ! -f "$COMPONENT_STATUS_VALIDATOR" ] || [ -L "$COMPONENT_STATUS_VALIDATOR" ] || [ ! -x "$COMPONENT_STATUS_VALIDATOR" ]; then
    fail "preflight" "component disposition validator is missing, symlinked, or not executable: $COMPONENT_STATUS_VALIDATOR"
fi
if [ ! -f "$COMPONENT_STATUS_RECORD" ] || [ -L "$COMPONENT_STATUS_RECORD" ]; then
    fail "preflight" "component disposition record is missing or is a symlink: $COMPONENT_STATUS_RECORD"
fi
validate_derived_data_root "$DERIVED_DATA_ROOT_ARG"

TESTED_COMMIT="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null)" || fail "preflight" "could not resolve tested Git commit"
TRACKED_STATUS="$(git -C "$REPO_ROOT" status --porcelain --untracked-files=normal)" || fail "preflight" "could not inspect Git worktree status"
if [ -n "$TRACKED_STATUS" ]; then
    TESTED_DIRTY=true
else
    TESTED_DIRTY=false
fi

printf 'TESTED_COMMIT: %s\n' "$TESTED_COMMIT"
printf 'TESTED_DIRTY: %s\n' "$TESTED_DIRTY"
printf 'DERIVED_DATA_ROOT: %s\n' "$DERIVED_DATA_ROOT"
printf 'OWNED_OUTPUT_ROOT: %s\n' "$OWNED_ROOT"
printf 'PASS preflight: tools, workspace, scheme, source manifest, validators, offline provenance records, and output root are valid\n'

# Each run owns a fresh directory instead of resetting the shared one, so a failed
# run's logs survive its successor (P03: do not delete earlier evidence to match a
# name).
if ! mkdir -p -- "$OWNED_ROOT"; then
    fail "output-init" "could not create owned output directory: $OWNED_ROOT"
fi
RUN_ROOT="$OWNED_ROOT/run-$(date -u +%Y%m%dT%H%M%SZ)-$$"
if ! mkdir -p -- "$RUN_ROOT"; then
    fail "output-init" "could not create the run directory: $RUN_ROOT"
fi
printf 'RUN_OUTPUT_ROOT: %s\n' "$RUN_ROOT"
DEBUG_DERIVED_ROOT="$RUN_ROOT/DebugDerivedData"
RELEASE_DERIVED_ROOT="$RUN_ROOT/ReleaseDerivedData"

# CC-011D: accepted offline provenance records are a pre-build release gate.
llama_provenance=(
    python3
    "$LLAMA_PROVENANCE_VALIDATOR"
    --repo-root "$REPO_ROOT"
)
run_logged_command "2" "llama framework provenance (offline)" "$RUN_ROOT/llama-provenance.log" "${llama_provenance[@]}"
cat "$RUN_ROOT/llama-provenance.log"

circle_provenance=(
    python3
    "$CIRCLE_PROVENANCE_VALIDATOR"
    --repo-root "$REPO_ROOT"
)
run_logged_command "3" "Circle asset provenance (offline)" "$RUN_ROOT/circle-provenance.log" "${circle_provenance[@]}"
cat "$RUN_ROOT/circle-provenance.log"

component_status=(
    python3
    "$COMPONENT_STATUS_VALIDATOR"
    --repo-root "$REPO_ROOT"
    --record "$COMPONENT_STATUS_RECORD"
)
run_logged_command "4" "release component dispositions (offline)" "$RUN_ROOT/component-status.log" "${component_status[@]}"
cat "$RUN_ROOT/component-status.log"

privacy_self_test=(
    "$PRIVACY_VALIDATOR"
    --self-test
    --source-manifest "$SOURCE_MANIFEST"
)
run_logged_command "5" "privacy validator self-test" "$RUN_ROOT/privacy-self-test.log" "${privacy_self_test[@]}"
cat "$RUN_ROOT/privacy-self-test.log"

debug_build=(
    xcodebuild
    -workspace shafinMultitool.xcworkspace
    -scheme "$SCHEME"
    -configuration Debug
    -destination 'generic/platform=iOS'
    -derivedDataPath "$DEBUG_DERIVED_ROOT"
    CODE_SIGNING_ALLOWED=NO
    COMPILER_INDEX_STORE_ENABLE=NO
    build-for-testing
)
run_logged_command "6" "Debug build-for-testing" "$RUN_ROOT/debug-build.log" "${debug_build[@]}"
debug_app="$(resolve_exact_app "$DEBUG_DERIVED_ROOT" "$RUN_ROOT/debug-apps.list")"
debug_xctestrun="$(find "$DEBUG_DERIVED_ROOT" -type f -name '*.xctestrun' -print -quit)"
if [ -z "$debug_xctestrun" ]; then
    fail "debug-build" "build-for-testing produced no .xctestrun under $DEBUG_DERIVED_ROOT"
fi
printf 'DEBUG_PRODUCT_EVIDENCE: app=%s xctestrun=%s\n' "$debug_app" "$debug_xctestrun"

release_build=(
    xcodebuild
    -workspace shafinMultitool.xcworkspace
    -scheme "$SCHEME"
    -configuration Release
    -destination 'generic/platform=iOS'
    -derivedDataPath "$RELEASE_DERIVED_ROOT"
    CODE_SIGNING_ALLOWED=NO
    COMPILER_INDEX_STORE_ENABLE=NO
    build
)
run_logged_command "7" "Release build" "$RUN_ROOT/release-build.log" "${release_build[@]}"
release_app="$(resolve_exact_app "$RELEASE_DERIVED_ROOT" "$RUN_ROOT/release-apps.list")"
printf 'RELEASE_APP: %s\n' "$release_app"

release_validation=(
    "$BUNDLE_VALIDATOR"
    --repo-root "$REPO_ROOT"
    --source-manifest "$SOURCE_MANIFEST"
    --app "$release_app"
)
run_logged_command "8" "Release bundle validation" "$RUN_ROOT/release-validation.log" "${release_validation[@]}"
cat "$RUN_ROOT/release-validation.log"

fixture_test=(
    "$FIXTURE_TEST"
    --release-app "$release_app"
)
run_logged_command "9" "Release bundle contamination fixtures" "$RUN_ROOT/release-fixtures.log" "${fixture_test[@]}"
cat "$RUN_ROOT/release-fixtures.log"

manifest_count="$(extract_metric MANIFEST_COUNT "$RUN_ROOT/release-validation.log")"
total_app_kib="$(extract_metric TOTAL_APP_KIB "$RUN_ROOT/release-validation.log")"
material_count="$(extract_metric MATERIAL_CONTRIBUTOR_COUNT "$RUN_ROOT/release-validation.log")"
known_blocker_count="$(extract_metric KNOWN_BLOCKER_COUNT "$RUN_ROOT/release-validation.log")"

printf 'PASS RELEASE GATES: commit=%s dirty=%s debug_product=%s release_app=%s manifest_count=%s total_app_kib=%s material_contributors=%s known_blockers=%s provenance_validators=2 contamination_fixtures=6 owned_output_root=%s\n' \
    "$TESTED_COMMIT" \
    "$TESTED_DIRTY" \
    "$debug_app" \
    "$release_app" \
    "$manifest_count" \
    "$total_app_kib" \
    "$material_count" \
    "$known_blocker_count" \
    "$OWNED_ROOT"
