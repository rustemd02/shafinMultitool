#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import json
import shutil
import subprocess
import sys
from math import isnan
from pathlib import Path


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[3]


def _run(cmd: list[str]) -> None:
    completed = subprocess.run(cmd, check=False)
    if completed.returncode != 0:
        raise RuntimeError(f"Command failed ({completed.returncode}): {' '.join(cmd)}")


def _parse_float(value: str | None) -> float | None:
    if value is None:
        return None
    text = str(value).strip()
    if not text:
        return None
    try:
        parsed = float(text)
    except ValueError:
        return None
    if isnan(parsed):
        return None
    return parsed


def _build_live_vs_offline_gap_report(
    *,
    model_slice_summary_csv: Path,
    output_path: Path,
    model_id: str,
) -> None:
    if not model_slice_summary_csv.exists():
        output_path.write_text(
            json.dumps(
                {
                    "status": "skipped",
                    "reason": "model_slice_summary_missing",
                    "model_id": model_id,
                    "source": str(model_slice_summary_csv),
                },
                ensure_ascii=False,
                indent=2,
            )
            + "\n",
            encoding="utf-8",
        )
        return

    with model_slice_summary_csv.open("r", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        rows = [row for row in reader if str(row.get("model_id") or "").strip() == model_id]

    model_only_row: dict[str, str] | None = None
    end_to_end_row: dict[str, str] | None = None
    for row in rows:
        slice_name = str(row.get("slice") or "").strip()
        if slice_name == "model_only":
            model_only_row = row
        elif slice_name == "end_to_end":
            end_to_end_row = row

    if not model_only_row or not end_to_end_row:
        output_path.write_text(
            json.dumps(
                {
                    "status": "skipped",
                    "reason": "required_slices_missing",
                    "model_id": model_id,
                    "available_slices": sorted({str(row.get("slice") or "").strip() for row in rows}),
                },
                ensure_ascii=False,
                indent=2,
            )
            + "\n",
            encoding="utf-8",
        )
        return

    deltas: dict[str, float] = {}
    for key, model_only_value in model_only_row.items():
        if key in {"model_id", "seed", "case_results_jsonl", "checkpoint_id", "slice", "predictions_jsonl"}:
            continue
        lhs = _parse_float(end_to_end_row.get(key))
        rhs = _parse_float(model_only_value)
        if lhs is None or rhs is None:
            continue
        deltas[key] = lhs - rhs

    report = {
        "status": "ok",
        "model_id": model_id,
        "slices": {
            "live": "end_to_end",
            "offline": "model_only",
        },
        "delta_definition": "live_minus_offline",
        "per_metric_delta": deltas,
    }
    output_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def _build_benchmark_config(
    *,
    repo_root: Path,
    run_root: Path,
    prep_root: Path,
    seed: int,
    eval_seed: int,
    config_path: Path,
    compiled_prediction_name: str,
    event_case_name: str,
) -> None:
    cfg = {
        "eval_bundle_dir": str(repo_root / "experiments/sc_benchmark/workspace/eval_bundle_v1"),
        "eval_seed": eval_seed,
        "seeds": [seed],
        "checkpoint_id_template": "{model_id}_seed{seed}",
        "slice_gate_baseline_model_id": "dataset_v8_plan_orpo_iter1",
        "models": [
            {
                "id": "dataset_v7_orpo_iter2",
                "name": "Fine-tuned on generate_dataset_v7 + ORPO iter2",
                "predictions_path_template": str(
                    prep_root / "colab_prep_export_seed42/predictions_dualslice_seed42/dataset_v7_orpo_iter2_seed{seed}.jsonl"
                ),
            },
            {
                "id": "dataset_v8_plan_orpo_iter1",
                "name": "V8 plan SFT + ORPO iter1",
                "predictions_path_template": str(
                    run_root / "eval_artifacts/dataset_v8_plan_orpo_iter1_seed{seed}.compiled_predictions.jsonl"
                ),
                "v8_plan_case_results_path_template": str(
                    run_root / "eval_artifacts/dataset_v8_plan_orpo_iter1_seed{seed}.plan_case_results.jsonl"
                ),
            },
            {
                "id": "dataset_v9_event_sft",
                "name": "V9 slot-event SFT",
                "predictions_path_template": str(run_root / f"eval_artifacts/{compiled_prediction_name}"),
                "v8_plan_case_results_path_template": str(run_root / f"eval_artifacts/{event_case_name}"),
            },
        ],
        "pairs": [
            ["dataset_v8_plan_orpo_iter1", "dataset_v7_orpo_iter2"],
            ["dataset_v9_event_sft", "dataset_v8_plan_orpo_iter1"],
            ["dataset_v9_event_sft", "dataset_v7_orpo_iter2"],
        ],
    }
    config_path.parent.mkdir(parents=True, exist_ok=True)
    config_path.write_text(json.dumps(cfg, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    repo_root = _repo_root()
    parser = argparse.ArgumentParser(description="Run local v9 benchmark from event-table predictions")
    parser.add_argument(
        "--run-root",
        type=Path,
        default=repo_root / "docs/SGv9pipeline/runs/v9_0_seed42",
    )
    parser.add_argument(
        "--prep-root",
        type=Path,
        default=repo_root / "docs/SGv7pipeline/runs/sgv7_full_20260417/iter3_1_prep_seed42",
    )
    parser.add_argument(
        "--eval-cases-jsonl",
        type=Path,
        default=repo_root / "experiments/sc_benchmark/workspace/eval_bundle_v1/eval_cases.jsonl",
    )
    parser.add_argument("--event-predictions-jsonl", required=True, type=Path)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--eval-seed", type=int, default=20260430)
    parser.add_argument("--clean-output", action=argparse.BooleanOptionalAction, default=True)
    args = parser.parse_args()

    run_root = args.run_root.expanduser().resolve()
    prep_root = args.prep_root.expanduser().resolve()
    eval_cases_jsonl = args.eval_cases_jsonl.expanduser().resolve()
    event_predictions_jsonl = args.event_predictions_jsonl.expanduser().resolve()
    eval_artifacts_dir = run_root / "eval_artifacts"
    output_dir = run_root / "benchmark_results_seed42"
    config_path = run_root / "benchmark_config.v9.seed42.json"

    eval_artifacts_dir.mkdir(parents=True, exist_ok=True)
    event_case_name = f"dataset_v9_event_sft_seed{args.seed}.event_case_results.jsonl"
    compiled_name = f"dataset_v9_event_sft_seed{args.seed}.compiled_predictions.jsonl"
    summary_name = f"dataset_v9_event_sft_seed{args.seed}.event_slice_summary.json"

    build_cli = repo_root / "docs/SGv9pipeline/v9/03_build_v9_eval_artifacts.py"
    _run(
        [
            sys.executable,
            str(build_cli),
            "--eval-cases-jsonl",
            str(eval_cases_jsonl),
            "--event-predictions-jsonl",
            str(event_predictions_jsonl),
            "--output-event-case-results-jsonl",
            str(eval_artifacts_dir / event_case_name),
            "--output-compiled-predictions-jsonl",
            str(eval_artifacts_dir / compiled_name),
            "--output-summary-json",
            str(eval_artifacts_dir / summary_name),
        ]
    )

    _build_benchmark_config(
        repo_root=repo_root,
        run_root=run_root,
        prep_root=prep_root,
        seed=args.seed,
        eval_seed=args.eval_seed,
        config_path=config_path,
        compiled_prediction_name=compiled_name,
        event_case_name=event_case_name,
    )

    if args.clean_output and output_dir.exists():
        shutil.rmtree(output_dir)

    benchmark_cli = repo_root / "experiments/sc_benchmark/run_scientific_benchmark.py"
    _run(
        [
            sys.executable,
            str(benchmark_cli),
            "--config",
            str(config_path),
            "--output-dir",
            str(output_dir),
            "--mode",
            "full",
        ]
    )

    live_vs_offline_gap_report = eval_artifacts_dir / f"dataset_v9_event_sft_seed{args.seed}.live_vs_offline_gap.json"
    _build_live_vs_offline_gap_report(
        model_slice_summary_csv=output_dir / "aggregate/model_slice_summary.csv",
        output_path=live_vs_offline_gap_report,
        model_id="dataset_v9_event_sft",
    )

    print("v9 benchmark completed")
    print(f"- config: {config_path}")
    print(f"- output dir: {output_dir}")
    print(f"- runs scored: {output_dir / 'aggregate/runs_scored.csv'}")
    print(f"- pairwise: {output_dir / 'aggregate/pairwise_compare.csv'}")
    print(f"- slice summary: {output_dir / 'aggregate/model_slice_summary.csv'}")
    print(f"- scientific report: {output_dir / 'aggregate/scientific_report.md'}")
    print(f"- live-vs-offline gap: {live_vs_offline_gap_report}")


if __name__ == "__main__":
    main()
