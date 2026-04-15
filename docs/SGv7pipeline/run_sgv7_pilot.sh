#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

SEED="20260415"
OUTPUT_DIR="/tmp/sgv7_pilot"
CORE_RECORDS="24"
HARD_RECORDS="12"
MAX_VARIANTS_PER_GRAPH="2"
MAX_AUGMENTED_VARIANTS_PER_PARENT="1"
PARAPHRASER_BACKEND="heuristic"
CRITIC_BACKEND="heuristic"
MODEL_NAME="gpt-5.4-nano"
BATCH_SIZE="8"
REFILL_BUDGET="12"
STRICT_DUPLICATES="0"
AUTO_PROMOTE_SAME_TYPE_REVIEW="1"
HEARTBEAT_SECONDS="20"
MAX_TECHNICAL_SOURCE_SHARE="0.15"
TOTAL_STEPS="12"
STEP_INDEX="0"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Run a small end-to-end SG v7 pilot build.

Options:
  --output-dir PATH                     Output directory (default: ${OUTPUT_DIR})
  --seed INT                            Deterministic seed (default: ${SEED})
  --core-records INT                    Number of core graph records (default: ${CORE_RECORDS})
  --hard-records INT                    Number of hard graph records (default: ${HARD_RECORDS})
  --max-variants-per-graph INT          Source variants per graph (default: ${MAX_VARIANTS_PER_GRAPH})
  --max-augmented-per-parent INT        Augmented variants per accepted source (default: ${MAX_AUGMENTED_VARIANTS_PER_PARENT})
  --paraphraser-backend MODE            openai|heuristic (default: ${PARAPHRASER_BACKEND})
  --critic-backend MODE                 openai|heuristic (default: ${CRITIC_BACKEND})
  --model-name NAME                     Source generation model label (default: ${MODEL_NAME})
  --batch-size INT                      Source generation batch size (default: ${BATCH_SIZE})
  --refill-budget INT                   Graph refill attempts on duplicates/budget rejects (default: ${REFILL_BUDGET})
  --heartbeat-seconds INT               Heartbeat period for long-running commands (default: ${HEARTBEAT_SECONDS})
  --max-technical-source-share FLOAT    Max SFT share with actor_*/object_marked_* literals (default: ${MAX_TECHNICAL_SOURCE_SHARE})
  --strict-duplicates                   Fail immediately on first duplicate graph (default: off)
  --no-auto-promote-same-type-review    Disable automatic promotion of same_type review cases
  -h, --help                            Show this help

Example:
  $(basename "$0") --output-dir /tmp/sgv7_pilot --seed 20260415
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --seed)
      SEED="$2"
      shift 2
      ;;
    --core-records)
      CORE_RECORDS="$2"
      shift 2
      ;;
    --hard-records)
      HARD_RECORDS="$2"
      shift 2
      ;;
    --max-variants-per-graph)
      MAX_VARIANTS_PER_GRAPH="$2"
      shift 2
      ;;
    --max-augmented-per-parent)
      MAX_AUGMENTED_VARIANTS_PER_PARENT="$2"
      shift 2
      ;;
    --paraphraser-backend)
      PARAPHRASER_BACKEND="$2"
      shift 2
      ;;
    --critic-backend)
      CRITIC_BACKEND="$2"
      shift 2
      ;;
    --model-name)
      MODEL_NAME="$2"
      shift 2
      ;;
    --batch-size)
      BATCH_SIZE="$2"
      shift 2
      ;;
    --refill-budget)
      REFILL_BUDGET="$2"
      shift 2
      ;;
    --heartbeat-seconds)
      HEARTBEAT_SECONDS="$2"
      shift 2
      ;;
    --max-technical-source-share)
      MAX_TECHNICAL_SOURCE_SHARE="$2"
      shift 2
      ;;
    --strict-duplicates)
      STRICT_DUPLICATES="1"
      shift
      ;;
    --no-auto-promote-same-type-review)
      AUTO_PROMOTE_SAME_TYPE_REVIEW="0"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

