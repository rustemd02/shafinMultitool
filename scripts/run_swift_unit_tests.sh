#!/usr/bin/env bash
# Run the shafinMultitool unit-test target in bounded, disk-guarded batches.
#
# Why batching: a single full-target run needs more than 7.6 GiB of free space on
# this machine and was killed by the free-space guard before finishing. The cost
# driver turned out to be the result bundle plus per-run growth in the shared
# simulator/XCTest area; a small batch without `-resultBundlePath` costs a few
# hundred MiB net. So this runner splits the target by test class, omits the result
# bundle, and uses a throwaway DerivedData per batch.
#
# Exit codes
#   0  every batch ran and no test case failed
#   1  at least one batch reported a failing test case
#   2  refused before running: no simulator, no test classes, or bad arguments
#   3  aborted by the disk guard (nothing is claimed about the un-run classes)
#
# The guard exists because an earlier unbounded run filled the volume to zero.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

WORKSPACE="shafinMultitool.xcworkspace"
SCHEME="shafinMultitool"
TEST_DIR="shafinMultitoolTests"
BATCH_SIZE=6
FLOOR_MIB=2048
POLL_SECONDS=5
KEEP_GOING=0
BATCHES_ONLY="${BATCHES_ONLY:-}"
UDID="${CAMERA_TEST_UDID:-}"

usage() {
  cat <<'USAGE'
Usage: scripts/run_swift_unit_tests.sh [--udid UDID] [--batch-size N] [--floor-mib N]

  --udid UDID        simulator to test on (default: first booted iPhone)
  --batch-size N     test classes per xcodebuild invocation (default 6)
  --floor-mib N      abort if free space falls below this (default 2048)
  --poll-seconds N   disk-guard poll interval (default 5)
  --keep-going       do not stop at the first failing batch; report every failure
                     (a survey run: the complete failure list matters more than speed)

Environment: CAMERA_TEST_UDID sets the default udid; BATCHES_ONLY=1 prints the
batches and exits without running them.
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --udid) UDID="${2:-}"; shift 2 ;;
    --batch-size) BATCH_SIZE="${2:-}"; shift 2 ;;
    --floor-mib) FLOOR_MIB="${2:-}"; shift 2 ;;
    --poll-seconds) POLL_SECONDS="${2:-}"; shift 2 ;;
    --keep-going) KEEP_GOING=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$BATCH_SIZE" in ''|*[!0-9]*) echo "REFUSED: --batch-size must be a positive integer" >&2; exit 2 ;; esac
[ "$BATCH_SIZE" -ge 1 ] || { echo "REFUSED: --batch-size must be >= 1" >&2; exit 2; }
case "$FLOOR_MIB" in ''|*[!0-9]*) echo "REFUSED: --floor-mib must be a positive integer" >&2; exit 2 ;; esac
case "$POLL_SECONDS" in ''|*[!0-9]*) echo "REFUSED: --poll-seconds must be a positive integer" >&2; exit 2 ;; esac
[ "$POLL_SECONDS" -ge 1 ] || { echo "REFUSED: --poll-seconds must be >= 1" >&2; exit 2; }

[ -d "$WORKSPACE" ] || { echo "REFUSED: $WORKSPACE not found; run from the repository" >&2; exit 2; }

CLASSES="$(grep -ho '^[[:space:]]*\(final \)\?class [A-Za-z0-9_]*Tests' "$TEST_DIR"/*.swift 2>/dev/null \
  | sed -E 's/^[[:space:]]*(final )?class //' | sort -u)"
TOTAL="$(printf '%s\n' "$CLASSES" | grep -c . || true)"
if [ "${TOTAL:-0}" -eq 0 ]; then
  echo "REFUSED: no *Tests classes found under $TEST_DIR (a run with none would pass vacuously)" >&2
  exit 2
fi

# The batch listing is a preview: it must work without a simulator, otherwise you
# cannot check the split before committing to a long run.
if [ -n "$BATCHES_ONLY" ]; then
  index=0
  while :; do
    chunk="$(printf '%s\n' "$CLASSES" | sed -n "$((index + 1)),$((index + BATCH_SIZE))p")"
    [ -z "$chunk" ] && break
    index=$((index + BATCH_SIZE))
    echo "batch $((index / BATCH_SIZE)): $(printf '%s ' $chunk)"
  done
  echo "classes=$TOTAL batch_size=$BATCH_SIZE"
  exit 0
fi

if [ -z "$UDID" ]; then
  UDID="$(xcrun simctl list devices booted 2>/dev/null | sed -n 's/.*(\([0-9A-F-]\{36\}\)) (Booted).*/\1/p' | head -1)"
fi
if [ -z "$UDID" ]; then
  echo "REFUSED: no booted simulator found; boot one or pass --udid" >&2
  exit 2
