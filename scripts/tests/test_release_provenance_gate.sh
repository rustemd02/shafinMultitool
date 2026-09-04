#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd -P)"
GATE="$REPO_ROOT/scripts/run_release_gates.sh"
ORIGINAL_PATH="$PATH"
TEMP_ROOT=""

fail() {
    printf 'FAIL: stage=release-provenance-orchestration reason=%s\n' "$*" >&2
    exit 1
}

cleanup() {
    if [ -n "${TEMP_ROOT:-}" ] && [ -d "$TEMP_ROOT" ]; then
        rm -rf -- "$TEMP_ROOT"
    fi
}

trap cleanup EXIT HUP INT TERM

assert_absent() {
    local token="$1"
    local path="$2"

    if grep -Fq -- "$token" "$path"; then
        fail "unexpected token '$token' in $path"
    fi
}

assert_present() {
    local token="$1"
    local path="$2"

    if ! grep -Fq -- "$token" "$path"; then
        fail "missing token '$token' in $path"
    fi
}

line_number() {
    local token="$1"
    local path="$2"

    grep -n -F -- "$token" "$path" | sed -n '1p' | cut -d: -f1
}

run_case() {
    local label="$1"
    local failure_mode="$2"
    local expected_status="$3"
    local case_root="$TEMP_ROOT/$label"
    local fake_bin="$case_root/fake bin"
    local derived_root="$case_root/derived root with spaces"
    local resolved_derived_root
    local invocation_log="$case_root/invocations.log"
    local gate_log="$case_root/gate.log"
    local status
    local llama_line
    local circle_line
    local xcode_line

    mkdir -p -- "$fake_bin" "$derived_root"
    resolved_derived_root="$(CDPATH= cd -- "$derived_root" && pwd -P)"

    printf '%s\n' \
        '#!/bin/bash' \
        'set -euo pipefail' \
        'printf "python3" >> "$FAKE_GATE_LOG"' \
        'for argument in "$@"; do printf "\\t%s" "$argument" >> "$FAKE_GATE_LOG"; done' \
        'printf "\\n" >> "$FAKE_GATE_LOG"' \
        'case "$FAKE_PROVENANCE_FAILURE:$1" in' \
        '    llama:*validate_llama_framework_provenance.py) exit 41 ;;' \
        '    circle:*validate_circle_asset_provenance.py) exit 42 ;;' \
        'esac' \
        'exit 0' > "$fake_bin/python3"
    chmod +x "$fake_bin/python3"

    printf '%s\n' \
        '#!/bin/bash' \
        'set -euo pipefail' \
        'printf "xcodebuild" >> "$FAKE_GATE_LOG"' \
        'for argument in "$@"; do printf "\\t%s" "$argument" >> "$FAKE_GATE_LOG"; done' \
        'printf "\\n" >> "$FAKE_GATE_LOG"' \
        'exit 77' > "$fake_bin/xcodebuild"
    chmod +x "$fake_bin/xcodebuild"

    set +e
    PATH="$fake_bin:$ORIGINAL_PATH" \
    FAKE_GATE_LOG="$invocation_log" \
    FAKE_PROVENANCE_FAILURE="$failure_mode" \
    "$GATE" --derived-data-root "$derived_root" > "$gate_log" 2>&1
    status=$?
    set -e

    if [ "$status" -ne "$expected_status" ]; then
        sed -n '1,160p' "$gate_log" >&2 || true
        fail "$label exited $status, expected $expected_status"
    fi
    assert_present 'validate_llama_framework_provenance.py' "$invocation_log"
    assert_absent '--upstream-checkout' "$invocation_log"

    if [ "$failure_mode" = "" ]; then
        assert_present 'validate_circle_asset_provenance.py' "$invocation_log"
        assert_present 'xcodebuild' "$invocation_log"
        llama_line="$(line_number 'validate_llama_framework_provenance.py' "$invocation_log")"
        circle_line="$(line_number 'validate_circle_asset_provenance.py' "$invocation_log")"
        xcode_line="$(line_number 'xcodebuild' "$invocation_log")"
        if [ -z "$llama_line" ] || [ -z "$circle_line" ] || [ -z "$xcode_line" ] || \
            [ "$llama_line" -ge "$circle_line" ] || [ "$circle_line" -ge "$xcode_line" ]; then
            fail "$label did not run llama, Circle, then xcodebuild in order"
        fi
        assert_present "$resolved_derived_root/shafin-release-gates/DebugDerivedData" "$invocation_log"
        [ -f "$derived_root/shafin-release-gates/llama-provenance.log" ] || fail "$label missing llama log"
        [ -f "$derived_root/shafin-release-gates/circle-provenance.log" ] || fail "$label missing Circle log"
    elif [ "$failure_mode" = "llama" ]; then
        assert_absent 'validate_circle_asset_provenance.py' "$invocation_log"
        assert_absent 'xcodebuild' "$invocation_log"
    elif [ "$failure_mode" = "circle" ]; then
        assert_present 'validate_circle_asset_provenance.py' "$invocation_log"
        assert_absent 'xcodebuild' "$invocation_log"
    else
        fail "unknown fixture failure mode: $failure_mode"
    fi

    printf 'PASS provenance orchestration fixture: label=%s exit=%s\n' "$label" "$status"
}

[ -x "$GATE" ] || fail "canonical gate is missing or not executable: $GATE"
assert_present 'validate_release_component_status.py' "$REPO_ROOT/scripts/validate_release_bundle.sh"
assert_present 'release-component-status.json' "$REPO_ROOT/scripts/validate_release_bundle.sh"
assert_absent 'component=llama.framework owner_task=' "$REPO_ROOT/scripts/validate_release_bundle.sh"
assert_absent 'component=Circle.usdz owner_task=' "$REPO_ROOT/scripts/validate_release_bundle.sh"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/release-provenance-gate.XXXXXX")"

run_case success-before-build "" 77
run_case llama-failure llama 41
run_case circle-failure circle 42

printf 'PASS release provenance orchestration self-test: pre-build ordering, fail-fast, offline args, separate logs, and spaced paths\n'
