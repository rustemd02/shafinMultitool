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
checks the known-blocked clean copy, then checks eleven independent metadata
and contamination fixtures. The supplied app is never modified.
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
    if ! cp -R "$RELEASE_APP" "$destination/shafinMultitool.app"; then
        fail "could not copy Release app fixture: label=$label"
    fi
    printf '%s\n' "$destination/shafinMultitool.app"
}

assert_fixture_failure() {
    local label="$1"
    local expected_token="$2"
    local fixture_app="$3"
    local assetutil_override="${4:-}"
    local log_path="$TEMP_ROOT/$label.log"
    local status
    local matched_output

    set +e
    if [ -n "$assetutil_override" ]; then
        ASSETUTIL_BIN_OVERRIDE="$assetutil_override" "$BUNDLE_VALIDATOR" \
            --repo-root "$REPO_ROOT" \
            --source-manifest "$SOURCE_MANIFEST" \
            --app "$fixture_app" > "$log_path" 2>&1
    else
        "$BUNDLE_VALIDATOR" \
            --repo-root "$REPO_ROOT" \
            --source-manifest "$SOURCE_MANIFEST" \
            --app "$fixture_app" > "$log_path" 2>&1
    fi
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
if ! tar -cf "$TEMP_ROOT/clean-before.tar" -C "$clean_app" .; then
    fail "could not snapshot clean copied Release app"
fi
set +e
"$BUNDLE_VALIDATOR" \
    --repo-root "$REPO_ROOT" \
    --source-manifest "$SOURCE_MANIFEST" \
    --app "$clean_app" > "$TEMP_ROOT/clean.log" 2>&1
clean_status=$?
set -e
if [ "$clean_status" -eq 0 ]; then
    cat "$TEMP_ROOT/clean.log" >&2
    fail "clean copied Release app unexpectedly passed"
fi
if ! grep -Fq 'release blocked by 5 known provenance blocker(s)' "$TEMP_ROOT/clean.log"; then
    cat "$TEMP_ROOT/clean.log" >&2
    fail "clean validation failed without stable known-blocker token"
fi
if ! grep -Fq 'KNOWN_BLOCKER_COUNT=5' "$TEMP_ROOT/clean.log"; then
    cat "$TEMP_ROOT/clean.log" >&2
    fail "clean validation omitted KNOWN_BLOCKER_COUNT=5"
fi
if ! grep -Eq '^MANIFEST_COUNT=2$' "$TEMP_ROOT/clean.log" \
    || ! grep -Eq '^TOTAL_APP_KIB=[0-9]+$' "$TEMP_ROOT/clean.log" \
    || ! grep -Eq '^MATERIAL_CONTRIBUTOR_COUNT=[0-9]+$' "$TEMP_ROOT/clean.log"; then
    cat "$TEMP_ROOT/clean.log" >&2
    fail "clean validation omitted manifest or size metrics"
fi
if grep -Fq 'PASS RELEASE BUNDLE VALIDATION' "$TEMP_ROOT/clean.log"; then
    cat "$TEMP_ROOT/clean.log" >&2
    fail "clean validation emitted PASS RELEASE BUNDLE VALIDATION while blocked"
fi
find "$clean_app" -print0 > "$TEMP_ROOT/clean-after.paths"
if ! cmp -s "$TEMP_ROOT/clean-before.paths" "$TEMP_ROOT/clean-after.paths"; then
    fail "validation-only mode mutated the clean copied app"
fi
if ! tar -cf "$TEMP_ROOT/clean-after.tar" -C "$clean_app" .; then
    fail "could not snapshot validated clean Release app"
fi
if ! cmp -s "$TEMP_ROOT/clean-before.tar" "$TEMP_ROOT/clean-after.tar"; then
    fail "validation-only mode mutated clean app content or metadata"
fi
printf 'PASS clean copied Release app blocked by known provenance: exit=%s\n' "$clean_status"

missing_font_app="$(copy_fixture missing-declared-font)"
missing_font_name="$(plutil -extract 'UIAppFonts.0' raw -o - -- "$missing_font_app/Info.plist")"
[ -n "$missing_font_name" ] || fail "could not read first declared font from clean fixture"
rm -f "$missing_font_app/$missing_font_name"
assert_fixture_failure missing-declared-font 'declared UIAppFonts entry' "$missing_font_app"

missing_ru_strings_app="$(copy_fixture missing-ru-infoplist-strings)"
rm -f "$missing_ru_strings_app/ru.lproj/InfoPlist.strings"
assert_fixture_failure missing-ru-infoplist-strings 'ru.lproj/InfoPlist.strings file is missing' "$missing_ru_strings_app"

missing_bundle_version_app="$(copy_fixture missing-bundle-version)"
if ! plutil -remove CFBundleVersion -- "$missing_bundle_version_app/Info.plist"; then
    fail "could not remove CFBundleVersion from metadata fixture"
fi
assert_fixture_failure missing-bundle-version 'CFBundleVersion is empty or missing' "$missing_bundle_version_app"

wrong_scene_class_app="$(copy_fixture wrong-scene-class)"
if ! plutil -replace 'UIApplicationSceneManifest.UISceneConfigurations.UIWindowSceneSessionRoleApplication.0.UISceneClassName' -string 'WrongScene' -- "$wrong_scene_class_app/Info.plist"; then
    fail "could not replace UISceneClassName in metadata fixture"
fi
assert_fixture_failure wrong-scene-class 'UISceneClassName must be UIWindowScene' "$wrong_scene_class_app"

missing_appicon_app="$(copy_fixture missing-appicon)"
missing_appicon_assetutil="$TEMP_ROOT/assetutil-without-appicon"
if ! printf '%s\n' '#!/bin/sh' 'printf "[]\\n"' > "$missing_appicon_assetutil"; then
    fail "could not create assetutil fixture"
fi
chmod +x "$missing_appicon_assetutil"
assert_fixture_failure missing-appicon 'Assets.car does not contain asset Name AppIcon' "$missing_appicon_app" "$missing_appicon_assetutil"

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

printf 'PASS release bundle gate self-test: known-blocked clean plus eleven metadata/contamination fixtures\n'
