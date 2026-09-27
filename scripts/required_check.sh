#!/bin/bash
#
# REL-003 — minimal required check for SET OS 1.0 (tracker §16).
#
# Deterministic, self-contained release-gate support check:
#   (1) source sanity — ML contract validators (stdlib/jsonschema, no network):
#         ml/camera_coach/contracts/check_production_heads_v1.py
#         ml/camera_coach/contracts/validate_camera_release_label.py (+ pinned fixtures)
#   (2) Pods prebuild with IPHONEOS_DEPLOYMENT_TARGET=15.0 override — the documented
#       Xcode 27.0 drift workaround (receipts/2026-09-22-cam-003-calibration-contract.md):
#       the checked-in Pods project pins deployment targets 12.0/14.0 which the 27.0 SDK
#       refuses; prebuilding Pods into the scratch DerivedData lets the app/test targets
#       build from the -project lane with their own real deployment target (17.0).
#       No repository file is modified by this override.
#   (3) M0 smoke lane from docs/implementation/test-command-matrix-v1.md (blocking
#       minimum, 133 tests: safety gate / good-frame policy / verifier / planner /
#       CAM-009 runtime+safety selectors), serial, scratch DerivedData under /tmp.
#   (4) privacy/provenance — scripts/validate_privacy_manifest.sh against the source
#       manifest AND the app bundle just built in (3).
#
# Invariants enforced (test-command-matrix-v1.md §2):
#   - zero-test run = FAILURE: the declared "Executed N tests" summary must exist,
#     N must equal the declared M0 count, and every -only-testing mask must be
#     observed as executed in the raw log.
#   - any test failure = FAILURE. Known diagnostic/perceptual pages are NOT part of
#     M0 and are NOT masked here; if M0 goes red the check goes red.
#
# Ownership / boundaries:
#   - This script does not modify tests, schemes, project files, or any tracked file.
#   - Scratch DerivedData and logs live only in /tmp and are removed on exit unless
#     REQUIRED_CHECK_KEEP=1.
#   - Enabling real CI (push, hosted runner wiring, secrets) is the owner's decision;
#     see .github/workflows/required-check.yml for the unverified hosted-runner config.
#
# Environment overrides (all optional, no secrets):
#   REQUIRED_CHECK_DESTINATION   xcodebuild destination (default: matrix-pinned UDID)
#   REQUIRED_CHECK_DERIVED_DATA  scratch path (default: mktemp under /tmp)
#   REQUIRED_CHECK_KEEP          set to 1 to keep the scratch dir after the run
#
# Exit codes: 0 = all steps passed; 1 = a step failed (see the PASS/FAIL summary).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

DESTINATION="${REQUIRED_CHECK_DESTINATION:-id=1F680A42-CEB3-43E8-9CED-52F874962A62}"  # iPhone 17e, iOS 26.5 (matrix M0 pin)
SCRATCH="${REQUIRED_CHECK_DERIVED_DATA:-$(mktemp -d /tmp/setos-required-check.XXXXXX)}"
KEEP="${REQUIRED_CHECK_KEEP:-0}"
DERIVED_DATA="$SCRATCH/dd"
LOG_DIR="$SCRATCH/logs"
EXPECTED_M0_TESTS=133  # test-command-matrix-v1.md §3 M0: 125 (5 classes: 19+8+28+39+31) + 8 method masks
SUMMARY=()

mkdir -p "$LOG_DIR" "$DERIVED_DATA"

cleanup() {
    if [ "$KEEP" = "1" ]; then
        echo "[required-check] scratch kept at: $SCRATCH"
    else
        rm -rf "$SCRATCH"
    fi
}
trap cleanup EXIT HUP INT TERM

step_banner() {
    echo ""
    echo "=== [required-check] $1 ==="
}

record_pass() { SUMMARY+=("PASS  $1"); echo "PASS: $1"; }
record_fail() { SUMMARY+=("FAIL  $1"); echo "FAIL: $1"; }

fail_step() {  # record_fail + fail-fast exit with pointer to log
    record_fail "$1"
    echo ""
    echo "=== [required-check] SUMMARY (failed) ==="
    printf '%s\n' "${SUMMARY[@]}"
    echo "[required-check] failing log: $2"
    exit 1
}

echo "[required-check] repo root : $REPO_ROOT"
echo "[required-check] scratch   : $SCRATCH"
echo "[required-check] destination: $DESTINATION"
echo "[required-check] HEAD      : $(git rev-parse HEAD 2>/dev/null || echo 'git unavailable')"

# ---------------------------------------------------------------------------
# Step 1 — source sanity: ML contract validators (REL-001 M4 validators subset)
# ---------------------------------------------------------------------------
step_banner "Step 1/4: source sanity (ML contract validators)"

