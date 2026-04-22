#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path

from datasets import build_critic_rank_rows, read_jsonl, split_rows, write_jsonl


def main() -> None:
    parser = argparse.ArgumentParser(description="Build v8 critic rank corpus from eval/prediction artifacts")
    parser.add_argument("--eval-cases-jsonl", required=True, type=Path)
    parser.add_argument("--candidate-predictions-jsonl", required=True, type=Path)
    parser.add_argument("--baseline-predictions-jsonl", required=True, type=Path)
    parser.add_argument("--candidate-case-results-jsonl", required=True, type=Path)
    parser.add_argument("--baseline-case-results-jsonl", required=True, type=Path)
    parser.add_argument("--candidate-model-id", required=True)
    parser.add_argument("--baseline-model-id", required=True)
    parser.add_argument("--paired-case-results-jsonl", type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--val-fraction", type=float, default=0.1)
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    output_dir = args.output_dir.expanduser()
    output_dir.mkdir(parents=True, exist_ok=True)

    rows = build_critic_rank_rows(
        eval_case_rows=read_jsonl(args.eval_cases_jsonl.expanduser()),
        candidate_prediction_rows=read_jsonl(args.candidate_predictions_jsonl.expanduser()),
        baseline_prediction_rows=read_jsonl(args.baseline_predictions_jsonl.expanduser()),
        candidate_case_rows=read_jsonl(args.candidate_case_results_jsonl.expanduser()),
        baseline_case_rows=read_jsonl(args.baseline_case_results_jsonl.expanduser()),
        candidate_model_id=args.candidate_model_id,
        baseline_model_id=args.baseline_model_id,
        paired_case_rows=read_jsonl(args.paired_case_results_jsonl.expanduser()) if args.paired_case_results_jsonl else None,
    )
    train_rows, val_rows = split_rows(rows, key_field="split_family_id", val_fraction=args.val_fraction, seed=args.seed)

    write_jsonl(rows, output_dir / "v8_critic_rank_all.jsonl")
    write_jsonl(train_rows, output_dir / "v8_critic_rank_train.jsonl")
    write_jsonl(val_rows, output_dir / "v8_critic_rank_val.jsonl")

    manifest = {
        "contract_version": "sg_v8_critic_rank_v1",
        "candidate_model_id": args.candidate_model_id,
        "baseline_model_id": args.baseline_model_id,
        "total_rows": len(rows),
        "train_rows": len(train_rows),
        "val_rows": len(val_rows),
    }
    (output_dir / "v8_critic_rank_manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
