#!/bin/bash
# Camera/analysis certification recipe (2026-09-12; P03 fix 2026-09-13).
#
# Load-flake mitigation: the ClosedLoop capture-path tests drive real
# CMSampleBuffer delivery through a real-time scheduler. Under parallel
# simulator clone contention their wait windows can expire (0-2 failures per
# parallel run, all pass solo). Running the ClosedLoop suite serially in its own
# invocation isolates them from the heavy AnalysisPipelinePresentationTests
# suite without touching production behavior.
#
# P03 repair (runbook 2026-09-13, §2 defect list): the previous version could
# exit 0 after a failed xcodebuild because the per-phase status was never
# aggregated, and it deleted each .xcresult, destroying the evidence it had just
# produced. This version:
#   * aggregates phase status and exits non-zero when any phase fails or its
#     result bundle does not report "Passed";
#   * keeps every .xcresult and log: each run writes into its own run directory,
#     so a later run never deletes an earlier run's evidence;
#   * writes a machine-readable receipt (certification-receipt.json) with per
#     phase exit code, parsed result, counts, failing test names, artifact paths
#     and log sha256, so a gate can be checked without re-reading logs by hand;
#   * accepts a discovered simulator destination instead of depending on a baked-in
#     UDID: an explicit `UDID` is used as given, otherwise an available iPhone
#     simulator is discovered, and either way the chosen device is verified to be
#     present before any xcodebuild runs. A stale identifier refuses here rather
#     than failing later in a way that could be mistaken for a test result.
#
# Usage: scripts/run_camera_certification.sh [result-root]
set -u

OUT_DIR="${1:-/private/tmp/shafin-camera-cert}"
# The workspace is resolved from this script's own location: a certification run must
# certify the checkout it was started from, never a fixed path that could be a
# different copy of the app.
REPO_ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
WORKSPACE="$REPO_ROOT/shafinMultitool.xcworkspace"
if [ ! -d "$WORKSPACE" ]; then
  echo "CERTIFICATION_REFUSED: workspace not found next to this script: $WORKSPACE" >&2
  exit 2
fi
mkdir -p "$OUT_DIR"
RUN_DIR="$OUT_DIR/run-$(date -u +%Y%m%dT%H%M%SZ)-$$"
mkdir -p "$RUN_DIR"

DEVICES_JSON="$(xcrun simctl list devices available -j 2>/dev/null || true)"

pick_udid() {
  /usr/bin/python3 - "$DEVICES_JSON" <<'PY'
import json
import sys

try:
    data = json.loads(sys.argv[1])
except Exception:
    print("")
    raise SystemExit(0)

fallback = ""
for runtime, devices in (data.get("devices") or {}).items():
    if "iOS" not in runtime:
        continue
    for device in devices:
        if not device.get("isAvailable", True):
            continue
        udid = str(device.get("udid") or "")
        if not udid:
            continue
        if str(device.get("name") or "").startswith("iPhone"):
            print(udid)
            raise SystemExit(0)
        fallback = fallback or udid
print(fallback)
PY
}

UDID="${UDID:-}"
if [ -z "$UDID" ]; then
  UDID="$(pick_udid)"
fi
if [ -z "$UDID" ]; then
  echo "CERTIFICATION_REFUSED: no available iOS simulator was found; pass UDID=<udid>" >&2
  exit 2
fi
if ! /usr/bin/python3 - "$DEVICES_JSON" "$UDID" <<'PY'
import json
import sys

try:
    data = json.loads(sys.argv[1])
except Exception:
    raise SystemExit(1)
want = sys.argv[2]
for devices in (data.get("devices") or {}).values():
    for device in devices:
        if str(device.get("udid")) == want:
            raise SystemExit(0)
raise SystemExit(1)
PY
then
  echo "CERTIFICATION_REFUSED: destination UDID ${UDID} is not among the available simulators" >&2
  exit 2
fi

DEST="platform=iOS Simulator,id=${UDID}"
echo "DESTINATION: $DEST (verified available)"

PHASES_JSONL="$RUN_DIR/phases.jsonl"
: > "$PHASES_JSONL"
ANY_FAILED=0

PARSER=$(mktemp "${TMPDIR:-/tmp}/cert-phase-parse.XXXXXX.py")
cat > "$PARSER" <<'PY'
"""Parse one phase into a single JSON line. Never raises on bad input."""
import hashlib
import json
import sys
from pathlib import Path

summary_path = Path(sys.argv[1])
phase = sys.argv[2]
exit_code = int(sys.argv[3])
bundle = Path(sys.argv[4])
log = Path(sys.argv[5])

record = {
    "phase": phase,
    "xcodebuild_exit": exit_code,
    "result": "no_result_bundle",
    "total": 0,
    "passed": 0,
    "failed": 0,
    "skipped": 0,
    "failures": [],
    "xcresult": str(bundle) if bundle.exists() else None,
    "log": str(log) if log.exists() else None,
    "log_sha256": None,
}
if log.exists():
    record["log_sha256"] = hashlib.sha256(log.read_bytes()).hexdigest()

