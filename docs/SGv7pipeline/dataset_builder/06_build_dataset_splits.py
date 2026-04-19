#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from dataset_builder import DatasetBuildError, DatasetBuildRequest, build_dataset


def _log(stage: str, message: str) -> None:
    sys.stdout.write(f"[sgv7:dataset_builder] {stage}: {message}\n")
    sys.stdout.flush()


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build SG v7 SFT/preference dataset splits and manifests.")
    parser.add_argument("--accepted-jsonl", type=Path, required=True)
    parser.add_argument("--cir-jsonl", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--seed", type=int, required=True)
    parser.add_argument("--manual-review-jsonl", type=Path)
    parser.add_argument("--review-promoted-jsonl", type=Path)
    parser.add_argument("--rejected-jsonl", type=Path)
    parser.add_argument("--runtime-failures-jsonl", type=Path)
    parser.add_argument("--contract-version", default="sg_v7_contract_v1")
    parser.add_argument("--sft-train-ratio", type=float, default=0.84)
    parser.add_argument("--sft-val-ratio", type=float, default=0.08)
    parser.add_argument("--sft-test-ratio", type=float, default=0.08)
    parser.add_argument("--preference-train-ratio", type=float, default=0.85)
    parser.add_argument("--preference-val-ratio", type=float, default=0.10)
    parser.add_argument("--preference-test-ratio", type=float, default=0.05)
    parser.add_argument(
        "--max-technical-source-share",
        type=float,
        default=None,
        help="Maximum share of SFT samples containing technical ids (actor_*/object_marked_*).",
    )
    parser.add_argument(
        "--max-comp-family-share",
        type=float,
        default=None,
        help="Maximum share of SFT samples containing comp/computer-family lexemes.",
    )
    parser.add_argument(
        "--max-notebook-family-share",
        type=float,
        default=None,
        help="Maximum share of SFT samples containing notebook-family lexemes.",
    )
    parser.add_argument(
        "--max-smoke-family-share",
        type=float,
        default=None,
        help="Maximum share of SFT samples containing smoke-family lexemes.",
    )
    return parser.parse_args()


def main() -> int:
    _log("stage 1/4", "parse args")
    args = _parse_args()
    technical_share = "off" if args.max_technical_source_share is None else str(args.max_technical_source_share)
    _log(
        "stage 2/4",
        "build request "
        f"output_dir={args.output_dir} contract={args.contract_version} "
        f"max_technical_share={technical_share} "
        f"lexeme_caps(comp/notebook/smoke)="
        f"{args.max_comp_family_share}/{args.max_notebook_family_share}/{args.max_smoke_family_share}",
    )
    request = DatasetBuildRequest(
        accepted_jsonl=args.accepted_jsonl,
        manual_review_jsonl=args.manual_review_jsonl,
        review_promoted_jsonl=args.review_promoted_jsonl,
        rejected_jsonl=args.rejected_jsonl,
        cir_jsonl=args.cir_jsonl,
        runtime_failures_jsonl=args.runtime_failures_jsonl,
        output_dir=args.output_dir,
        seed=args.seed,
        contract_version=args.contract_version,
        sft_train_ratio=args.sft_train_ratio,
        sft_val_ratio=args.sft_val_ratio,
        sft_test_ratio=args.sft_test_ratio,
        preference_train_ratio=args.preference_train_ratio,
        preference_val_ratio=args.preference_val_ratio,
        preference_test_ratio=args.preference_test_ratio,
        max_technical_source_share=args.max_technical_source_share,
        max_comp_family_share=args.max_comp_family_share,
        max_notebook_family_share=args.max_notebook_family_share,
        max_smoke_family_share=args.max_smoke_family_share,
    )
    try:
        _log("stage 3/4", "run dataset assembly")
        result = build_dataset(request)
    except DatasetBuildError as exc:
        sys.stderr.write(f"Dataset build failed: {exc}\n")
        return 2

    sft_counts = {split: len(rows) for split, rows in result.sft_records.items()}
    pref_counts = {split: len(rows) for split, rows in result.preference_records.items()}
    _log("stage 4/4", f"write artifacts sft={sft_counts} preference={pref_counts}")
    sys.stdout.write(
        "Built SG v7 dataset artifacts: "
        f"sft={sft_counts} preference={pref_counts} output={args.output_dir}\n"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
