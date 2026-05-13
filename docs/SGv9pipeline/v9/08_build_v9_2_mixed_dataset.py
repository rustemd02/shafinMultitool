from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

try:
    from .datasets import write_jsonl
except ImportError:  # pragma: no cover
    import sys

    sys.path.append(str(Path(__file__).resolve().parents[3]))
    from docs.SGv9pipeline.v9.datasets import write_jsonl


def read_jsonl(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    with path.open("r", encoding="utf-8") as handle:
        for line in handle:
            payload = line.strip()
            if payload:
                rows.append(json.loads(payload))
    return rows


def dedupe_rows(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    seen: set[str] = set()
    deduped: list[dict[str, Any]] = []
    for row in rows:
        sample_id = str(row.get("sample_id") or "")
        if not sample_id or sample_id in seen:
            continue
        seen.add(sample_id)
        deduped.append(row)
    return deduped


def count_targeted(rows: list[dict[str, Any]]) -> int:
    return sum(1 for row in rows if row.get("packaging_metadata", {}).get("v9_2_targeted"))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-all", type=Path, required=True)
    parser.add_argument("--base-train", type=Path, required=True)
    parser.add_argument("--base-val", type=Path, required=True)
    parser.add_argument("--hard-all", type=Path, required=True)
    parser.add_argument("--hard-train", type=Path, required=True)
    parser.add_argument("--hard-val", type=Path, required=True)
    parser.add_argument("--aug-all", type=Path, required=True)
    parser.add_argument("--aug-train", type=Path, required=True)
    parser.add_argument("--aug-val", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()

    base_all = read_jsonl(args.base_all)
    base_train = read_jsonl(args.base_train)
    base_val = read_jsonl(args.base_val)
    hard_all = read_jsonl(args.hard_all)
    hard_train = read_jsonl(args.hard_train)
    hard_val = read_jsonl(args.hard_val)
    aug_all = read_jsonl(args.aug_all)
    aug_train = read_jsonl(args.aug_train)
    aug_val = read_jsonl(args.aug_val)

    mixed_all = dedupe_rows(base_all + hard_all + aug_all)
    mixed_train = dedupe_rows(base_train + hard_train + aug_train)
    mixed_val = dedupe_rows(base_val + hard_val + aug_val)

    output_dir = args.output_dir
    output_dir.mkdir(parents=True, exist_ok=True)
    write_jsonl(mixed_all, output_dir / "v9_2_event_sft_mixed_all.jsonl")
    write_jsonl(mixed_train, output_dir / "v9_2_event_sft_mixed_train.jsonl")
    write_jsonl(mixed_val, output_dir / "v9_2_event_sft_mixed_val.jsonl")

    manifest = {
        "contract_version": "sg_v9_2_mixed_event_dataset_manifest_v1",
        "all_rows": len(mixed_all),
        "train_rows": len(mixed_train),
        "val_rows": len(mixed_val),
        "base_rows": {
            "all": len(base_all),
            "train": len(base_train),
            "val": len(base_val),
        },
        "hard_targeted_rows": {
            "all": len(hard_all),
            "train": len(hard_train),
            "val": len(hard_val),
        },
        "augmented_targeted_rows": {
            "all": len(aug_all),
            "train": len(aug_train),
            "val": len(aug_val),
        },
        "mixed_targeted_rows": {
            "all": count_targeted(mixed_all),
            "train": count_targeted(mixed_train),
            "val": count_targeted(mixed_val),
        },
        "sources": {
            "base_all": str(args.base_all),
            "hard_all": str(args.hard_all),
            "aug_all": str(args.aug_all),
        },
    }
    (output_dir / "v9_2_event_sft_mixed_manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(manifest, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