HEADS_LOG="$LOG_DIR/step1_check_production_heads.log"
LABEL_LOG="$LOG_DIR/step1_validate_release_label.log"

if python3 ml/camera_coach/contracts/check_production_heads_v1.py > "$HEADS_LOG" 2>&1; then
    tail -3 "$HEADS_LOG"
    record_pass "source sanity: check_production_heads_v1.py (production heads contract)"
else
    echo "--- check_production_heads_v1.py output ---"; cat "$HEADS_LOG"
    fail_step "source sanity: check_production_heads_v1.py FAILED" "$HEADS_LOG"
fi

if python3 ml/camera_coach/contracts/validate_camera_release_label.py > "$LABEL_LOG" 2>&1; then
    tail -5 "$LABEL_LOG"
    record_pass "source sanity: validate_camera_release_label.py (schema + positive/negative fixtures)"
else
    echo "--- validate_camera_release_label.py output ---"; cat "$LABEL_LOG"
    fail_step "source sanity: validate_camera_release_label.py FAILED" "$LABEL_LOG"
fi

# ---------------------------------------------------------------------------
# Step 2 — Pods prebuild (documented Xcode 27.0 deployment-target workaround)
# ---------------------------------------------------------------------------
step_banner "Step 2/4: Pods prebuild (IPHONEOS_DEPLOYMENT_TARGET=15.0 override, no repo file changed)"

PODS_LOG="$LOG_DIR/step2_pods_prebuild.log"
set +e
xcodebuild -workspace shafinMultitool.xcworkspace -scheme Pods-shafinMultitool \
    -sdk iphonesimulator -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA" \
    IPHONEOS_DEPLOYMENT_TARGET=15.0 \
    build > "$PODS_LOG" 2>&1
PODS_RC=$?
set -e
tail -5 "$PODS_LOG"
if [ "$PODS_RC" -ne 0 ] || ! grep -q "BUILD SUCCEEDED" "$PODS_LOG"; then
    fail_step "Pods prebuild FAILED (rc=$PODS_RC)" "$PODS_LOG"
fi
record_pass "Pods prebuild (deployment-target override, scratch derived data)"

# ---------------------------------------------------------------------------
# Step 3 — M0 smoke lane (test-command-matrix-v1.md §3 M0, blocking minimum)
# ---------------------------------------------------------------------------
step_banner "Step 3/4: M0 smoke lane ($EXPECTED_M0_TESTS declared tests, serial, scratch DerivedData)"

TEST_LOG="$LOG_DIR/step3_m0_smoke_xcodebuild.log"
set +e
xcodebuild -project shafinMultitool.xcodeproj -scheme shafinMultitool \
    -sdk iphonesimulator -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA" \
    -parallel-testing-enabled NO -collect-test-diagnostics never \
    -only-testing:shafinMultitoolTests/CameraAdviceSafetyGateTests \
    -only-testing:shafinMultitoolTests/GoodFramePreservationPolicyTests \
    -only-testing:shafinMultitoolTests/ActionVerifierTests \
    -only-testing:shafinMultitoolTests/UserMovementObserverTests \
    -only-testing:shafinMultitoolTests/SemanticTipPlannerTests \
    -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testPauseStylePreservationCannotReopenGoodWithoutCurrentTechnicalMeasurement \
    -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testStillImageReplaySuppressesFalseKeepForBadTechnicalFrames \
    -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testStillImageReplayPreservesLowKeyMoodKeepDespiteTechnicalFuture \
    -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testStillImageReplayPreservesReadableObjectInsertDespiteWindowHotspot \
    -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testStillImageReplayDoesNotOvercorrectCinematicGoodObjectInsertFrames \
    -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testGoodPauseVerdictWithExplicitStrengthUsesHighConfidenceFloor \
    -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testGoodPauseVerdictWithoutStrengthKeepsConservativeConfidence \
    -only-testing:shafinMultitoolTests/CameraCoachClosedLoopTests/testFreshReplanningPreservesEpisodeThroughVerification \
    test > "$TEST_LOG" 2>&1
TEST_RC=$?
set -e

# --- zero-test rule: parse the final "Executed N tests, with F failures" summary ---
EXEC_LINE="$(grep -E 'Executed [0-9]+ tests, with [0-9]+ failures' "$TEST_LOG" | tail -1 || true)"
if [ -z "$EXEC_LINE" ]; then
    tail -20 "$TEST_LOG"
    fail_step "M0 smoke: no 'Executed N tests' summary found — run aborted before executing any test (zero-test run = failure)" "$TEST_LOG"
