#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from v9.datasets import read_jsonl, write_jsonl
from v9.eval import summarize_event_slice_metrics
from v9.eval_artifacts import build_v9_eval_artifacts


def main() -> None:
    parser = argparse.ArgumentParser(description="Build v9 eval artifacts from event predictions")
    parser.add_argument("--eval-cases-jsonl", required=True, type=Path)
    parser.add_argument("--event-predictions-jsonl", required=True, type=Path)
    parser.add_argument("--output-event-case-results-jsonl", required=True, type=Path)
    parser.add_argument("--output-compiled-predictions-jsonl", required=True, type=Path)
    parser.add_argument("--output-summary-json", required=False, type=Path)
    args = parser.parse_args()

    eval_rows = read_jsonl(args.eval_cases_jsonl.expanduser())
    prediction_rows = read_jsonl(args.event_predictions_jsonl.expanduser())
    event_case_rows, compiled_rows = build_v9_eval_artifacts(
        eval_case_rows=eval_rows,
        prediction_rows=prediction_rows,
    )

    write_jsonl(event_case_rows, args.output_event_case_results_jsonl.expanduser())
    write_jsonl(compiled_rows, args.output_compiled_predictions_jsonl.expanduser())

    if args.output_summary_json:
        metrics = summarize_event_slice_metrics(event_case_rows)
        args.output_summary_json.expanduser().write_text(
            json.dumps(
                {
                    "slice": "local_event_raw",
                    "overall": metrics.get("overall", {}),
                    "structural": metrics.get("structural", {}),
                    "semantic": metrics.get("semantic", {}),
                    "degradation": metrics.get("degradation", {}),
                    "metrics": metrics,
                },
                ensure_ascii=False,
                indent=2,
            )
            + "\n",
            encoding="utf-8",
        )


if __name__ == "__main__":
    main()
