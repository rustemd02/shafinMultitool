#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import json
import shutil
import subprocess
import sys
from pathlib import Path

try:
    from .datasets import read_jsonl
    from .eval_artifacts import summarize_v1_eval_rows
except ImportError:  # pragma: no cover
    from datasets import read_jsonl
    from eval_artifacts import summarize_v1_eval_rows


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[3]


def _run(cmd: list[str]) -> None:
    completed = subprocess.run(cmd, check=False)
    if completed.returncode != 0:
        raise RuntimeError(f"Command failed ({completed.returncode}): {' '.join(cmd)}")


def _write_csv(rows: list[dict[str, object]], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if not rows:
        path.write_text("", encoding="utf-8")
        return
    fieldnames = list(rows[0].keys())
    with path.open("w", encoding="utf-8", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def _build_benchmark_config(
    *,
    repo_root: Path,
    run_root: Path,
    prep_root: Path,
    seed: int,
    eval_seed: int,
    config_path: Path,
    model_id: str,
) -> None:
    cfg = {
        "eval_bundle_dir": str(repo_root / "experiments/sc_benchmark/workspace/eval_bundle_v1"),
        "eval_seed": eval_seed,
        "seeds": [seed],
        "checkpoint_id_template": "{model_id}_seed{seed}",
        "slice_gate_baseline_model_id": "dataset_v7_orpo_iter2",
        "models": [
            {
                "id": "dataset_v7",
                "name": "Fine-tuned on generate_dataset_v7",
                "predictions_path_template": str(
                    prep_root / "colab_prep_export_seed42/predictions_dualslice_seed42/dataset_v7_seed{seed}.jsonl"
                ),
            },
            {
                "id": "dataset_v7_orpo_iter2",
                "name": "Fine-tuned on generate_dataset_v7 + ORPO iter2",
                "predictions_path_template": str(
                    prep_root / "colab_prep_export_seed42/predictions_dualslice_seed42/dataset_v7_orpo_iter2_seed{seed}.jsonl"
                ),
            },
            {
                "id": model_id,
                "name": "V1 chunk-native bundle pipeline",
                "predictions_path_template": str(
                    run_root / f"eval_artifacts/{model_id}_seed{{seed}}.compiled_predictions.jsonl"
                ),
            },
        ],
        "pairs": [
            [model_id, "dataset_v7"],
            [model_id, "dataset_v7_orpo_iter2"],
        ],
    }
    config_path.parent.mkdir(parents=True, exist_ok=True)
    config_path.write_text(json.dumps(cfg, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    repo_root = _repo_root()
    parser = argparse.ArgumentParser(description="Run V1 local benchmark from bundle predictions")
    parser.add_argument("--run-root", type=Path, required=True)
    parser.add_argument("--prediction-jsonl", type=Path, required=True)
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
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--eval-seed", type=int, default=20260421)
    parser.add_argument("--model-id", type=str, default="dataset_v1_bundle")
    parser.add_argument("--clean-output", action=argparse.BooleanOptionalAction, default=True)
    args = parser.parse_args()

    run_root = args.run_root.expanduser().resolve()
    run_root.mkdir(parents=True, exist_ok=True)
    eval_artifacts_dir = run_root / "eval_artifacts"
    eval_artifacts_dir.mkdir(parents=True, exist_ok=True)
    config_path = run_root / f"benchmark_config.{args.model_id}.seed{args.seed}.json"
    output_dir = run_root / f"benchmark_results_seed{args.seed}"

    build_cli = repo_root / "docs/SGv7pipeline/v1/03_build_v1_eval_artifacts.py"
    _run(
        [
            sys.executable,
            str(build_cli),
            "--eval-cases-jsonl",
            str(args.eval_cases_jsonl),
            "--prediction-jsonl",
            str(args.prediction_jsonl),
            "--output-chunk-case-results-jsonl",
            str(eval_artifacts_dir / f"{args.model_id}_seed{args.seed}.chunk_case_results.jsonl"),
            "--output-scene-case-results-jsonl",
            str(eval_artifacts_dir / f"{args.model_id}_seed{args.seed}.scene_case_results.jsonl"),
            "--output-bundle-case-results-jsonl",
            str(eval_artifacts_dir / f"{args.model_id}_seed{args.seed}.bundle_case_results.jsonl"),
            "--output-compiled-predictions-jsonl",
            str(eval_artifacts_dir / f"{args.model_id}_seed{args.seed}.compiled_predictions.jsonl"),
        ]
    )

    _build_benchmark_config(
        repo_root=repo_root,
        run_root=run_root,
        prep_root=args.prep_root.expanduser().resolve(),
        seed=args.seed,
        eval_seed=args.eval_seed,
        config_path=config_path,
        model_id=args.model_id,
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

    chunk_rows = read_jsonl(eval_artifacts_dir / f"{args.model_id}_seed{args.seed}.chunk_case_results.jsonl")
    scene_rows = read_jsonl(eval_artifacts_dir / f"{args.model_id}_seed{args.seed}.scene_case_results.jsonl")
    bundle_rows = read_jsonl(eval_artifacts_dir / f"{args.model_id}_seed{args.seed}.bundle_case_results.jsonl")
    aggregate_dir = output_dir / "aggregate"
    aggregate_dir.mkdir(parents=True, exist_ok=True)

    _write_csv(
        [
            summarize_v1_eval_rows(
                chunk_rows,
                model_id=args.model_id,
                metric_keys=[
                    "chunk_parse_ok",
                    "chunk_schema_valid",
                    "speaker_attribution_support",
                    "phase_signal_support",
                    "cross_chunk_pronoun_support",
                ],
            )
        ],
        aggregate_dir / "v1_chunk_slice_summary.csv",
    )
    _write_csv(
        [
            summarize_v1_eval_rows(
                scene_rows,
                model_id=args.model_id,
                metric_keys=["stitch_success", "compile_ok", "chunk_count"],
            )
        ],
        aggregate_dir / "v1_scene_stitch_summary.csv",
    )
    _write_csv(
        [
            summarize_v1_eval_rows(
                bundle_rows,
                model_id=args.model_id,
                metric_keys=["bundle_json_valid", "scene_count_accuracy", "chunk_parse_rate", "stitch_success_rate"],
            )
        ],
        aggregate_dir / "v1_bundle_summary.csv",
    )


if __name__ == "__main__":
    main()

