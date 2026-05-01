#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[3]


def _run(cmd: list[str]) -> None:
    completed = subprocess.run(cmd, check=False)
    if completed.returncode != 0:
        raise RuntimeError(f"Command failed ({completed.returncode}): {' '.join(cmd)}")


def _extract_eval_zip(zip_path: Path, export_dir: Path) -> None:
    export_dir.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(zip_path, "r") as zf:
        needed = [
            name
            for name in zf.namelist()
            if name.endswith(".plan_predictions.jsonl") or name.endswith("v8_plan_predictions_manifest_seed42.json")
        ]
        for name in needed:
            target = export_dir / Path(name).name
            with zf.open(name) as src, target.open("wb") as dst:
                shutil.copyfileobj(src, dst)


def _build_benchmark_config(
    *,
    repo_root: Path,
    run_root: Path,
    prep_root: Path,
    seed: int,
    eval_seed: int,
    config_path: Path,
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
                    prep_root
                    / "colab_prep_export_seed42/predictions_dualslice_seed42/dataset_v7_seed{seed}.jsonl"
                ),
            },
            {
                "id": "dataset_v7_orpo_iter1",
                "name": "Fine-tuned on generate_dataset_v7 + ORPO iter1",
                "predictions_path_template": str(
                    prep_root
                    / "colab_prep_export_seed42/predictions_dualslice_seed42/dataset_v7_orpo_iter1_seed{seed}.jsonl"
                ),
            },
            {
                "id": "dataset_v7_orpo_iter2",
                "name": "Fine-tuned on generate_dataset_v7 + ORPO iter2",
                "predictions_path_template": str(
                    prep_root
                    / "colab_prep_export_seed42/predictions_dualslice_seed42/dataset_v7_orpo_iter2_seed{seed}.jsonl"
                ),
            },
            {
                "id": "dataset_v8_plan_sft",
                "name": "V8 plan SFT",
                "predictions_path_template": str(
                    run_root / "eval_artifacts/dataset_v8_plan_sft_seed{seed}.compiled_predictions.jsonl"
                ),
                "v8_plan_case_results_path_template": str(
                    run_root / "eval_artifacts/dataset_v8_plan_sft_seed{seed}.plan_case_results.jsonl"
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
        ],
        "pairs": [
            ["dataset_v7_orpo_iter1", "dataset_v7"],
            ["dataset_v7_orpo_iter2", "dataset_v7"],
            ["dataset_v7_orpo_iter2", "dataset_v7_orpo_iter1"],
            ["dataset_v8_plan_sft", "dataset_v7"],
            ["dataset_v8_plan_sft", "dataset_v7_orpo_iter2"],
            ["dataset_v8_plan_orpo_iter1", "dataset_v7"],
            ["dataset_v8_plan_orpo_iter1", "dataset_v7_orpo_iter1"],
            ["dataset_v8_plan_orpo_iter1", "dataset_v7_orpo_iter2"],
            ["dataset_v8_plan_orpo_iter1", "dataset_v8_plan_sft"],
        ],
    }
    config_path.parent.mkdir(parents=True, exist_ok=True)
    config_path.write_text(json.dumps(cfg, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    repo_root = _repo_root()
    parser = argparse.ArgumentParser(description="Run local v8 benchmark from Colab export zip")
    parser.add_argument(
        "--run-root",
        type=Path,
        default=repo_root / "docs/SGv7pipeline/runs/v8_0_seed42",
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
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--eval-seed", type=int, default=20260421)
    parser.add_argument(
        "--zip-path",
        type=Path,
        default=None,
        help="Path to sgv8_eval_pack_seed42.zip (defaults to <run-root>/sgv8_eval_export_seed42/sgv8_eval_pack_seed42.zip)",
    )
    parser.add_argument("--colab-export-dir", type=Path, default=None)
    parser.add_argument("--eval-artifacts-dir", type=Path, default=None)
    parser.add_argument("--config-path", type=Path, default=None)
    parser.add_argument("--output-dir", type=Path, default=None)
    parser.add_argument(
        "--skip-unzip",
        action=argparse.BooleanOptionalAction,
        default=False,
        help="Skip extracting zip when plan_predictions jsonl files are already present",
    )
    parser.add_argument(
        "--clean-output",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Delete benchmark output dir before run",
    )
    args = parser.parse_args()

    run_root = args.run_root.expanduser().resolve()
    prep_root = args.prep_root.expanduser().resolve()
    eval_cases_jsonl = args.eval_cases_jsonl.expanduser().resolve()
    zip_path = (
        args.zip_path.expanduser().resolve()
        if args.zip_path
        else (run_root / "sgv8_eval_export_seed42/sgv8_eval_pack_seed42.zip").resolve()
    )
    colab_export_dir = (
        args.colab_export_dir.expanduser().resolve()
        if args.colab_export_dir
        else (run_root / "colab_export").resolve()
    )
    eval_artifacts_dir = (
        args.eval_artifacts_dir.expanduser().resolve()
        if args.eval_artifacts_dir
        else (run_root / "eval_artifacts").resolve()
    )
    config_path = (
        args.config_path.expanduser().resolve()
        if args.config_path
        else (run_root / "benchmark_config.v8.seed42.json").resolve()
    )
    output_dir = (
        args.output_dir.expanduser().resolve()
        if args.output_dir
        else (run_root / "benchmark_results_seed42").resolve()
    )

    if not eval_cases_jsonl.exists():
        raise FileNotFoundError(f"eval cases file missing: {eval_cases_jsonl}")
    if not prep_root.exists():
        raise FileNotFoundError(f"prep root missing: {prep_root}")

    if not args.skip_unzip:
        if not zip_path.exists():
            raise FileNotFoundError(f"zip file not found: {zip_path}")
        _extract_eval_zip(zip_path, colab_export_dir)

    sft_plan_pred = colab_export_dir / f"dataset_v8_plan_sft_seed{args.seed}.plan_predictions.jsonl"
    orpo_plan_pred = colab_export_dir / f"dataset_v8_plan_orpo_iter1_seed{args.seed}.plan_predictions.jsonl"
    for required_path in (sft_plan_pred, orpo_plan_pred):
        if not required_path.exists():
            raise FileNotFoundError(f"missing plan prediction file: {required_path}")

    eval_artifacts_dir.mkdir(parents=True, exist_ok=True)
    build_eval_cli = repo_root / "docs/SGv7pipeline/v8/06_build_v8_eval_artifacts.py"
    _run(
        [
            sys.executable,
            str(build_eval_cli),
            "--eval-cases-jsonl",
            str(eval_cases_jsonl),
            "--plan-predictions-jsonl",
            str(sft_plan_pred),
            "--output-plan-case-results-jsonl",
            str(eval_artifacts_dir / f"dataset_v8_plan_sft_seed{args.seed}.plan_case_results.jsonl"),
            "--output-compiled-predictions-jsonl",
            str(eval_artifacts_dir / f"dataset_v8_plan_sft_seed{args.seed}.compiled_predictions.jsonl"),
        ]
    )
    _run(
        [
            sys.executable,
            str(build_eval_cli),
            "--eval-cases-jsonl",
            str(eval_cases_jsonl),
            "--plan-predictions-jsonl",
            str(orpo_plan_pred),
            "--output-plan-case-results-jsonl",
            str(eval_artifacts_dir / f"dataset_v8_plan_orpo_iter1_seed{args.seed}.plan_case_results.jsonl"),
            "--output-compiled-predictions-jsonl",
            str(eval_artifacts_dir / f"dataset_v8_plan_orpo_iter1_seed{args.seed}.compiled_predictions.jsonl"),
        ]
    )

    _build_benchmark_config(
        repo_root=repo_root,
        run_root=run_root,
        prep_root=prep_root,
        seed=args.seed,
        eval_seed=args.eval_seed,
        config_path=config_path,
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

    print("v8 benchmark completed")
    print(f"- config: {config_path}")
    print(f"- output dir: {output_dir}")
    print(f"- runs scored: {output_dir / 'aggregate/runs_scored.csv'}")
    print(f"- pairwise: {output_dir / 'aggregate/pairwise_compare.csv'}")
    print(f"- slice summary: {output_dir / 'aggregate/model_slice_summary.csv'}")
    print(f"- v8 plan slice summary: {output_dir / 'aggregate/v8_plan_slice_summary.csv'}")
    print(f"- scientific report: {output_dir / 'aggregate/scientific_report.md'}")


if __name__ == "__main__":
    main()
