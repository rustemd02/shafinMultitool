#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from training import Iter3ReleaseGateError, Iter3ReleaseGateRequest, evaluate_iter3_release_gate


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Evaluate iter3 release gate against benchmark aggregates and corpus diagnostics.")
    parser.add_argument("--runs-scored-csv", type=Path, required=True)
    parser.add_argument("--model-slice-summary-csv", type=Path, required=True)
    parser.add_argument("--iter3-manifest-json", type=Path, required=True)
    parser.add_argument("--candidate-model-only-case-results-jsonl", type=Path, required=True)
    parser.add_argument("--baseline-model-only-case-results-jsonl", type=Path, required=True)
    parser.add_argument("--candidate-model-id", required=True)
    parser.add_argument("--baseline-model-id", default="dataset_v7_orpo_iter2")
    parser.add_argument("--seed", type=int)
    parser.add_argument("--manual-review-json", type=Path)
    parser.add_argument("--output-dir", type=Path, required=True)
    return parser.parse_args()


def main() -> int:
    args = _parse_args()
    try:
        result = evaluate_iter3_release_gate(
            Iter3ReleaseGateRequest(
                runs_scored_csv=args.runs_scored_csv,
                model_slice_summary_csv=args.model_slice_summary_csv,
                iter3_manifest_json=args.iter3_manifest_json,
                candidate_model_only_case_results_jsonl=args.candidate_model_only_case_results_jsonl,
                baseline_model_only_case_results_jsonl=args.baseline_model_only_case_results_jsonl,
                candidate_model_id=args.candidate_model_id,
                baseline_model_id=args.baseline_model_id,
                seed=args.seed,
                manual_review_json=args.manual_review_json,
                output_dir=args.output_dir,
            )
        )
    except (Iter3ReleaseGateError, ValueError) as exc:
        sys.stderr.write(f"Iter3 release gate failed: {exc}\n")
        return 2

    sys.stdout.write(
        f"Evaluated iter3 release gate: candidate={args.candidate_model_id} status={result['gate_status']} output={args.output_dir}\n"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
