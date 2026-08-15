#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

# This baseline is evidence-bound. Enabling a production backend, analytics,
# or remote visual provider requires a privacy re-audit before release.

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
TEMP_ROOT=""
TEMP_INDEX=0

EXPECTED_TOP_LEVEL_KEYS=(
    NSPrivacyTracking
    NSPrivacyTrackingDomains
    NSPrivacyCollectedDataTypes
    NSPrivacyAccessedAPITypes
)

DEFAULT_ROOT_RELATIVE_PATH="PrivacyInfo.xcprivacy"
DEFAULT_SNAPKIT_RELATIVE_PATH="Frameworks/SnapKit.framework/SnapKit_Privacy.bundle/PrivacyInfo.xcprivacy"

source_manifest=""
app_path=""
self_test=0
allow_relative_paths=(
    "$DEFAULT_ROOT_RELATIVE_PATH"
    "$DEFAULT_SNAPKIT_RELATIVE_PATH"
)

usage() {
    cat <<'EOF'
Usage:
  scripts/validate_privacy_manifest.sh \
    --source-manifest /path/to/PrivacyInfo.xcprivacy \
    --app /path/to/shafinMultitool.app \
    [--allow-relative-path path/to/PrivacyInfo.xcprivacy ...]

  scripts/validate_privacy_manifest.sh \
    --self-test \
    --source-manifest /path/to/PrivacyInfo.xcprivacy

The built app must contain exactly the root app manifest and the SnapKit
nested manifest by default. Additional exact relative manifest paths may be
allowlisted with repeated --allow-relative-path options.
EOF
}

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

cleanup() {
    if [ -n "${TEMP_ROOT:-}" ] && [ -d "$TEMP_ROOT" ]; then
        rm -rf "$TEMP_ROOT"
    fi
}

trap cleanup EXIT HUP INT TERM

ensure_temp_root() {
    if [ -z "$TEMP_ROOT" ]; then
        TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/privacy-manifest-validator.XXXXXX")"
    fi
}

next_temp_path() {
    TEMP_INDEX=$((TEMP_INDEX + 1))
    printf '%s/%s-%s.plist\n' "$TEMP_ROOT" "$1" "$TEMP_INDEX"
}

validate_relative_path() {
    case "$1" in
        ""|/*|../*|*/../*|*/..|.)
            fail "allowlisted manifest path must be an exact relative path: '$1'"
            ;;
    esac
}

plist_type() {
    local manifest="$1"
    local key_path="$2"
    plutil -type "$key_path" -- "$manifest" 2>/dev/null
}

plist_raw() {
    local manifest="$1"
    local key_path="$2"
    plutil -extract "$key_path" raw -o - -- "$manifest" 2>/dev/null
}

assert_type() {
    local manifest="$1"
    local key_path="$2"
    local expected_type="$3"
    local actual_type

    if ! actual_type="$(plist_type "$manifest" "$key_path")"; then
        fail "$(basename "$manifest"): missing or unreadable key '$key_path'"
    fi
    if [ "$actual_type" != "$expected_type" ]; then
        fail "$(basename "$manifest"): key '$key_path' has type '$actual_type', expected '$expected_type'"
    fi
}

assert_raw_value() {
    local manifest="$1"
    local key_path="$2"
    local expected_value="$3"
    local actual_value

    if ! actual_value="$(plist_raw "$manifest" "$key_path")"; then
        fail "$(basename "$manifest"): missing or unreadable key '$key_path'"
    fi
    if [ "$actual_value" != "$expected_value" ]; then
        fail "$(basename "$manifest"): key '$key_path' is '$actual_value', expected '$expected_value'"
    fi
}

assert_exact_keys() {
    local manifest="$1"
    shift
    local residual
    local key
    local remaining_keys

    residual="$(next_temp_path residual)"
    cp "$manifest" "$residual"
    for key in "$@"; do
        if ! plutil -remove "$key" "$residual" >/dev/null 2>&1; then
            fail "$(basename "$manifest"): expected key '$key' is missing"
        fi
    done

    if ! remaining_keys="$(plutil -convert json -o - -- "$residual" | tr -d '[:space:]')"; then
        fail "$(basename "$manifest"): could not inspect remaining plist keys"
    fi
    if [ "$remaining_keys" != "{}" ]; then
        fail "$(basename "$manifest"): unexpected plist keys remain: $remaining_keys"
    fi
}

