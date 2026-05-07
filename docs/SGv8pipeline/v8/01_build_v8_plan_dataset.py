#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path

from datasets import build_plan_sft_rows, read_jsonl, split_rows, write_jsonl


def main() -> None:
    parser = argparse.ArgumentParser(description="Build v8 ScenePlanIR SFT corpus from CIR jsonl")
    parser.add_argument("--cir-jsonl", required=True, help="Path to CIR jsonl")
    parser.add_argument("--output-jsonl", help="Path to output plan jsonl")
    parser.add_argument("--output-dir", type=Path, help="Optional output dir for all/train/val plan dataset files")
    parser.add_argument("--val-fraction", type=float, default=0.1)
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()
    if not args.output_jsonl and args.output_dir is None:
        parser.error("one of --output-jsonl or --output-dir is required")

    cir_rows = read_jsonl(Path(args.cir_jsonl).expanduser())
    output_rows = build_plan_sft_rows(cir_rows)
    if args.output_jsonl:
        write_jsonl(output_rows, Path(args.output_jsonl).expanduser())
    if args.output_dir is not None:
        output_dir = args.output_dir.expanduser()
        output_dir.mkdir(parents=True, exist_ok=True)
        train_rows, val_rows = split_rows(output_rows, key_field="split_family_id", val_fraction=args.val_fraction, seed=args.seed)
        write_jsonl(output_rows, output_dir / "v8_plan_sft_all.jsonl")
        write_jsonl(train_rows, output_dir / "v8_plan_sft_train.jsonl")
        write_jsonl(val_rows, output_dir / "v8_plan_sft_val.jsonl")
        manifest = {
            "contract_version": "sg_v8_plan_sft_v1",
            "total_rows": len(output_rows),
            "train_rows": len(train_rows),
            "val_rows": len(val_rows),
        }
        (output_dir / "v8_plan_sft_manifest.json").write_text(
            json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )


if __name__ == "__main__":
    main()
