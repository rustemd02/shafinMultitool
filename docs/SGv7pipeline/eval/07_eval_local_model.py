#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from eval import CompareReportsRequest, EvalScoreRequest, compare_reports, score_checkpoint
from eval.compare import CompareError
from eval.harness import EvalHarnessError


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Track 9 eval harness for SG v7 local model checkpoints.")
    parser.add_argument("--mode", choices=("score", "compare"), required=True)
    parser.add_argument("--output-dir", type=Path, required=True)

    # score mode
    parser.add_argument("--eval-bundle-dir", type=Path)
    parser.add_argument("--checkpoint-id")
    parser.add_argument("--seed", type=int)
    parser.add_argument("--model-path", type=Path)
    parser.add_argument("--predictions-jsonl", type=Path)
    parser.add_argument("--baseline-report", type=Path)

    # compare mode
    parser.add_argument("--candidate-report", type=Path)
    return parser.parse_args()


def _require_score_args(args: argparse.Namespace) -> None:
    missing: list[str] = []
    if args.eval_bundle_dir is None:
        missing.append("--eval-bundle-dir")
    if not args.checkpoint_id:
        missing.append("--checkpoint-id")
    if args.seed is None:
        missing.append("--seed")
    if missing:
        raise EvalHarnessError("score mode missing required args: " + ", ".join(missing))


def _require_compare_args(args: argparse.Namespace) -> None:
    missing: list[str] = []
    if args.candidate_report is None:
        missing.append("--candidate-report")
    if args.baseline_report is None:
        missing.append("--baseline-report")
    if missing:
        raise CompareError("compare mode missing required args: " + ", ".join(missing))


def main() -> int:
    args = _parse_args()
    try:
        if args.mode == "score":
            _require_score_args(args)
            result = score_checkpoint(
                EvalScoreRequest(
                    eval_bundle_dir=args.eval_bundle_dir,
                    checkpoint_id=str(args.checkpoint_id),
                    output_dir=args.output_dir,
                    seed=int(args.seed),
                    model_path=args.model_path,
                    predictions_jsonl=args.predictions_jsonl,
                    baseline_report_dir=args.baseline_report,
                )
            )
            sys.stdout.write(
                "Eval score completed: checkpoint={checkpoint} gate_status={status} output={output}\n".format(
                    checkpoint=result["run_metadata"]["checkpoint_id"],
                    status=result["release_gate_summary"]["gate_status"],
                    output=args.output_dir,
                )
            )
            return 0

        _require_compare_args(args)
        summary = compare_reports(
            CompareReportsRequest(
                candidate_report_dir=args.candidate_report,
                baseline_report_dir=args.baseline_report,
                output_dir=args.output_dir,
            )
        )
        sys.stdout.write(
            "Eval compare completed: wins_candidate={wins_candidate} wins_baseline={wins_baseline} output={output}\n".format(
                wins_candidate=summary["wins_candidate"],
                wins_baseline=summary["wins_baseline"],
                output=args.output_dir,
            )
        )
        return 0
    except (EvalHarnessError, CompareError, ValueError) as exc:
        sys.stderr.write(f"{exc}\n")
        message = str(exc).lower()
        if "contract drift" in message or "missing required" in message or "snapshot" in message:
            return 2
        if "inference" in message or "prediction" in message or "model" in message:
            return 3
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