lint_manifest() {
    local manifest="$1"
    local description="$2"

    if [ ! -f "$manifest" ]; then
        fail "$description manifest is missing: $manifest"
    fi
    if ! plutil -lint -- "$manifest" >/dev/null 2>&1; then
        fail "$description manifest does not plutil-lint: $manifest"
    fi
}

validate_app_baseline_manifest() {
    local manifest="$1"
    local description="$2"
    local entry_manifest

    lint_manifest "$manifest" "$description"
    assert_exact_keys "$manifest" "${EXPECTED_TOP_LEVEL_KEYS[@]}"

    assert_type "$manifest" "NSPrivacyTracking" bool
    assert_raw_value "$manifest" "NSPrivacyTracking" false

    assert_type "$manifest" "NSPrivacyTrackingDomains" array
    assert_raw_value "$manifest" "NSPrivacyTrackingDomains" 0

    assert_type "$manifest" "NSPrivacyCollectedDataTypes" array
    assert_raw_value "$manifest" "NSPrivacyCollectedDataTypes" 0

    assert_type "$manifest" "NSPrivacyAccessedAPITypes" array
    assert_raw_value "$manifest" "NSPrivacyAccessedAPITypes" 1
    assert_type "$manifest" "NSPrivacyAccessedAPITypes.0" dictionary

    entry_manifest="$(next_temp_path required-reason-entry)"
    if ! plutil -extract "NSPrivacyAccessedAPITypes.0" xml1 -o "$entry_manifest" -- "$manifest" >/dev/null 2>&1; then
        fail "$(basename "$manifest"): could not inspect required-reason entry"
    fi
    if ! plutil -lint -- "$entry_manifest" >/dev/null 2>&1; then
        fail "$(basename "$manifest"): required-reason entry is not a valid plist"
    fi
    assert_exact_keys "$entry_manifest" "NSPrivacyAccessedAPIType" "NSPrivacyAccessedAPITypeReasons"

    assert_type "$manifest" "NSPrivacyAccessedAPITypes.0.NSPrivacyAccessedAPIType" string
    assert_raw_value "$manifest" "NSPrivacyAccessedAPITypes.0.NSPrivacyAccessedAPIType" "NSPrivacyAccessedAPICategoryUserDefaults"
    assert_type "$manifest" "NSPrivacyAccessedAPITypes.0.NSPrivacyAccessedAPITypeReasons" array
    assert_raw_value "$manifest" "NSPrivacyAccessedAPITypes.0.NSPrivacyAccessedAPITypeReasons" 1
    assert_type "$manifest" "NSPrivacyAccessedAPITypes.0.NSPrivacyAccessedAPITypeReasons.0" string
    assert_raw_value "$manifest" "NSPrivacyAccessedAPITypes.0.NSPrivacyAccessedAPITypeReasons.0" "CA92.1"

    printf 'PASS %s baseline: tracking=false, trackingDomains=0, collectedDataTypes=0, requiredReasonEntries=1, category=NSPrivacyAccessedAPICategoryUserDefaults, reasons=CA92.1\n' "$description"
}

is_allowed_relative_path() {
    local candidate="$1"
    local allowed

    for allowed in "${allow_relative_paths[@]}"; do
        if [ "$candidate" = "$allowed" ]; then
            return 0
        fi
    done
    return 1
}