run() {
  STEP_INDEX="$((STEP_INDEX + 1))"
  local step_label="[${STEP_INDEX}/${TOTAL_STEPS}]"
  local start_ts
  local now_ts
  local last_heartbeat_ts
  local elapsed
  start_ts="$(date +%s)"
  last_heartbeat_ts="$start_ts"

  echo
  echo "==> ${step_label} $*"
  (
    cd "$REPO_ROOT"
    "$@" &
    local cmd_pid=$!
    while kill -0 "$cmd_pid" 2>/dev/null; do
      sleep 1
      now_ts="$(date +%s)"
      if kill -0 "$cmd_pid" 2>/dev/null && (( now_ts - last_heartbeat_ts >= HEARTBEAT_SECONDS )); then
        elapsed="$((now_ts - start_ts))"
        echo "    ${step_label} still running (${elapsed}s): $1"
        last_heartbeat_ts="$now_ts"
      fi
    done
    wait "$cmd_pid"
  )
  local rc=$?
  now_ts="$(date +%s)"
  elapsed="$((now_ts - start_ts))"
  if [[ "$rc" -eq 0 ]]; then
    echo "    ${step_label} done (${elapsed}s)"
  else
    echo "    ${step_label} failed (${elapsed}s)"
  fi
  return "$rc"
}

run_with_stdin() {
  STEP_INDEX="$((STEP_INDEX + 1))"
  local step_label="[${STEP_INDEX}/${TOTAL_STEPS}]"
  local start_ts
  local now_ts
  local elapsed
  start_ts="$(date +%s)"

  echo
  echo "==> ${step_label} $*"
  (cd "$REPO_ROOT" && "$@")
  local rc=$?
  now_ts="$(date +%s)"
  elapsed="$((now_ts - start_ts))"
  if [[ "$rc" -eq 0 ]]; then
    echo "    ${step_label} done (${elapsed}s)"
  else
    echo "    ${step_label} failed (${elapsed}s)"
  fi
  return "$rc"
}

mkdir -p "$OUTPUT_DIR/core" "$OUTPUT_DIR/hard" "$OUTPUT_DIR/final"

graph_duplicate_mode_msg="allow-refill"
if [[ "$STRICT_DUPLICATES" == "1" ]]; then
  graph_duplicate_mode_msg="strict-fail"
fi

echo "SG v7 pilot config:"
echo "  output_dir=$OUTPUT_DIR"
echo "  seed=$SEED"
echo "  core_records=$CORE_RECORDS hard_records=$HARD_RECORDS"
echo "  paraphraser_backend=$PARAPHRASER_BACKEND critic_backend=$CRITIC_BACKEND"
echo "  refill_budget=$REFILL_BUDGET duplicate_mode=$graph_duplicate_mode_msg"
echo "  auto_promote_same_type_review=$AUTO_PROMOTE_SAME_TYPE_REVIEW"
echo "  heartbeat_seconds=$HEARTBEAT_SECONDS total_steps=$TOTAL_STEPS"
echo "  max_technical_source_share=$MAX_TECHNICAL_SOURCE_SHARE"

