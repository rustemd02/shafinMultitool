#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PILOT_SCRIPT="$SCRIPT_DIR/run_sgv7_pilot.sh"
AUDIT_SCRIPT="$SCRIPT_DIR/audit_sgv7_outputs.py"

OUTPUT_DIR="/tmp/sgv7_pilot_auto"
RUN_CONTRACT_TESTS="1"
RUN_AUDIT="1"
MIN_SFT_TOTAL="1"
MIN_SAME_TYPE_MARKERS="1"
MIN_THREE_BEAT_CASES="0"
MIN_ORDINAL_CASES="0"
MIN_EXACT_MARKER_IDENTITY_CASES="0"
MIN_MARKED_OBJECT_MORPHOLOGY="0"
REQUIRE_PREFERENCE="0"
REQUIRE_RUNTIME_PREFERENCE_ORIGIN="0"
MAX_SOURCE_REJECT_RATE=""
MAX_GRAPH_PATTERN_SHARE=""
MAX_FINAL_SFT_PATTERN_SHARE=""
MAX_PROMOTED_REVIEW_SHARE=""
MAX_TECHNICAL_LITERAL_SHARE=""
MAX_META_LANGUAGE_SHARE=""
MAX_SURFACE_NOISE_SHARE=""
MAX_BAD_MORPHOLOGY_SHARE=""
OPENAI_BASE_URL_VALUE=""
FORWARDED_ARGS=()

usage() {
  cat <<EOF
Usage: $(basename "$0") [options-for-wrapper] [-- options-for-run_sgv7_pilot.sh]

Wrapper over run_sgv7_pilot.sh:
1) preflight contract tests
2) full pilot run
3) automatic post-run audit

Wrapper options:
  --output-dir PATH                Output dir passed to pilot and audit (default: ${OUTPUT_DIR})
  --skip-contract-tests            Skip CIR contract unittest preflight
  --no-audit                       Skip post-run audit
  --min-sft-total INT              Audit gate: minimal SFT rows (default: ${MIN_SFT_TOTAL})
  --min-same-type-markers INT      Audit gate: minimal same_type_markers coverage (default: ${MIN_SAME_TYPE_MARKERS})
  --min-three-beat-cases INT       Audit gate: minimal three_beat_cases coverage (default: ${MIN_THREE_BEAT_CASES})
  --min-ordinal-cases INT          Audit gate: minimal ordinal_cases coverage (default: ${MIN_ORDINAL_CASES})
  --min-exact-marker-identity-cases INT
                                   Audit gate: minimal exact_marker_identity_cases coverage (default: ${MIN_EXACT_MARKER_IDENTITY_CASES})
  --min-marked-object-morphology INT
                                   Audit gate: minimal marked_object_morphology coverage (default: ${MIN_MARKED_OBJECT_MORPHOLOGY})
  --require-preference             Audit gate: fail if preference split is empty
  --require-runtime-preference-origin
                                   Audit gate: fail if preference origin runtime_failure_reviewed_merge is absent
  --max-source-reject-rate FLOAT   Audit gate for core/hard source reject ratio [0..1]
  --max-graph-pattern-share FLOAT  Audit gate for max single-pattern share in core/hard graph manifests [0..1]
  --max-final-sft-pattern-share FLOAT
                                   Audit gate for max single-pattern share in final SFT [0..1]
  --max-promoted-review-share FLOAT
                                   Audit gate for promoted review share in final SFT [0..1]
  --max-technical-literal-share FLOAT
                                   Audit gate for technical-literal rows in final SFT [0..1]
  --max-meta-language-share FLOAT  Audit gate for meta-language rows in final SFT [0..1]
  --max-surface-noise-share FLOAT  Audit gate for surface-noise rows in final SFT [0..1]
  --max-bad-morphology-share FLOAT Audit gate for bad-morphology rows in final SFT [0..1]
  --openai-base-url URL            Export OPENAI_BASE_URL for this run
  -h, --help                       Show this help

