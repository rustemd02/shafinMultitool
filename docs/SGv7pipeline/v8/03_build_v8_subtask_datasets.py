#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from collections import Counter, defaultdict
from pathlib import Path

from datasets import build_subtask_sft_rows, read_jsonl, split_rows, write_jsonl


def _write_manifest(*, rows: list[dict], train_rows: list[dict], val_rows: list[dict], output_dir: Path) -> None:
    subtask_counts = Counter(str(row.get("subtask_type") or "") for row in rows)
    split_counts = defaultdict(Counter)
    for split_name, split_rowset in (("train", train_rows), ("val", val_rows)):
        for row in split_rowset:
            split_counts[split_name][str(row.get("subtask_type") or "")] += 1
    manifest = {
        "contract_version": "sg_v8_subtask_dataset_v1",
        "total_rows": len(rows),
        "train_rows": len(train_rows),
        "val_rows": len(val_rows),
        "subtask_counts": dict(sorted(subtask_counts.items())),
        "split_subtask_counts": {
            split: dict(sorted(counter.items()))
            for split, counter in sorted(split_counts.items())
        },
    }
    (output_dir / "v8_subtask_dataset_manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="Build v8 subtask SFT corpora from CIR jsonl")
    parser.add_argument("--cir-jsonl", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--val-fraction", type=float, default=0.1)
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    output_dir = args.output_dir.expanduser()
    output_dir.mkdir(parents=True, exist_ok=True)

    cir_rows = read_jsonl(args.cir_jsonl.expanduser())
    rows = build_subtask_sft_rows(cir_rows)
    train_rows, val_rows = split_rows(rows, key_field="split_family_id", val_fraction=args.val_fraction, seed=args.seed)

    write_jsonl(rows, output_dir / "v8_subtask_sft_all.jsonl")
    write_jsonl(train_rows, output_dir / "v8_subtask_sft_train.jsonl")
    write_jsonl(val_rows, output_dir / "v8_subtask_sft_val.jsonl")

    for subtask_type in sorted({str(row.get("subtask_type") or "") for row in rows}):
        write_jsonl([row for row in rows if row.get("subtask_type") == subtask_type], output_dir / f"{subtask_type}_sft_all.jsonl")
        write_jsonl([row for row in train_rows if row.get("subtask_type") == subtask_type], output_dir / f"{subtask_type}_sft_train.jsonl")
        write_jsonl([row for row in val_rows if row.get("subtask_type") == subtask_type], output_dir / f"{subtask_type}_sft_val.jsonl")

    _write_manifest(rows=rows, train_rows=train_rows, val_rows=val_rows, output_dir=output_dir)


if __name__ == "__main__":
    main()
