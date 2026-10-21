#!/usr/bin/env bash
# Stage the SHA-pinned NIMA iOS-simulator qualification payload into the app
# container of booted simulators so NIMACorrectedFP32SimulatorQualificationTests
# can read their authenticated fixtures.
#
# The canonical payload (protocol.json + model/input files, protocol SHA
# 203aeed9…) lives in local-data per the 2026-09-16 qualification receipts. The
# tests read it from the app container's Caches
# (SETOSNIMAQualification/<first-12-sha-chars>), which changes whenever the app
# container is recreated by a reinstall; rerun this script after a fresh
# install. Missing payload makes those tests XCTSkip (fixture-availability
# gate); a present-but-modified payload still fails the SHA check inside the
# tests.
#
# Usage: scripts/stage_nima_qualification.sh [--udid UDID] [--payload DIR]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE}[0]")/.." && pwd)"
DEFAULT_PAYLOAD="/Users/unterlantas/Documents/XCode/setos-backend/local-data/SETOS/verification/nima-ios-simulator-qualification-20260916-955kofxs/payload"
PROTOCOL_SHA="203aeed91ee401d988714cc3c2abb6c77d64e3eba75465a3829c832f6f682d02"
BUNDLE_ID="com.vigvamcev-media.shafinMultitool"

UDID=""
PAYLOAD="$DEFAULT_PAYLOAD"
while [ $# -gt 0 ]; do
  case "$1" in
    --udid) UDID="$2"; shift ;;
    --payload) PAYLOAD="$2"; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [ ! -f "$PAYLOAD/protocol.json" ]; then
  echo "FAIL canonical payload not found at $PAYLOAD" >&2
  exit 2
fi

ACTUAL_SHA=$(shasum -a 256 "$PAYLOAD/protocol.json" | cut -d' ' -f1)
if [ "$ACTUAL_SHA" != "$PROTOCOL_SHA" ]; then
  echo "FAIL payload protocol SHA mismatch: $ACTUAL_SHA" >&2
  exit 2
fi

staged=0
skipped=0
for target in $(xcrun simctl list devices | grep -E "\(Booted\)" | grep -oE "[0-9A-F-]{36}"); do
  if [ -n "$UDID" ] && [ "$target" != "$UDID" ]; then continue; fi
  container=$(xcrun simctl get_app_container "$target" "$BUNDLE_ID" data 2>/dev/null || true)
  if [ -z "$container" ]; then
    echo "SKIP $target: app not installed"
    skipped=$((skipped + 1))
    continue
  fi
  dest="$container/Library/Caches/SETOSNIMAQualification/${PROTOCOL_SHA:0:12}"
  mkdir -p "$dest"
  ditto "$PAYLOAD" "$dest"
  verify=$(shasum -a 256 "$dest/protocol.json" | cut -d' ' -f1)
  if [ "$verify" != "$PROTOCOL_SHA" ]; then
    echo "FAIL $target: post-copy verification mismatch" >&2
    exit 1
  fi
  echo "STAGED $target -> $dest"
  staged=$((staged + 1))
done

if [ "$staged" -eq 0 ] && [ "$skipped" -eq 0 ]; then
  echo "FAIL no booted simulator found" >&2
  exit 1
fi
echo "DONE staged=$staged skipped=$skipped"
