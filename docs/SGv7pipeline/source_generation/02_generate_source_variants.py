#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from source_generation import SourceGenerationRequest, generate_source_variants


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate SG v7 source variants from CIR graph JSONL.")
    parser.add_argument("--input-jsonl", type=Path, required=True)
    parser.add_argument("--output-jsonl", type=Path, required=True)
    parser.add_argument("--reject-log-jsonl", type=Path)
    parser.add_argument("--seed", type=int, required=True)
    parser.add_argument("--difficulty-bucket", choices=["core", "hard"], dest="difficulty_bucket")
    parser.add_argument("--max-graphs", type=int)
    parser.add_argument("--max-variants-per-graph", type=int)
    parser.add_argument("--model-name", default="gpt-5.4-nano")
    parser.add_argument("--batch-size", type=int, default=16)
    parser.add_argument("--paraphraser-backend", choices=["openai", "heuristic"], default="openai")
    return parser.parse_args()


def main() -> int:
    args = _parse_args()
    request = SourceGenerationRequest(
        input_jsonl=args.input_jsonl,
        output_jsonl=args.output_jsonl,
        reject_log_jsonl=args.reject_log_jsonl,
        seed=args.seed,
        model_name=args.model_name,
        max_variants_per_graph=args.max_variants_per_graph,
        difficulty_bucket=args.difficulty_bucket,
        max_graphs=args.max_graphs,
        batch_size=args.batch_size,
        paraphraser_backend=args.paraphraser_backend,
    )
    result = generate_source_variants(request)
    sys.stdout.write(
        f"Built {len(result.accepted_records)} source variants -> {request.output_jsonl}"
        + (f" and {request.reject_log_jsonl}" if request.reject_log_jsonl is not None else "")
        + "\n"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