if summary_path.exists() and summary_path.stat().st_size > 0:
    try:
        data = json.loads(summary_path.read_text(encoding="utf-8"))
    except Exception:
        data = None
    if isinstance(data, dict):
        record["result"] = data.get("result") or "unknown"
        record["total"] = data.get("totalTestCount") or 0
        record["passed"] = data.get("passedTests") or 0
        record["failed"] = data.get("failedTests") or 0
        record["skipped"] = data.get("skippedTests") or 0
        record["failures"] = sorted(
            str(item.get("testName", "")) for item in (data.get("testFailures") or [])
        )
    else:
        record["result"] = "summary_unreadable"
elif bundle.exists():
    record["result"] = "summary_unavailable"

print(json.dumps(record, ensure_ascii=False, sort_keys=True))
PY

run_phase() {
  local name="$1"; shift
  # A run owns its directory, so these paths are new by construction: no earlier
  # result bundle is ever removed to make room for this one.
  local bundle="$RUN_DIR/${name}.xcresult"
  local log="$RUN_DIR/${name}.log"
  local summary="$RUN_DIR/${name}.summary.json"
  echo "=== PHASE ${name} ==="
  xcodebuild test \
    -workspace "$WORKSPACE" \
    -scheme shafinMultitool \
    -destination "$DEST" \
    "$@" \
    -resultBundlePath "$bundle" \
    COMPILER_INDEX_STORE_ENABLE=NO > "$log" 2>&1
  local status=$?

  if [ -d "$bundle" ] && command -v xcrun >/dev/null 2>&1; then
    xcrun xcresulttool get test-results summary --path "$bundle" > "$summary" 2>/dev/null || true
  fi

  local record
  record=$(/usr/bin/python3 "$PARSER" "$summary" "$name" "$status" "$bundle" "$log")
  printf '%s\n' "$record" >> "$PHASES_JSONL"

  echo "$record" | /usr/bin/python3 -c '
import json, sys
d = json.loads(sys.stdin.read())
print("PHASE_RESULT:", d["result"], "| xcodebuild exit:", d["xcodebuild_exit"],
      "| total:", d["total"], "passed:", d["passed"],
      "failed:", d["failed"], "skipped:", d["skipped"])
for name in d["failures"]:
    print("  FAIL:", name)
print("  evidence:", d["xcresult"] or "(no result bundle)", "| log:", d["log"])
'

  if [ "$status" -ne 0 ] || [ "$record" = "" ]; then
    ANY_FAILED=1
  else
    echo "$record" | /usr/bin/python3 -c '
import json, sys
d = json.loads(sys.stdin.read())
sys.exit(0 if d["result"] in ("Passed", "passed") else 1)
' || ANY_FAILED=1
  fi
}

# Phase A: capture-path ClosedLoop serially (real-time delivery isolation).
run_phase closedloop-serial -parallel-testing-enabled NO \
  -only-testing:shafinMultitoolTests/CameraCoachClosedLoopTests

# Phase B: everything else in parallel.
run_phase rest-parallel \
  -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests \
  -only-testing:shafinMultitoolTests/CoachingEpisodeCoordinatorTests \
  -only-testing:shafinMultitoolTests/CameraAdviceSafetyGateTests \
  -only-testing:shafinMultitoolTests/SemanticTipPlannerTests \
  -only-testing:shafinMultitoolTests/SubjectIdentityRegistryTests

/usr/bin/python3 - "$PHASES_JSONL" "$RUN_DIR/certification-receipt.json" "$ANY_FAILED" "$DEST" "$RUN_DIR" <<'PY'
import json
import sys
from pathlib import Path

phases_path = Path(sys.argv[1])
receipt_path = Path(sys.argv[2])
any_failed = int(sys.argv[3]) == 1
destination = sys.argv[4]
run_dir = sys.argv[5]

phases = [json.loads(line) for line in phases_path.read_text(encoding="utf-8").splitlines() if line.strip()]
receipt = {
    "schema_id": "camera-certification-receipt-v1",
    "destination": destination,
    "run_dir": run_dir,
    "phases": phases,
    "phase_count": len(phases),
    "totals": {
        "passed": sum(p["passed"] for p in phases),
        "failed": sum(p["failed"] for p in phases),
        "skipped": sum(p["skipped"] for p in phases),
    },
    "status": "failed" if (any_failed or any(p["failed"] for p in phases)) else "passed",
    "evidence_note": "each run writes into its own run directory; this script does not delete evidence",
}
receipt_path.write_text(json.dumps(receipt, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print("CERTIFICATION_STATUS:", receipt["status"], "| phases:", receipt["phase_count"],
      "| passed:", receipt["totals"]["passed"], "failed:", receipt["totals"]["failed"],
      "skipped:", receipt["totals"]["skipped"])
print("RECEIPT:", receipt_path)
sys.exit(1 if receipt["status"] == "failed" else 0)
PY
STATUS=$?

rm -f "$PARSER"
exit "$STATUS"
