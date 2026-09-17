#!/usr/bin/env bash
# Stage the SHA-pinned legacy camera reference payload into the app container
# of booted simulators so VisionRequestIsolationDiagnosticTests and
# AnalysisPipelinePresentationTests can read their authenticated fixtures.
#
# The canonical payload (9 images + manifest.json, manifest SHA ed652add…)
# lives in local-data per the 2026-09-17 recovery receipt. The tests read it
# from the app container's Caches, which changes whenever the app is
# reinstalled; rerun this script after a fresh install.
#
# Usage: scripts/stage_legacy_camera_references.sh [--udid UDID] [--payload DIR]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE}[0]")/.." && pwd)"
DEFAULT_PAYLOAD="/Users/unterlantas/Documents/XCode/setos-backend/local-data/SETOS/verification/legacy-reference-recovery-20260917-p8m2af3s/resolver-proposal/payload"
MANIFEST_SHA="ed652addfd2c661060bb6dfbcab8c9c7f7be1d02a50c1b9a8e518068153e9894"
BUNDLE_ID="com.vigvamcev-media.shafinMultitool"

UDID=""
PAYLOAD="$DEFAULT_PAYLOAD"
while [ $# -gt 0 ]; do
  case "$1" in
    --udid) UDID="$2"; shift 2 ;;
    --payload) PAYLOAD="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [ ! -f "$PAYLOAD/manifest.json" ]; then
  echo "FAIL canonical payload not found at $PAYLOAD" >&2
  exit 2
fi

ACTUAL_SHA=$(shasum -a 256 "$PAYLOAD/manifest.json" | cut -d' ' -f1)
if [ "$ACTUAL_SHA" != "$MANIFEST_SHA" ]; then
  echo "FAIL payload manifest SHA mismatch: $ACTUAL_SHA" >&2
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
  dest="$container/Library/Caches/SETOSLegacyCameraReferences/$MANIFEST_SHA"
  mkdir -p "$dest"
  # copy payload contents (not the dir) without following symlinks
  ditto "$PAYLOAD" "$dest"
  verify=$(shasum -a 256 "$dest/manifest.json" | cut -d' ' -f1)
  if [ "$verify" != "$MANIFEST_SHA" ]; then
    echo "FAIL $target: post-copy verification mismatch" >&2
    exit 1
  fi
  echo "STAGED $target -> $dest"
  staged=$((staged + 1))
done

if [ "$staged" -eq 0 ] && [ "$skipped" -eq 0 ]; then
  echo "FAIL no booted simulator matched" >&2
  exit 3
fi
echo "DONE staged=$staged skipped=$skipped"