for bucket in core hard; do
  if [[ "$bucket" == "core" ]]; then
    total_records="$CORE_RECORDS"
  else
    total_records="$HARD_RECORDS"
  fi

  graph_cmd=(
    python3 "docs/SGv7pipeline/graph_generator/01_build_pattern_graphs.py"
    --seed "$SEED"
    --bucket "$bucket"
    --total-records "$total_records"
    --output-jsonl "$OUTPUT_DIR/$bucket/graphs.jsonl"
    --output-manifest "$OUTPUT_DIR/$bucket/graphs.manifest.json"
    --refill-budget "$REFILL_BUDGET"
  )
  if [[ "$STRICT_DUPLICATES" == "1" ]]; then
    graph_cmd+=(--fail-on-duplicates)
  fi
  run "${graph_cmd[@]}"

  run python3 "docs/SGv7pipeline/source_generation/02_generate_source_variants.py" \
    --input-jsonl "$OUTPUT_DIR/$bucket/graphs.jsonl" \
    --output-jsonl "$OUTPUT_DIR/$bucket/source_candidates.jsonl" \
    --reject-log-jsonl "$OUTPUT_DIR/$bucket/source_rejects.jsonl" \
    --seed "$SEED" \
    --difficulty-bucket "$bucket" \
    --max-variants-per-graph "$MAX_VARIANTS_PER_GRAPH" \
    --model-name "$MODEL_NAME" \
    --batch-size "$BATCH_SIZE" \
    --paraphraser-backend "$PARAPHRASER_BACKEND"

  run python3 "docs/SGv7pipeline/validators/05_validate_and_pack.py" \
    --input-jsonl "$OUTPUT_DIR/$bucket/source_candidates.jsonl" \
    --cir-jsonl "$OUTPUT_DIR/$bucket/graphs.jsonl" \
    --accepted-jsonl "$OUTPUT_DIR/$bucket/accepted_source.jsonl" \
    --review-jsonl "$OUTPUT_DIR/$bucket/review_source.jsonl" \
    --rejected-jsonl "$OUTPUT_DIR/$bucket/rejected_source.jsonl" \
    --manifest-json "$OUTPUT_DIR/$bucket/source_validation_manifest.json" \
    --seed "$SEED" \
    --difficulty-bucket "$bucket" \
    --critic-backend "$CRITIC_BACKEND"

  run python3 "docs/SGv7pipeline/augmentation/04_noise_and_morphology.py" \
    --input-jsonl "$OUTPUT_DIR/$bucket/accepted_source.jsonl" \
    --output-jsonl "$OUTPUT_DIR/$bucket/aug_candidates.jsonl" \
    --reject-log-jsonl "$OUTPUT_DIR/$bucket/aug_rejects.jsonl" \
    --seed "$SEED" \
    --difficulty-bucket "$bucket" \
    --max-augmented-variants-per-parent "$MAX_AUGMENTED_VARIANTS_PER_PARENT"

  run python3 "docs/SGv7pipeline/validators/05_validate_and_pack.py" \
    --input-jsonl "$OUTPUT_DIR/$bucket/aug_candidates.jsonl" \
    --cir-jsonl "$OUTPUT_DIR/$bucket/graphs.jsonl" \
    --accepted-jsonl "$OUTPUT_DIR/$bucket/accepted_augmented.jsonl" \
    --review-jsonl "$OUTPUT_DIR/$bucket/review_augmented.jsonl" \
    --rejected-jsonl "$OUTPUT_DIR/$bucket/rejected_augmented.jsonl" \
    --manifest-json "$OUTPUT_DIR/$bucket/aug_validation_manifest.json" \
    --seed "$SEED" \
    --difficulty-bucket "$bucket" \
    --critic-backend "$CRITIC_BACKEND"
done

export SGV7_OUTPUT_DIR="$OUTPUT_DIR"
export SGV7_AUTO_PROMOTE_SAME_TYPE_REVIEW="$AUTO_PROMOTE_SAME_TYPE_REVIEW"
run_with_stdin python3 - <<'PY'
from pathlib import Path
import os
import json
import sys
from copy import deepcopy

root = Path(os.environ["SGV7_OUTPUT_DIR"])
repo_root = Path.cwd()
docs_root = repo_root / "docs" / "SGv7pipeline"
if str(docs_root) not in sys.path:
    sys.path.insert(0, str(docs_root))

from source_generation.metadata import build_graph_constraints  # type: ignore[import-not-found]
from cir_contract.contracts import structural_hash  # type: ignore[import-not-found]

accepted_parts = [
    root / "core" / "accepted_source.jsonl",
    root / "core" / "accepted_augmented.jsonl",
    root / "hard" / "accepted_source.jsonl",
    root / "hard" / "accepted_augmented.jsonl",
]
accepted_out = root / "final" / "accepted_merged.jsonl"

review_parts = [
    root / "core" / "review_source.jsonl",
    root / "core" / "review_augmented.jsonl",
    root / "hard" / "review_source.jsonl",
    root / "hard" / "review_augmented.jsonl",
]
review_out = root / "final" / "review_merged.jsonl"
review_promoted_out = root / "final" / "review_promoted.jsonl"
auto_promote_same_type = os.environ.get("SGV7_AUTO_PROMOTE_SAME_TYPE_REVIEW", "1") == "1"

