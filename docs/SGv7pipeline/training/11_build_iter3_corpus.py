#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from training import Iter3CorpusBuildError, Iter3CorpusBuildRequest, build_iter3_corpus


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build iter3 delta-SFT and preference corpora from SG v7 benchmark artifacts."
    )
    parser.add_argument("--eval-cases-jsonl", type=Path, required=True)
    parser.add_argument("--cir-jsonl", type=Path, required=True)
    parser.add_argument("--v7-case-results-jsonl", type=Path, required=True)
    parser.add_argument("--iter1-case-results-jsonl", type=Path, required=True)
    parser.add_argument("--iter2-case-results-jsonl", type=Path, required=True)
    parser.add_argument("--v7-predictions-jsonl", type=Path, required=True)
    parser.add_argument("--iter1-predictions-jsonl", type=Path, required=True)
    parser.add_argument("--iter2-predictions-jsonl", type=Path, required=True)
    parser.add_argument("--iter2-vs-iter1-paired-jsonl", type=Path, required=True)
    parser.add_argument("--iter2-vs-v7-paired-jsonl", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--seed", type=int, required=True)
    parser.add_argument("--delta-sft-val-ratio", type=float, default=0.10)
    parser.add_argument("--delta-sft-max-family-share", type=float, default=0.50)
    parser.add_argument("--preference-val-ratio", type=float, default=0.10)
    parser.add_argument("--max-simple-dialogue-share", type=float, default=0.15)
    parser.add_argument("--manual-review-samples-per-pattern", type=int, default=5)
    parser.add_argument(
        "--min-family-counts-json",
        type=Path,
        help="Optional JSON object override for iter3 family floors (e.g. {\"three_beat\": 8}).",
    )
    return parser.parse_args()


def _load_min_family_counts(path: Path | None) -> dict[str, int] | None:
    if path is None:
        return None
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise Iter3CorpusBuildError("min_family_counts_json must be a JSON object")
    return {str(key): int(value) for key, value in payload.items()}


def main() -> int:
    args = _parse_args()
    try:
        manifest = build_iter3_corpus(
            Iter3CorpusBuildRequest(
                eval_cases_jsonl=args.eval_cases_jsonl,
                cir_jsonl=args.cir_jsonl,
                v7_case_results_jsonl=args.v7_case_results_jsonl,
                iter1_case_results_jsonl=args.iter1_case_results_jsonl,
                iter2_case_results_jsonl=args.iter2_case_results_jsonl,
                v7_predictions_jsonl=args.v7_predictions_jsonl,
                iter1_predictions_jsonl=args.iter1_predictions_jsonl,
                iter2_predictions_jsonl=args.iter2_predictions_jsonl,
                iter2_vs_iter1_paired_jsonl=args.iter2_vs_iter1_paired_jsonl,
                iter2_vs_v7_paired_jsonl=args.iter2_vs_v7_paired_jsonl,
                output_dir=args.output_dir,
                seed=args.seed,
                delta_sft_val_ratio=args.delta_sft_val_ratio,
                delta_sft_max_family_share=args.delta_sft_max_family_share,
                preference_val_ratio=args.preference_val_ratio,
                max_simple_dialogue_share=args.max_simple_dialogue_share,
                manual_review_samples_per_pattern=args.manual_review_samples_per_pattern,
                min_family_counts=_load_min_family_counts(args.min_family_counts_json),
            )
        )
    except (Iter3CorpusBuildError, ValueError) as exc:
        sys.stderr.write(f"Iter3 corpus build failed: {exc}\n")
        return 2

    counts = manifest.get("counts", {})
    sys.stdout.write(
        "Built iter3 corpora: "
        f"delta_sft={counts.get('delta_sft_total', 0)} "
        f"preference={counts.get('preference_total', 0)} "
        f"output={args.output_dir}\n"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
