#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from augmentation import AugmentationRequest, generate_augmented_variants


def _log(stage: str, message: str) -> None:
    sys.stdout.write(f"[sgv7:augmentation] {stage}: {message}\n")
    sys.stdout.flush()


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate SG v7 augmentation variants from accepted source JSONL.")
    parser.add_argument("--input-jsonl", type=Path, required=True)
    parser.add_argument("--output-jsonl", type=Path, required=True)
    parser.add_argument("--reject-log-jsonl", type=Path)
    parser.add_argument("--seed", type=int, required=True)
    parser.add_argument("--difficulty-bucket", choices=["core", "hard"], dest="difficulty_bucket")
    parser.add_argument("--max-augmented-variants-per-parent", type=int)
    parser.add_argument("--enable-risky", action="store_true")
    return parser.parse_args()


def main() -> int:
    _log("stage 1/4", "parse args")
    args = _parse_args()
    _log(
        "stage 2/4",
        f"build request bucket={args.difficulty_bucket or 'all'} max_augmented={args.max_augmented_variants_per_parent or 'auto'} risky={bool(args.enable_risky)}",
    )
    request = AugmentationRequest(
        input_jsonl=args.input_jsonl,
        output_jsonl=args.output_jsonl,
        reject_log_jsonl=args.reject_log_jsonl,
        seed=args.seed,
        difficulty_bucket=args.difficulty_bucket,
        max_augmented_variants_per_parent=args.max_augmented_variants_per_parent,
        enable_risky=args.enable_risky,
    )
    _log("stage 3/4", "run augmentation generator")
    result = generate_augmented_variants(request)
    _log("stage 4/4", f"write artifacts accepted={len(result.accepted_records)} rejected={len(result.reject_records)}")
    sys.stdout.write(
        f"Built {len(result.accepted_records)} augmentation variants -> {request.output_jsonl}"
        + (f" and {request.reject_log_jsonl}" if request.reject_log_jsonl is not None else "")
        + "\n"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