cir_parts = [
    root / "core" / "graphs.jsonl",
    root / "hard" / "graphs.jsonl",
]


def read_rows(path: Path) -> list[dict]:
    if not path.exists():
        return []
    rows: list[dict] = []
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        if not raw_line.strip():
            continue
        row = json.loads(raw_line)
        if isinstance(row, dict):
            rows.append(row)
    return rows


def is_missing(value: object) -> bool:
    if value is None:
        return True
    if isinstance(value, str):
        return not value.strip()
    if isinstance(value, (list, tuple, dict, set)):
        return len(value) == 0
    return False


def fill_missing(target: dict, key: str, value: object) -> bool:
    if is_missing(target.get(key)) and not is_missing(value):
        target[key] = value
        return True
    return False


cir_index: dict[str, dict] = {}
for path in cir_parts:
    for row in read_rows(path):
        sample_id = str(row.get("sample_id", "")).strip()
        if sample_id and sample_id not in cir_index:
            cir_index[sample_id] = row


def row_priority(row: dict) -> tuple:
    recoverability = (
        row.get("validation_report", {}).get("recoverability_score")
        if isinstance(row.get("validation_report"), dict)
        else None
    )
    recoverability_score = int(recoverability) if isinstance(recoverability, int) else 0
    generation_pass = str(row.get("generation_pass", ""))
    pass_rank = 1 if generation_pass == "augmentation" else 0
    metadata_keys = (
        "pattern_name",
        "contract_version",
        "graph_constraints",
        "prompt_template_version",
        "source_policy_version",
        "model_name",
    )
    metadata_score = sum(0 if is_missing(row.get(key)) else 1 for key in metadata_keys)
    source_len = len(str(row.get("source_text", "")))
    return (recoverability_score, pass_rank, metadata_score, source_len)


def enrich_row(row: dict, sample_id: str) -> tuple[dict, int]:
    merged = deepcopy(row)
    backfilled = 0
    cir_row = cir_index.get(sample_id)
    if cir_row is None:
        return merged, backfilled

    if fill_missing(merged, "graph_id", sample_id):
        backfilled += 1
    if fill_missing(merged, "pattern_name", cir_row.get("pattern_name")):
        backfilled += 1
    if fill_missing(merged, "difficulty_bucket", cir_row.get("difficulty_bucket")):
        backfilled += 1
    if fill_missing(merged, "contract_version", cir_row.get("contract_version", "sg_v7_contract_v1")):
        backfilled += 1
    if fill_missing(merged, "graph_hash", structural_hash(cir_row)):
        backfilled += 1
    if fill_missing(merged, "graph_constraints", build_graph_constraints(cir_row)):
        backfilled += 1
    return merged, backfilled


def merge_rows(primary: dict, secondary: dict, sample_id: str) -> tuple[dict, int]:
    preferred = primary
    donor = secondary
    if row_priority(secondary) > row_priority(primary):
        preferred = secondary
        donor = primary

    merged = deepcopy(preferred)
    backfilled = 0
    for key in (
        "pattern_name",
        "contract_version",
        "difficulty_bucket",
        "prompt_template_version",
        "source_policy_version",
        "model_name",
        "graph_constraints",
        "acceptance",
        "validation",
        "surface_anchor_snapshot",
        "augmentation_policy_version",
        "parent_variant_id",
        "risk_flags",
        "graph_hash",
        "graph_id",
    ):
        if fill_missing(merged, key, donor.get(key)):
            backfilled += 1

    if isinstance(merged.get("validation_report"), dict) and isinstance(donor.get("validation_report"), dict):
        for key, value in donor["validation_report"].items():
            if fill_missing(merged["validation_report"], key, value):
                backfilled += 1

    merged, extra_backfilled = enrich_row(merged, sample_id)
    backfilled += extra_backfilled
    return merged, backfilled


