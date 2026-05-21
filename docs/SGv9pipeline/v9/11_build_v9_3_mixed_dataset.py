from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

try:
    from .datasets import read_jsonl, split_rows, write_jsonl
except ImportError:  # pragma: no cover
    import sys

    sys.path.append(str(Path(__file__).resolve().parents[3]))
    from docs.SGv9pipeline.v9.datasets import read_jsonl, split_rows, write_jsonl


def dedupe_rows(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    seen: set[str] = set()
    output: list[dict[str, Any]] = []
    for row in rows:
        key = str(row.get("sample_id") or row.get("packaging_metadata", {}).get("sample_id") or "")
        if not key:
            key = json.dumps(row.get("slot_catalog", {}), ensure_ascii=False, sort_keys=True)
        if key in seen:
            continue
        seen.add(key)
        output.append(row)
    return output


def count_source(rows: list[dict[str, Any]], key: str) -> int:
    return sum(1 for row in rows if row.get("packaging_metadata", {}).get(key))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-all", type=Path, required=True)
    parser.add_argument("--exact-targeted-all", type=Path, required=True)
    parser.add_argument("--augmented-all", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--val-fraction", type=float, default=0.15)
    args = parser.parse_args()

    base_rows = read_jsonl(args.base_all)
    exact_rows = read_jsonl(args.exact_targeted_all)
    augmented_rows = read_jsonl(args.augmented_all)
    mixed_all = dedupe_rows(base_rows + exact_rows + augmented_rows)
    train_rows, val_rows = split_rows(
        mixed_all,
        key_field="split_family_id",
        val_fraction=args.val_fraction,
        seed=args.seed,
    )

    output_dir = args.output_dir
    output_dir.mkdir(parents=True, exist_ok=True)
    write_jsonl(mixed_all, output_dir / "v9_3_event_sft_mixed_all.jsonl")
    write_jsonl(train_rows, output_dir / "v9_3_event_sft_mixed_train.jsonl")
    write_jsonl(val_rows, output_dir / "v9_3_event_sft_mixed_val.jsonl")

    manifest = {
        "contract_version": "sg_v9_3_mixed_event_dataset_manifest_v1",
        "all_rows": len(mixed_all),
        "train_rows": len(train_rows),
        "val_rows": len(val_rows),
        "seed": args.seed,
        "val_fraction": args.val_fraction,
        "inputs": {
            "base_all": str(args.base_all),
            "exact_targeted_all": str(args.exact_targeted_all),
            "augmented_all": str(args.augmented_all),
        },
        "input_row_counts": {
            "base_all": len(base_rows),
            "exact_targeted_all": len(exact_rows),
            "augmented_all": len(augmented_rows),
        },
        "targeted_row_counts": {
            "v9_2_targeted_in_base": count_source(base_rows, "v9_2_targeted"),
            "v9_3_exact_targeted": count_source(exact_rows, "v9_3_targeted"),
            "v9_3_augmented_targeted": count_source(augmented_rows, "v9_3_targeted"),
            "v9_3_total": count_source(mixed_all, "v9_3_targeted"),
        },
    }
    (output_dir / "v9_3_event_sft_mixed_manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(manifest, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
