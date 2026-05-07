#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path

from datasets import read_jsonl, write_jsonl
from eval_artifacts import build_v8_eval_artifacts


def main() -> None:
    parser = argparse.ArgumentParser(description="Build v8 plan case-results and compiled SceneScript predictions")
    parser.add_argument("--eval-cases-jsonl", required=True, type=Path)
    parser.add_argument("--plan-predictions-jsonl", required=True, type=Path)
    parser.add_argument("--output-plan-case-results-jsonl", required=True, type=Path)
    parser.add_argument("--output-compiled-predictions-jsonl", required=True, type=Path)
    args = parser.parse_args()

    plan_case_rows, compiled_prediction_rows = build_v8_eval_artifacts(
        eval_case_rows=read_jsonl(args.eval_cases_jsonl.expanduser()),
        prediction_rows=read_jsonl(args.plan_predictions_jsonl.expanduser()),
    )

    write_jsonl(plan_case_rows, args.output_plan_case_results_jsonl.expanduser())
    write_jsonl(compiled_prediction_rows, args.output_compiled_predictions_jsonl.expanduser())

    manifest = {
        "contract_version": "sg_v8_eval_artifacts_v1",
        "total_rows": len(plan_case_rows),
        "plan_parse_ok_rows": sum(1 for row in plan_case_rows if row["plan_parse_ok"]),
        "plan_compile_ok_rows": sum(1 for row in plan_case_rows if row["plan_compile_ok"]),
    }
    manifest_path = args.output_plan_case_results_jsonl.expanduser().with_suffix(".manifest.json")
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {args.output_plan_case_results_jsonl.expanduser()}")
    print(f"Wrote {args.output_compiled_predictions_jsonl.expanduser()}")
    print(f"Wrote {manifest_path}")


if __name__ == "__main__":
    main()