validate_built_app() {
    local root_manifest="$app_path/$DEFAULT_ROOT_RELATIVE_PATH"
    local snapkit_manifest="$app_path/$DEFAULT_SNAPKIT_RELATIVE_PATH"
    local manifest_list
    local manifest_path
    local relative_path
    local root_count=0
    local manifest_count=0

    if [ ! -d "$app_path" ]; then
        fail "built app directory is missing: $app_path"
    fi

    manifest_list="$(next_temp_path built-manifests)"
    if ! find "$app_path" -type f -name PrivacyInfo.xcprivacy -print | sort > "$manifest_list"; then
        fail "could not enumerate PrivacyInfo.xcprivacy files under $app_path"
    fi

    while IFS= read -r manifest_path; do
        [ -n "$manifest_path" ] || continue
        manifest_count=$((manifest_count + 1))
        case "$manifest_path" in
            "$app_path"/*)
                relative_path="${manifest_path#"$app_path"/}"
                ;;
            *)
                fail "manifest path is outside the supplied app: $manifest_path"
                ;;
        esac

        if [ "$relative_path" = "$DEFAULT_ROOT_RELATIVE_PATH" ]; then
            root_count=$((root_count + 1))
        fi
        if ! is_allowed_relative_path "$relative_path"; then
            fail "unexpected PrivacyInfo.xcprivacy in built app at exact relative path '$relative_path'"
        fi
    done < "$manifest_list"

    if [ "$root_count" -ne 1 ] || [ ! -f "$root_manifest" ]; then
        fail "built app must contain exactly one root PrivacyInfo.xcprivacy; found $root_count"
    fi
    if [ ! -f "$snapkit_manifest" ]; then
        fail "SnapKit nested privacy manifest is missing: $DEFAULT_SNAPKIT_RELATIVE_PATH"
    fi

    validate_app_baseline_manifest "$root_manifest" "built root app"
    lint_manifest "$snapkit_manifest" "SnapKit nested"
    printf 'PASS built app manifest inventory: total=%s, root=1, SnapKit nested=1, no unexpected paths\n' "$manifest_count"
}

expect_failure() {
    local label="$1"
    shift
    local log_path="$TEMP_ROOT/$label.log"

    if "$@" > "$log_path" 2>&1; then
        fail "negative fixture unexpectedly passed: $label"
    fi
    printf 'PASS negative fixture: %s (validator rejected it)\n' "$label"
}

run_self_test() {
    local fixture_app="$TEMP_ROOT/fixture.app"
    local fixture_nested="$fixture_app/$DEFAULT_SNAPKIT_RELATIVE_PATH"
    local missing_app="$TEMP_ROOT/missing-root.app"
    local wrong_reason_app="$TEMP_ROOT/wrong-reason.app"
    local unexpected_extra_app="$TEMP_ROOT/unexpected-extra.app"

    mkdir -p "$(dirname "$fixture_nested")"
    cp "$source_manifest" "$fixture_app/$DEFAULT_ROOT_RELATIVE_PATH"
    cp "$source_manifest" "$fixture_nested"

    "$SCRIPT_PATH" --source-manifest "$source_manifest" --app "$fixture_app"

    cp -R "$fixture_app" "$missing_app"
    rm -f "$missing_app/$DEFAULT_ROOT_RELATIVE_PATH"
    expect_failure missing-root "$SCRIPT_PATH" --source-manifest "$source_manifest" --app "$missing_app"

    cp -R "$fixture_app" "$wrong_reason_app"
    if ! plutil -replace "NSPrivacyAccessedAPITypes.0.NSPrivacyAccessedAPITypeReasons.0" -string CA92.2 "$wrong_reason_app/$DEFAULT_ROOT_RELATIVE_PATH" >/dev/null 2>&1; then
        fail "could not create wrong-reason negative fixture"
    fi
    expect_failure wrong-reason "$SCRIPT_PATH" --source-manifest "$source_manifest" --app "$wrong_reason_app"

    cp -R "$fixture_app" "$unexpected_extra_app"
    mkdir -p "$unexpected_extra_app/Frameworks/Unexpected.framework"
    cp "$source_manifest" "$unexpected_extra_app/Frameworks/Unexpected.framework/PrivacyInfo.xcprivacy"
    expect_failure unexpected-extra "$SCRIPT_PATH" --source-manifest "$source_manifest" --app "$unexpected_extra_app"

    printf 'PASS validator self-test: positive, missing-root, wrong-reason, unexpected-extra\n'
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --source-manifest)
            [ "$#" -ge 2 ] || fail "--source-manifest requires a path"
            source_manifest="$2"
            shift 2
            ;;
        --app)
            [ "$#" -ge 2 ] || fail "--app requires a path"
            app_path="${2%/}"
            shift 2
            ;;
        --allow-relative-path)
            [ "$#" -ge 2 ] || fail "--allow-relative-path requires a path"
            validate_relative_path "$2"
            allow_relative_paths+=("$2")
            shift 2
            ;;
        --self-test)
            self_test=1
            shift
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

[ -n "$source_manifest" ] || { usage >&2; fail "--source-manifest is required"; }
ensure_temp_root
lint_manifest "$source_manifest" "source"

if [ "$self_test" -eq 1 ]; then
    [ -z "$app_path" ] || fail "--app is not used with --self-test"
    run_self_test
    exit 0
fi

[ -n "$app_path" ] || { usage >&2; fail "--app is required unless --self-test is used"; }
validate_app_baseline_manifest "$source_manifest" "source"
validate_built_app
printf 'PASS privacy manifest validation\n'