fi
if ! xcrun simctl list devices available 2>/dev/null | grep -q "$UDID"; then
  echo "REFUSED: simulator $UDID is not available" >&2
  exit 2
fi

echo "workspace=$WORKSPACE scheme=$SCHEME simulator=$UDID"
echo "classes=$TOTAL batch_size=$BATCH_SIZE floor=${FLOOR_MIB}MiB"

cases_passed=0
failures=0
aborted=0
batches_run=0
index=0

while :; do
  chunk="$(printf '%s\n' "$CLASSES" | sed -n "$((index + 1)),$((index + BATCH_SIZE))p")"
  [ -z "$chunk" ] && break
  index=$((index + BATCH_SIZE))
  batches_run=$((batches_run + 1))

  args=()
  while read -r name; do
    [ -n "$name" ] && args+=("-only-testing:${TEST_DIR}/${name}")
  done <<< "$chunk"

  tmp="$(mktemp -d /private/tmp/setos-unit.XXXXXX)"
  log="$tmp/run.log"
  # No -resultBundlePath: its omission is what makes a batch affordable here.
  xcodebuild test \
    -workspace "$WORKSPACE" \
    -scheme "$SCHEME" \
    -destination "platform=iOS Simulator,id=$UDID" \
    "${args[@]}" \
    -derivedDataPath "$tmp/DerivedData" > "$log" 2>&1 &
  pid=$!

  while kill -0 "$pid" 2>/dev/null; do
    free_mib="$(df -m / | awk 'NR==2{print $4}')"
    if [ "${free_mib:-0}" -lt "$FLOOR_MIB" ]; then
      echo "ABORT: free space ${free_mib}MiB below floor ${FLOOR_MIB}MiB — killing batch $batches_run"
      kill -9 "$pid" 2>/dev/null || true
      pkill -9 -P "$pid" 2>/dev/null || true
      aborted=1
      break
    fi
    sleep "$POLL_SECONDS"
  done
  rc=0; wait "$pid" 2>/dev/null || rc=$?

  passed="$(grep -c "passed on 'Clone" "$log" 2>/dev/null || true)"
  # Xcode 26 prints "Test case '<name>()' failed on '<device>'"; older runs used
  # "Test Case '-[Class method]' failed". Counting only the capital-C form made the
  # failure count read 0 while the batch exited 65.
  failed="$(grep -cE "Test [Cc]ase .* failed" "$log" 2>/dev/null || true)"
  cases_passed=$((cases_passed + ${passed:-0}))
  echo "batch $batches_run: classes=$(printf '%s\n' "$chunk" | grep -c .) passed=${passed:-0} failed=${failed:-0} rc=$rc"

  if [ "$aborted" = "1" ]; then
    rm -rf "$tmp"
    failures=$failed
    break
  fi
  if [ "${failed:-0}" != "0" ]; then
    echo "FAILING CASES (batch $batches_run):"
    grep -E "Test case .* failed|Test Case .* failed" "$log" 2>/dev/null | sed 's/ on .*//' | head -20 || true
    failures=$((failures + failed))
    if [ "$KEEP_GOING" = "1" ]; then
      rm -rf "$tmp"
      continue
    fi
    break
  fi
  # A batch that executed nothing is not a batch that found nothing wrong: a build
  # failure or an empty selection would otherwise be reported as a clean run.
  if [ "${passed:-0}" = "0" ] || [ "$rc" != "0" ]; then
    echo "FAILING BATCH $batches_run: xcodebuild rc=$rc and ${passed:-0} test case(s) executed"
    grep -E "error:|Testing cancelled because|\*\* TEST (FAILED|SUCCEEDED)" "$log" 2>/dev/null | head -10 || true
    grep -E "Test case .* failed" "$log" 2>/dev/null | sed 's/ on .*//' | head -20 || true
    failures=$((failures + 1))
    if [ "$KEEP_GOING" = "1" ]; then
      rm -rf "$tmp"
      continue
    fi
    break
  fi
done

echo "batches_run=$batches_run classes_attempted=$index cases_passed=$cases_passed failures=$failures aborted=$aborted"
if [ "$aborted" = "1" ]; then
  echo "RESULT: ABORTED BY DISK GUARD — the classes after $index were not run; free space first or lower --batch-size"
  exit 3
fi
if [ "${failures:-0}" != "0" ]; then
  echo "RESULT: FAILED — $failures test case(s) failed"
  exit 1
fi
if [ "$index" -lt "$TOTAL" ]; then
  echo "RESULT: INCOMPLETE — only $index of $TOTAL classes were attempted"
  exit 3
fi
echo "RESULT: PASSED — all $TOTAL classes ran with no failing test case"
exit 0
