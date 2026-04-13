#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from validators import ValidationRequest, validate_and_pack


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Validate and pack SG v7 source/augmentation candidates.")
    parser.add_argument("--input-jsonl", type=Path, required=True)
    parser.add_argument("--cir-jsonl", type=Path)
    parser.add_argument("--accepted-jsonl", type=Path, required=True)
    parser.add_argument("--review-jsonl", type=Path, required=True)
    parser.add_argument("--rejected-jsonl", type=Path, required=True)
    parser.add_argument("--manifest-json", type=Path, required=True)
    parser.add_argument("--seed", type=int, required=True)
    parser.add_argument("--difficulty-bucket", choices=["core", "hard"], dest="difficulty_bucket")
    parser.add_argument("--critic-backend", choices=["heuristic", "openai"], default="heuristic")
    parser.add_argument("--critic-model", default="gpt-5.4-nano")
    parser.add_argument("--disable-critic", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = _parse_args()
    request = ValidationRequest(
        input_jsonl=args.input_jsonl,
        cir_jsonl=args.cir_jsonl,
        accepted_jsonl=args.accepted_jsonl,
        review_jsonl=args.review_jsonl,
        rejected_jsonl=args.rejected_jsonl,
        manifest_json=args.manifest_json,
        seed=args.seed,
        difficulty_bucket=args.difficulty_bucket,
        critic_backend=args.critic_backend,
        critic_model=args.critic_model,
        enable_critic=not args.disable_critic,
    )
    result = validate_and_pack(request)
    sys.stdout.write(
        f"Validated {result.manifest['total_input_count']} samples -> "
        f"{request.accepted_jsonl}, {request.review_jsonl}, {request.rejected_jsonl}\n"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
