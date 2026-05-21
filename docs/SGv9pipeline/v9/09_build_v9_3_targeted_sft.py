from __future__ import annotations

import argparse
import json
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any

try:
    from .datasets import build_v9_event_sft_rows, split_rows, write_jsonl
except ImportError:  # pragma: no cover
    import sys

    sys.path.append(str(Path(__file__).resolve().parents[3]))
    from docs.SGv9pipeline.v9.datasets import build_v9_event_sft_rows, split_rows, write_jsonl

import importlib.util

helper_path = Path(__file__).with_name("06_build_v9_2_targeted_sft.py")
spec = importlib.util.spec_from_file_location("v9_2_targeted_helper", helper_path)
if spec is None or spec.loader is None:
    raise RuntimeError(f"Cannot load helper module: {helper_path}")
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)
hard_case_to_cir = helper.hard_case_to_cir
read_jsonl = helper.read_jsonl
validate_sft_row = helper.validate_sft_row


def _rewrite_v9_2_to_v9_3(value: Any) -> Any:
    if isinstance(value, str):
        return value.replace("v9_2", "v9_3")
    if isinstance(value, list):
        return [_rewrite_v9_2_to_v9_3(item) for item in value]
    if isinstance(value, dict):
        return {key.replace("v9_2", "v9_3"): _rewrite_v9_2_to_v9_3(item) for key, item in value.items()}
    return value


def hard_case_to_v9_3_cir(hard_case: dict[str, Any]) -> dict[str, Any]:
    cir = _rewrite_v9_2_to_v9_3(hard_case_to_cir(hard_case))
    metadata = cir.setdefault("internal_metadata", {})
    metadata["generator_name"] = "v9_3_exact_failure_target_builder"
    metadata["generator_version"] = "v1"
    metadata["v9_3_origin"] = "policy_corrected_failure_mining"
    tags = set(str(tag) for tag in cir.get("semantic_tags", []) if str(tag))
    tags.add("v9_3_targeted")
    tags.add("v9_3_policy_corrected_failure")
    cir["semantic_tags"] = sorted(tags)
    cir["source_variant_key"] = "v9_3_exact_failure"
    return cir


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--hard-cases", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--val-fraction", type=float, default=0.15)
    args = parser.parse_args()

    hard_cases = read_jsonl(args.hard_cases)
    cir_rows = [hard_case_to_v9_3_cir(row) for row in hard_cases]
    sft_rows = build_v9_event_sft_rows(cir_rows)
    hard_case_by_original_sample = {str(row["original_case"].get("sample_id") or ""): row for row in hard_cases}

    validation_issues: dict[str, list[str]] = {}
    for row in sft_rows:
        original_sample_id = str(row.get("packaging_metadata", {}).get("sample_id") or "").removeprefix(
            "v9_3_hardcase__"
        )
        hard_case = hard_case_by_original_sample.get(original_sample_id, {})
        metadata = row.setdefault("packaging_metadata", {})
        metadata["v9_3_targeted"] = True
        metadata["v9_3_source"] = "policy_corrected_failure_mining"
        metadata["v9_3_origin_eval_case_id"] = str(hard_case.get("eval_case_id") or "")
        metadata["v9_3_hard_cluster"] = str(hard_case.get("cluster") or "")
        metadata["v9_3_training_target"] = "sg_v9_event_table_v1"
        issues = validate_sft_row(row)
        if issues:
            validation_issues[str(row.get("sample_id") or "")] = issues

    train_rows, val_rows = split_rows(
        sft_rows,
        key_field="split_family_id",
        val_fraction=args.val_fraction,
        seed=args.seed,
    )

    output_dir = args.output_dir
    output_dir.mkdir(parents=True, exist_ok=True)
    write_jsonl(hard_cases, output_dir / "v9_3_hard_cases.jsonl")
    write_jsonl(sft_rows, output_dir / "v9_3_event_sft_targeted_all.jsonl")
    write_jsonl(train_rows, output_dir / "v9_3_event_sft_targeted_train.jsonl")
    write_jsonl(val_rows, output_dir / "v9_3_event_sft_targeted_val.jsonl")

    cluster_counts = Counter(str(row.get("cluster") or "unknown") for row in hard_cases)
    row_counts_by_cluster: Counter[str] = Counter()
    action_counts: Counter[str] = Counter()
    event_rows_by_cluster: defaultdict[str, int] = defaultdict(int)
    for row in sft_rows:
        cluster = str(row.get("packaging_metadata", {}).get("v9_3_hard_cluster") or "unknown")
        row_counts_by_cluster[cluster] += 1
        events = row.get("target_event_table", {}).get("rows", [])
        event_rows_by_cluster[cluster] += len(events)
        for event in events:
            action_counts[str(event.get("actionType") or "unknown")] += 1

    manifest = {
        "contract_version": "sg_v9_3_targeted_event_sft_manifest_v1",
        "hard_case_source": str(args.hard_cases),
        "total_hard_cases": len(hard_cases),
        "cluster_counts": dict(sorted(cluster_counts.items())),
        "total_sft_rows": len(sft_rows),
        "train_rows": len(train_rows),
        "val_rows": len(val_rows),
        "event_rows_by_cluster": dict(sorted(event_rows_by_cluster.items())),
        "sft_rows_by_cluster": dict(sorted(row_counts_by_cluster.items())),
        "action_type_counts": dict(sorted(action_counts.items())),
        "validation": {
            "valid_rows": len(sft_rows) - len(validation_issues),
            "invalid_rows": len(validation_issues),
            "issues_by_sample_id": validation_issues,
        },
    }
    (output_dir / "v9_3_targeted_sft_manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(manifest, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
