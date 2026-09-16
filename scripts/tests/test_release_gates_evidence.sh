#!/bin/bash

# Does the release-gate orchestrator keep evidence across runs?
#
# P03 established the rule for the certification recipe: a run must not delete an
# earlier run's evidence to make room for its own. This test pins the same rule for
# scripts/run_release_gates.sh, and it is written so it holds whatever stage the run
# happens to stop at:
#
#   * the run exits non-zero (the current tree has known blockers, and a stub
#     xcodebuild fails on purpose, so no outcome can silently look green);
#   * the run writes its own run-<UTC>-<pid> directory containing stage logs;
#   * a pre-existing run directory and its file are still there afterwards.
#
# No real Xcode build is involved: xcodebuild is stubbed through PATH.

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd -P)"
ORCHESTRATOR="$REPO_ROOT/scripts/run_release_gates.sh"

TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/rg-evidence.XXXXXX")"
trap 'rm -rf -- "$TEMP_ROOT"' EXIT

OWNED_ROOT="$TEMP_ROOT/shafin-release-gates"
mkdir -p "$OWNED_ROOT/run-19700101T000000Z-1"
printf 'earlier run evidence\n' > "$OWNED_ROOT/run-19700101T000000Z-1/keep.txt"

STUB_BIN="$TEMP_ROOT/bin"
mkdir -p "$STUB_BIN"
cat > "$STUB_BIN/xcodebuild" <<'STUB'
#!/bin/bash
echo "stub xcodebuild: failing on purpose so the run cannot look green" >&2
exit 65
STUB
chmod +x "$STUB_BIN/xcodebuild"

set +e
PATH="$STUB_BIN:$PATH" bash "$ORCHESTRATOR" --derived-data-root "$TEMP_ROOT" \
    > "$TEMP_ROOT/run-output.txt" 2>&1
STATUS=$?
set -e

if [ "$STATUS" -eq 0 ]; then
    printf 'FAIL: the orchestrator exited 0 while this tree still has known blockers and the stub build fails\n' >&2
    tail -n 40 "$TEMP_ROOT/run-output.txt" >&2
    exit 1
fi
printf 'PASS non-zero exit (%s) with known blockers present\n' "$STATUS"

if ! grep -q 'RUN_OUTPUT_ROOT: ' "$TEMP_ROOT/run-output.txt"; then
    printf 'FAIL: the run did not announce its own output directory\n' >&2
    exit 1
fi
printf 'PASS the run announces its own output directory\n'

NEW_RUNS="$(find "$OWNED_ROOT" -maxdepth 1 -type d -name 'run-*' ! -name 'run-19700101T000000Z-1' | wc -l | tr -d ' ')"
if [ "$NEW_RUNS" -lt 1 ]; then
    printf 'FAIL: no new run directory was created\n' >&2
    exit 1
fi
NEW_RUN="$(find "$OWNED_ROOT" -maxdepth 1 -type d -name 'run-*' ! -name 'run-19700101T000000Z-1' | head -1)"
LOGS="$(find "$NEW_RUN" -maxdepth 1 -type f -name '*.log' | wc -l | tr -d ' ')"
if [ "$LOGS" -lt 1 ]; then
    printf 'FAIL: the run directory carries no stage log\n' >&2
    ls -la "$NEW_RUN" >&2
    exit 1
fi
printf 'PASS the run kept %s stage log(s) in its own directory\n' "$LOGS"

if [ ! -f "$OWNED_ROOT/run-19700101T000000Z-1/keep.txt" ]; then
    printf 'FAIL: an earlier run directory was removed by this run\n' >&2
    exit 1
fi
printf 'PASS an earlier run directory and its evidence survived\n'

printf 'ALL PASS: run_release_gates.sh keeps per-run evidence and fails closed\n'
