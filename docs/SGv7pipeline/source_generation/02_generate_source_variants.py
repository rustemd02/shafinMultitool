#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from source_generation import SourceGenerationRequest, generate_source_variants


def _log(stage: str, message: str) -> None:
    sys.stdout.write(f"[sgv7:source_generation] {stage}: {message}\n")
    sys.stdout.flush()


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
    parser.add_argument("--paraphraser-workers", type=int, default=1)
    parser.add_argument(
        "--disable-clean-fallback",
        action="store_true",
        help="Disable heuristic fallback for required clean variants when paraphraser backend is openai.",
    )
    return parser.parse_args()


def main() -> int:
    _log("stage 1/4", "parse args")
    args = _parse_args()
    _log(
        "stage 2/4",
        f"build request backend={args.paraphraser_backend} workers={max(1, args.paraphraser_workers)} batch_size={args.batch_size}",
    )
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
        paraphraser_workers=max(1, args.paraphraser_workers),
        enable_clean_fallback=not args.disable_clean_fallback,
    )
    _log("stage 3/4", "run source variant generation")
    result = generate_source_variants(request)
    _log("stage 4/4", f"write artifacts accepted={len(result.accepted_records)} rejected={len(result.reject_records)}")
    sys.stdout.write(
        f"Built {len(result.accepted_records)} source variants -> {request.output_jsonl}"
        + (f" and {request.reject_log_jsonl}" if request.reject_log_jsonl is not None else "")
        + "\n"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
