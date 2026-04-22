#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path

try:
    from .datasets import read_jsonl, write_jsonl
    from .eval_artifacts import stitch_eval_artifacts_builder
except ImportError:  # pragma: no cover
    from datasets import read_jsonl, write_jsonl
    from eval_artifacts import stitch_eval_artifacts_builder


def main() -> None:
    parser = argparse.ArgumentParser(description="Build V1 stitch/bundle eval artifacts")
    parser.add_argument("--eval-cases-jsonl", type=Path, required=True)
    parser.add_argument("--prediction-jsonl", type=Path, required=True)
    parser.add_argument("--output-chunk-case-results-jsonl", type=Path, required=True)
    parser.add_argument("--output-scene-case-results-jsonl", type=Path, required=True)
    parser.add_argument("--output-bundle-case-results-jsonl", type=Path, required=True)
    parser.add_argument("--output-compiled-predictions-jsonl", type=Path, required=True)
    args = parser.parse_args()

    eval_case_rows = read_jsonl(args.eval_cases_jsonl)
    prediction_rows = read_jsonl(args.prediction_jsonl)
    chunk_rows, scene_rows, bundle_rows, compiled_rows = stitch_eval_artifacts_builder(
        eval_case_rows=eval_case_rows,
        prediction_rows=prediction_rows,
    )

    write_jsonl(chunk_rows, args.output_chunk_case_results_jsonl)
    write_jsonl(scene_rows, args.output_scene_case_results_jsonl)
    write_jsonl(bundle_rows, args.output_bundle_case_results_jsonl)
    write_jsonl(compiled_rows, args.output_compiled_predictions_jsonl)


if __name__ == "__main__":
    main()