def merge_part_rows(parts: list[Path]) -> tuple[dict[str, dict], int, int]:
    by_sample_id: dict[str, dict] = {}
    conflicting_duplicates = 0
    backfilled_fields = 0
    for path in parts:
        for row in read_rows(path):
            sample_id = str(row.get("sample_id", "")).strip()
            if not sample_id:
                continue
            row, added = enrich_row(row, sample_id)
            backfilled_fields += added
            existing = by_sample_id.get(sample_id)
            if existing is None:
                by_sample_id[sample_id] = row
                continue
            if existing != row:
                conflicting_duplicates += 1
            merged, added = merge_rows(existing, row, sample_id)
            by_sample_id[sample_id] = merged
            backfilled_fields += added
    return by_sample_id, conflicting_duplicates, backfilled_fields


accepted_by_sample, conflicting_duplicates, accepted_backfilled = merge_part_rows(accepted_parts)
accepted_lines = [
    json.dumps(accepted_by_sample[sample_id], ensure_ascii=False)
    for sample_id in sorted(accepted_by_sample.keys())
]
accepted_out.write_text("".join(line + "\n" for line in accepted_lines), encoding="utf-8")

review_by_sample_id, review_conflicting_duplicates, review_backfilled = merge_part_rows(review_parts)
review_lines = [
    json.dumps(review_by_sample_id[sample_id], ensure_ascii=False)
    for sample_id in sorted(review_by_sample_id.keys())
]
review_out.write_text("".join(line + "\n" for line in review_lines), encoding="utf-8")

promoted_rows: list[dict] = []
if auto_promote_same_type:
    for sample_id in sorted(review_by_sample_id.keys()):
        row = review_by_sample_id[sample_id]
        review_reasons = row.get("validation_report", {}).get("review_reasons", [])
        if not isinstance(review_reasons, list):
            continue
        if "review_same_type_marker_conflict" not in review_reasons:
            continue
        promoted_rows.append(
            {
                "sample_id": sample_id,
                "promoted_train_eligibility": "hard_or_preference_only",
                "review_decision": "promote_same_type_marker_conflict_for_pilot_coverage",
                "reviewed_at": "pilot-auto",
                "reviewer": "sgv7_pilot_script",
            }
        )

review_promoted_out.write_text(
    "".join(json.dumps(row, ensure_ascii=False) + "\n" for row in promoted_rows),
    encoding="utf-8",
)

cir_out = root / "final" / "cir_merged.jsonl"
cir_out.write_text(
    "".join(path.read_text(encoding="utf-8") for path in cir_parts if path.exists()),
    encoding="utf-8",
)

print(f"Merged accepted set -> {accepted_out}")
print(f"Merged review set -> {review_out}")
print(f"Review conflicts resolved by priority -> {review_conflicting_duplicates}")
print(f"Merged CIR set -> {cir_out}")
print(f"Accepted conflicts resolved by priority -> {conflicting_duplicates}")
print(f"Accepted metadata fields backfilled -> {accepted_backfilled}")
print(f"Review metadata fields backfilled -> {review_backfilled}")
print(f"Auto-promoted same_type review rows -> {len(promoted_rows)}")
PY

run python3 "docs/SGv7pipeline/dataset_builder/06_build_dataset_splits.py" \
  --accepted-jsonl "$OUTPUT_DIR/final/accepted_merged.jsonl" \
  --cir-jsonl "$OUTPUT_DIR/final/cir_merged.jsonl" \
  --output-dir "$OUTPUT_DIR/final/dataset" \
  --seed "$SEED" \
  --manual-review-jsonl "$OUTPUT_DIR/final/review_merged.jsonl" \
  --review-promoted-jsonl "$OUTPUT_DIR/final/review_promoted.jsonl" \
  --max-technical-source-share "$MAX_TECHNICAL_SOURCE_SHARE"

echo
echo "Pilot run completed."
echo "Inspect:"
echo "  $OUTPUT_DIR/final/accepted_merged.jsonl"
echo "  $OUTPUT_DIR/final/review_merged.jsonl"
echo "  $OUTPUT_DIR/final/review_promoted.jsonl"
echo "  $OUTPUT_DIR/final/cir_merged.jsonl"
echo "  $OUTPUT_DIR/final/dataset"
