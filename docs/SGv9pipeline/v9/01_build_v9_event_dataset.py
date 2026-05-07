#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from v9.datasets import build_v9_event_sft_rows, read_jsonl, split_rows, write_jsonl


def _write_manifest(*, rows: list[dict], train_rows: list[dict], val_rows: list[dict], output_dir: Path) -> None:
    manifest = {
        "contract_version": "sg_v9_event_dataset_v1",
        "total_rows": len(rows),
        "train_rows": len(train_rows),
        "val_rows": len(val_rows),
        "difficulty_counts": dict(
            sorted(Counter(str(row.get("packaging_metadata", {}).get("difficulty_bucket") or "") for row in rows).items())
        ),
    }
    (output_dir / "v9_event_dataset_manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="Build v9 event-table SFT dataset from CIR jsonl")
    parser.add_argument("--cir-jsonl", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--val-fraction", type=float, default=0.1)
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    output_dir = args.output_dir.expanduser()
    output_dir.mkdir(parents=True, exist_ok=True)
    cir_rows = read_jsonl(args.cir_jsonl.expanduser())
    rows = build_v9_event_sft_rows(cir_rows)
    train_rows, val_rows = split_rows(rows, key_field="split_family_id", val_fraction=args.val_fraction, seed=args.seed)

    write_jsonl(rows, output_dir / "v9_event_sft_all.jsonl")
    write_jsonl(train_rows, output_dir / "v9_event_sft_train.jsonl")
    write_jsonl(val_rows, output_dir / "v9_event_sft_val.jsonl")
    _write_manifest(rows=rows, train_rows=train_rows, val_rows=val_rows, output_dir=output_dir)


if __name__ == "__main__":
    main()