Any unknown flags are forwarded to run_sgv7_pilot.sh.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir)
      OUTPUT_DIR="$2"
      FORWARDED_ARGS+=("$1" "$2")
      shift 2
      ;;
    --skip-contract-tests)
      RUN_CONTRACT_TESTS="0"
      shift
      ;;
    --no-audit)
      RUN_AUDIT="0"
      shift
      ;;
    --min-sft-total)
      MIN_SFT_TOTAL="$2"
      shift 2
      ;;
    --min-same-type-markers)
      MIN_SAME_TYPE_MARKERS="$2"
      shift 2
      ;;
    --min-three-beat-cases)
      MIN_THREE_BEAT_CASES="$2"
      shift 2
      ;;
    --min-ordinal-cases)
      MIN_ORDINAL_CASES="$2"
      shift 2
      ;;
    --min-exact-marker-identity-cases)
      MIN_EXACT_MARKER_IDENTITY_CASES="$2"
      shift 2
      ;;
    --min-marked-object-morphology)
      MIN_MARKED_OBJECT_MORPHOLOGY="$2"
      shift 2
      ;;
    --require-preference)
      REQUIRE_PREFERENCE="1"
      shift
      ;;
    --require-runtime-preference-origin)
      REQUIRE_RUNTIME_PREFERENCE_ORIGIN="1"
      shift
      ;;
    --max-source-reject-rate)
      MAX_SOURCE_REJECT_RATE="$2"
      shift 2
      ;;
    --max-graph-pattern-share)
      MAX_GRAPH_PATTERN_SHARE="$2"
      shift 2
      ;;
    --max-final-sft-pattern-share)
      MAX_FINAL_SFT_PATTERN_SHARE="$2"
      shift 2
      ;;
    --max-promoted-review-share)
      MAX_PROMOTED_REVIEW_SHARE="$2"
      shift 2
      ;;
    --max-technical-literal-share)
      MAX_TECHNICAL_LITERAL_SHARE="$2"
      shift 2
      ;;
    --max-meta-language-share)
      MAX_META_LANGUAGE_SHARE="$2"
      shift 2
      ;;
    --max-surface-noise-share)
      MAX_SURFACE_NOISE_SHARE="$2"
      shift 2
      ;;
    --max-bad-morphology-share)
      MAX_BAD_MORPHOLOGY_SHARE="$2"
      shift 2
      ;;
    --openai-base-url)
      OPENAI_BASE_URL_VALUE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      while [[ $# -gt 0 ]]; do
        FORWARDED_ARGS+=("$1")
        shift
      done
      ;;
    *)
      FORWARDED_ARGS+=("$1")
      shift
      ;;
  esac
done

if [[ -n "$OPENAI_BASE_URL_VALUE" ]]; then
  export OPENAI_BASE_URL="$OPENAI_BASE_URL_VALUE"
  echo "[sgv7:full] OPENAI_BASE_URL is set for this run."
fi

echo "[sgv7:full] output_dir=$OUTPUT_DIR"
echo "[sgv7:full] run_contract_tests=$RUN_CONTRACT_TESTS run_audit=$RUN_AUDIT"
echo "[sgv7:full] min_sft_total=$MIN_SFT_TOTAL min_same_type_markers=$MIN_SAME_TYPE_MARKERS require_preference=$REQUIRE_PREFERENCE"
echo "[sgv7:full] min_three_beat_cases=$MIN_THREE_BEAT_CASES min_ordinal_cases=$MIN_ORDINAL_CASES"
echo "[sgv7:full] min_exact_marker_identity_cases=$MIN_EXACT_MARKER_IDENTITY_CASES min_marked_object_morphology=$MIN_MARKED_OBJECT_MORPHOLOGY"
echo "[sgv7:full] require_runtime_preference_origin=$REQUIRE_RUNTIME_PREFERENCE_ORIGIN"
if [[ -n "$MAX_SOURCE_REJECT_RATE" ]]; then
  echo "[sgv7:full] max_source_reject_rate=$MAX_SOURCE_REJECT_RATE"
fi
if [[ -n "$MAX_GRAPH_PATTERN_SHARE" ]]; then
  echo "[sgv7:full] max_graph_pattern_share=$MAX_GRAPH_PATTERN_SHARE"
fi
if [[ -n "$MAX_FINAL_SFT_PATTERN_SHARE" ]]; then
  echo "[sgv7:full] max_final_sft_pattern_share=$MAX_FINAL_SFT_PATTERN_SHARE"
fi
if [[ -n "$MAX_PROMOTED_REVIEW_SHARE" ]]; then
  echo "[sgv7:full] max_promoted_review_share=$MAX_PROMOTED_REVIEW_SHARE"
fi
if [[ -n "$MAX_TECHNICAL_LITERAL_SHARE" ]]; then
  echo "[sgv7:full] max_technical_literal_share=$MAX_TECHNICAL_LITERAL_SHARE"
fi
if [[ -n "$MAX_META_LANGUAGE_SHARE" ]]; then
  echo "[sgv7:full] max_meta_language_share=$MAX_META_LANGUAGE_SHARE"
fi
if [[ -n "$MAX_SURFACE_NOISE_SHARE" ]]; then
  echo "[sgv7:full] max_surface_noise_share=$MAX_SURFACE_NOISE_SHARE"
fi
if [[ -n "$MAX_BAD_MORPHOLOGY_SHARE" ]]; then
  echo "[sgv7:full] max_bad_morphology_share=$MAX_BAD_MORPHOLOGY_SHARE"
fi

if [[ "$RUN_CONTRACT_TESTS" == "1" ]]; then
  echo
  echo "==> [preflight] CIR contract tests"
  (
    cd "$REPO_ROOT"
    python3 -m unittest discover -s docs/SGv7pipeline/cir_contract/tests -p 'test_*.py'
  )
  echo "==> [preflight] done"
fi

echo
echo "==> [pipeline] run_sgv7_pilot.sh"
(
  cd "$REPO_ROOT"
  "$PILOT_SCRIPT" --output-dir "$OUTPUT_DIR" "${FORWARDED_ARGS[@]}"
)
echo "==> [pipeline] done"

if [[ "$RUN_AUDIT" == "1" ]]; then
  audit_cmd=(
    python3 "$AUDIT_SCRIPT"
    --output-dir "$OUTPUT_DIR"
    --min-sft-total "$MIN_SFT_TOTAL"
    --min-same-type-markers "$MIN_SAME_TYPE_MARKERS"
    --min-three-beat-cases "$MIN_THREE_BEAT_CASES"
    --min-ordinal-cases "$MIN_ORDINAL_CASES"
    --min-exact-marker-identity-cases "$MIN_EXACT_MARKER_IDENTITY_CASES"
    --min-marked-object-morphology "$MIN_MARKED_OBJECT_MORPHOLOGY"
  )
  if [[ "$REQUIRE_PREFERENCE" == "1" ]]; then
    audit_cmd+=(--require-preference)
  fi
  if [[ "$REQUIRE_RUNTIME_PREFERENCE_ORIGIN" == "1" ]]; then
    audit_cmd+=(--require-runtime-preference-origin)
  fi
  if [[ -n "$MAX_SOURCE_REJECT_RATE" ]]; then
    audit_cmd+=(--max-source-reject-rate "$MAX_SOURCE_REJECT_RATE")
  fi
  if [[ -n "$MAX_GRAPH_PATTERN_SHARE" ]]; then
    audit_cmd+=(--max-graph-pattern-share "$MAX_GRAPH_PATTERN_SHARE")
  fi
  if [[ -n "$MAX_FINAL_SFT_PATTERN_SHARE" ]]; then
    audit_cmd+=(--max-final-sft-pattern-share "$MAX_FINAL_SFT_PATTERN_SHARE")
  fi
  if [[ -n "$MAX_PROMOTED_REVIEW_SHARE" ]]; then
    audit_cmd+=(--max-promoted-review-share "$MAX_PROMOTED_REVIEW_SHARE")
  fi
  if [[ -n "$MAX_TECHNICAL_LITERAL_SHARE" ]]; then
    audit_cmd+=(--max-technical-literal-share "$MAX_TECHNICAL_LITERAL_SHARE")
  fi
  if [[ -n "$MAX_META_LANGUAGE_SHARE" ]]; then
    audit_cmd+=(--max-meta-language-share "$MAX_META_LANGUAGE_SHARE")
  fi
  if [[ -n "$MAX_SURFACE_NOISE_SHARE" ]]; then
    audit_cmd+=(--max-surface-noise-share "$MAX_SURFACE_NOISE_SHARE")
  fi
  if [[ -n "$MAX_BAD_MORPHOLOGY_SHARE" ]]; then
    audit_cmd+=(--max-bad-morphology-share "$MAX_BAD_MORPHOLOGY_SHARE")
  fi

  echo
  echo "==> [audit] SG v7 outputs"
  (
    cd "$REPO_ROOT"
    "${audit_cmd[@]}"
  )
  echo "==> [audit] done"
fi

echo
echo "[sgv7:full] Completed."
echo "[sgv7:full] Inspect: $OUTPUT_DIR/final/dataset"
