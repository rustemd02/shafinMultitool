#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd -P)"
BUNDLE_VALIDATOR="$REPO_ROOT/scripts/validate_release_bundle.sh"
SOURCE_MANIFEST="$REPO_ROOT/shafinMultitool/PrivacyInfo.xcprivacy"
RELEASE_APP=""
TEMP_ROOT=""

usage() {
    cat <<'EOF'
Usage:
  scripts/tests/test_release_bundle_gate.sh \
    --release-app /absolute/path/to/shafinMultitool.app

Copies the supplied fresh Release app to a temporary fixture directory,
validates the clean copy, then checks six independent contamination fixtures.
The supplied app is never modified.
EOF
}

fail() {
    printf 'FAIL: stage=release-bundle-fixtures reason=%s\n' "$*" >&2
    exit 1
}

cleanup() {
    if [ -n "${TEMP_ROOT:-}" ] && [ -d "$TEMP_ROOT" ]; then
        rm -rf "$TEMP_ROOT"
    fi
}

trap cleanup EXIT HUP INT TERM

copy_fixture() {
    local label="$1"
    local destination="$TEMP_ROOT/$label"

    mkdir -p "$destination"
    cp -R "$RELEASE_APP" "$destination/shafinMultitool.app"
    printf '%s\n' "$destination/shafinMultitool.app"
}

assert_fixture_failure() {
    local label="$1"
    local expected_token="$2"
    local fixture_app="$3"
    local log_path="$TEMP_ROOT/$label.log"
    local status
    local matched_output

    set +e
    "$BUNDLE_VALIDATOR" \
        --repo-root "$REPO_ROOT" \
        --source-manifest "$SOURCE_MANIFEST" \
        --app "$fixture_app" > "$log_path" 2>&1
    status=$?
    set -e
    if [ "$status" -eq 0 ]; then
        fail "$label unexpectedly passed"
    fi
    if ! grep -Fq "$expected_token" "$log_path"; then
        sed -n '1,120p' "$log_path" >&2
        fail "$label failed without stable token '$expected_token'"
    fi
    matched_output="$(grep -F "$expected_token" "$log_path" | sed -n '1p')"
    printf 'PASS negative fixture: label=%s exit=%s token=%s output=%s\n' \
        "$label" "$status" "$expected_token" "$matched_output"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --release-app)
            [ "$#" -ge 2 ] || fail "--release-app requires a path"
            RELEASE_APP="${2%/}"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            usage >&2
            fail "unknown argument: $1"
            ;;
    esac
done

[ -n "$RELEASE_APP" ] || fail "--release-app is required"
case "$RELEASE_APP" in
    /*)
        ;;
    *)
        fail "--release-app must be an absolute path: $RELEASE_APP"
        ;;
esac
if [ ! -d "$RELEASE_APP" ] || [ -L "$RELEASE_APP" ]; then
    fail "Release app is missing or is a symlink: $RELEASE_APP"
fi
if [ ! -x "$BUNDLE_VALIDATOR" ]; then
    fail "bundle validator is missing or not executable: $BUNDLE_VALIDATOR"
fi

TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/release-bundle-fixtures.XXXXXX")"
clean_app="$(copy_fixture clean)"

find "$clean_app" -print0 > "$TEMP_ROOT/clean-before.paths"
if ! "$BUNDLE_VALIDATOR" \
    --repo-root "$REPO_ROOT" \
    --source-manifest "$SOURCE_MANIFEST" \
    --app "$clean_app" > "$TEMP_ROOT/clean.log" 2>&1; then
    cat "$TEMP_ROOT/clean.log" >&2
    fail "clean copied Release app was rejected"
fi
if ! grep -Fq 'PASS RELEASE BUNDLE VALIDATION' "$TEMP_ROOT/clean.log"; then
    fail "clean validation did not emit PASS RELEASE BUNDLE VALIDATION"
fi
find "$clean_app" -print0 > "$TEMP_ROOT/clean-after.paths"
if ! cmp -s "$TEMP_ROOT/clean-before.paths" "$TEMP_ROOT/clean-after.paths"; then
    fail "validation-only mode mutated the clean copied app"
fi
printf 'PASS clean copied Release app validation\n'

device_benchmark_app="$(copy_fixture forbidden-devicebenchmark)"
mkdir -p "$device_benchmark_app/DeviceBenchmark"
printf 'fixture\n' > "$device_benchmark_app/DeviceBenchmark/fake.bin"
assert_fixture_failure forbidden-devicebenchmark 'forbidden DeviceBenchmark path component' "$device_benchmark_app"

gguf_app="$(copy_fixture forbidden-gguf)"
printf 'fixture\n' > "$gguf_app/fake.gguf"
assert_fixture_failure forbidden-gguf 'forbidden .gguf payload' "$gguf_app"

third_model_app="$(copy_fixture unknown-third-model)"
mkdir -p "$third_model_app/unknown_model.mlmodelc"
printf 'fixture\n' > "$third_model_app/unknown_model.mlmodelc/coremldata.bin"
assert_fixture_failure unknown-third-model 'unknown compiled model root' "$third_model_app"

extra_framework_app="$(copy_fixture unexpected-framework)"
mkdir -p "$extra_framework_app/Frameworks/Unexpected.framework"
printf 'fixture\n' > "$extra_framework_app/Frameworks/Unexpected.framework/Unexpected"
assert_fixture_failure unexpected-framework 'unexpected framework entry' "$extra_framework_app"

missing_privacy_app="$(copy_fixture missing-root-privacy)"
rm -f "$missing_privacy_app/PrivacyInfo.xcprivacy"
assert_fixture_failure missing-root-privacy 'built app must contain exactly one root PrivacyInfo.xcprivacy' "$missing_privacy_app"

extra_privacy_app="$(copy_fixture unexpected-extra-privacy)"
mkdir -p "$extra_privacy_app/Frameworks/Unexpected.bundle"
cp "$SOURCE_MANIFEST" "$extra_privacy_app/Frameworks/Unexpected.bundle/PrivacyInfo.xcprivacy"
assert_fixture_failure unexpected-extra-privacy 'unexpected PrivacyInfo.xcprivacy in built app at exact relative path' "$extra_privacy_app"

printf 'PASS release bundle contamination self-test: clean plus six negative fixtures\n'