fi
EXEC_N="$(printf '%s' "$EXEC_LINE" | sed -E 's/.*Executed ([0-9]+) tests.*/\1/')"
EXEC_F="$(printf '%s' "$EXEC_LINE" | sed -E 's/.*with ([0-9]+) failures.*/\1/')"
echo "[required-check] final summary line: $EXEC_LINE"
echo "[required-check] xcodebuild rc=$TEST_RC, executed=$EXEC_N, failures=$EXEC_F, expected=$EXPECTED_M0_TESTS"

if [ "$EXEC_N" -eq 0 ]; then
    fail_step "M0 smoke: executed 0 tests (zero-test run = failure)" "$TEST_LOG"
fi
if [ "$EXEC_N" -ne "$EXPECTED_M0_TESTS" ]; then
    fail_step "M0 smoke: executed $EXEC_N tests but the matrix declares $EXPECTED_M0_TESTS — declared tests were not all executed" "$TEST_LOG"
fi
if [ "$EXEC_F" -ne 0 ]; then
    echo "--- failing test cases ---"
    grep -E "Test Case .* (failed|' failed)" "$TEST_LOG" | tail -20 || true
    fail_step "M0 smoke: $EXEC_F test failure(s) — red is reported red, no diagnostic masking" "$TEST_LOG"
fi
if [ "$TEST_RC" -ne 0 ] || ! grep -q "TEST SUCCEEDED" "$TEST_LOG"; then
    fail_step "M0 smoke: xcodebuild did not report TEST SUCCEEDED (rc=$TEST_RC)" "$TEST_LOG"
fi

# --- every declared mask must be observed as executed in the raw log ---
MISSING_MASKS=()
for cls in CameraAdviceSafetyGateTests GoodFramePreservationPolicyTests ActionVerifierTests UserMovementObserverTests SemanticTipPlannerTests; do
    if ! grep -q "Test Suite '$cls' passed" "$TEST_LOG"; then
        MISSING_MASKS+=("class $cls")
    fi
done
for m in \
    testPauseStylePreservationCannotReopenGoodWithoutCurrentTechnicalMeasurement \
    testStillImageReplaySuppressesFalseKeepForBadTechnicalFrames \
    testStillImageReplayPreservesLowKeyMoodKeepDespiteTechnicalFuture \
    testStillImageReplayPreservesReadableObjectInsertDespiteWindowHotspot \
    testStillImageReplayDoesNotOvercorrectCinematicGoodObjectInsertFrames \
    testGoodPauseVerdictWithExplicitStrengthUsesHighConfidenceFloor \
    testGoodPauseVerdictWithoutStrengthKeepsConservativeConfidence \
    testFreshReplanningPreservesEpisodeThroughVerification; do
    # xcodebuild prints: Test Case '-[Target.Class method]' passed (N.NNN seconds).
    test_fingerprint="${m}]' passed"
    if ! grep -qF "$test_fingerprint" "$TEST_LOG"; then
        MISSING_MASKS+=("method $m")
    fi
done
if [ "${#MISSING_MASKS[@]}" -gt 0 ]; then
    printf 'missing from log: %s\n' "${MISSING_MASKS[@]}"
    fail_step "M0 smoke: ${#MISSING_MASKS[@]} declared -only-testing mask(s) not observed as executed" "$TEST_LOG"
fi
record_pass "M0 smoke lane: $EXEC_N tests executed, 0 failures, all declared masks observed (serial)"

# ---------------------------------------------------------------------------
# Step 4 — privacy/provenance: source manifest vs the app bundle just built
# ---------------------------------------------------------------------------
step_banner "Step 4/4: privacy manifest validation (source + built app)"

APP_PATH="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/shafinMultitool.app"
PRIVACY_LOG="$LOG_DIR/step4_privacy_manifest.log"
if [ ! -d "$APP_PATH" ]; then
    fail_step "built app bundle missing after M0 run: $APP_PATH" "$TEST_LOG"
fi
if scripts/validate_privacy_manifest.sh \
    --source-manifest shafinMultitool/PrivacyInfo.xcprivacy \
    --app "$APP_PATH" > "$PRIVACY_LOG" 2>&1; then
    tail -4 "$PRIVACY_LOG"
    record_pass "privacy manifest: source + built app validated (root + SnapKit nested, 4 required-reason entries)"
else
    echo "--- validate_privacy_manifest.sh output ---"; cat "$PRIVACY_LOG"
    fail_step "privacy manifest validation FAILED" "$PRIVACY_LOG"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "=== [required-check] SUMMARY ==="
printf '%s\n' "${SUMMARY[@]}"
echo "REQUIRED CHECK: PASSED"
exit 0
