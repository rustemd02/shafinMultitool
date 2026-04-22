#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path

try:
    from .datasets import chunk_preference_builder, read_jsonl, split_rows_by_document, write_jsonl
except ImportError:  # pragma: no cover
    from datasets import chunk_preference_builder, read_jsonl, split_rows_by_document, write_jsonl


def _score_map(rows: list[dict]) -> dict[tuple[str, str, str], float]:
    mapping: dict[tuple[str, str, str], float] = {}
    for row in rows:
        key = (
            str(row.get("document_id") or ""),
            str(row.get("scene_id") or ""),
            str(row.get("chunk_id") or ""),
        )
        if all(key):
            mapping[key] = float(row.get("score", 0.0) or 0.0)
    return mapping


def main() -> None:
    parser = argparse.ArgumentParser(description="Build V1 chunk preference dataset")
    parser.add_argument("--candidate-jsonl", type=Path, required=True)
    parser.add_argument("--baseline-jsonl", type=Path, required=True)
    parser.add_argument("--candidate-scores-jsonl", type=Path, default=None)
    parser.add_argument("--baseline-scores-jsonl", type=Path, default=None)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--val-fraction", type=float, default=0.1)
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    candidate_rows = read_jsonl(args.candidate_jsonl)
    baseline_rows = read_jsonl(args.baseline_jsonl)
    candidate_scores = _score_map(read_jsonl(args.candidate_scores_jsonl)) if args.candidate_scores_jsonl else None
    baseline_scores = _score_map(read_jsonl(args.baseline_scores_jsonl)) if args.baseline_scores_jsonl else None

    preference_rows = chunk_preference_builder(
        candidate_rows,
        baseline_rows,
        candidate_scores=candidate_scores,
        baseline_scores=baseline_scores,
    )
    train_rows, val_rows = split_rows_by_document(
        preference_rows,
        val_fraction=args.val_fraction,
        seed=args.seed,
    )

    args.output_dir.mkdir(parents=True, exist_ok=True)
    write_jsonl(train_rows, args.output_dir / "v1_chunk_preference_train.jsonl")
    write_jsonl(val_rows, args.output_dir / "v1_chunk_preference_val.jsonl")


if __name__ == "__main__":
    main()

