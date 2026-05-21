from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[3]
DEFAULT_RUN_ROOT = REPO_ROOT / "docs/SGv9pipeline/runs/v9_3_seed42/from_user_predictions"
DEFAULT_PREDICTIONS = REPO_ROOT / "experiments/sc_benchmark/dataset_v9_3_event_sft_seed42.event_predictions.jsonl"
DEFAULT_EVAL_CASES = REPO_ROOT / "experiments/sc_benchmark/workspace/eval_bundle_v1/eval_cases.jsonl"
BASELINE_ROOT = REPO_ROOT / "docs/SGv9pipeline/runs/v9_0_seed42/eval_artifacts"
BASELINE_FILES = [
    "dataset_v8_plan_orpo_iter1_seed42.compiled_predictions.jsonl",
    "dataset_v8_plan_orpo_iter1_seed42.plan_case_results.jsonl",
    "dataset_v8_plan_orpo_iter1_seed42.plan_case_results.manifest.json",
]


def run(cmd: list[str], *, env: dict[str, str] | None = None) -> None:
    print("[v9.3-post-train]", " ".join(cmd))
    subprocess.run(cmd, cwd=REPO_ROOT, check=True, env=env)


def ensure_baseline(eval_artifacts_dir: Path) -> None:
    eval_artifacts_dir.mkdir(parents=True, exist_ok=True)
    for filename in BASELINE_FILES:
        src = BASELINE_ROOT / filename
        dst = eval_artifacts_dir / filename
        if dst.exists():
            continue
        if not src.exists():
            raise FileNotFoundError(f"Missing frozen V8 baseline artifact: {src}")
        shutil.copy2(src, dst)


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def evaluate_acceptance(metrics: dict[str, Any], args: argparse.Namespace) -> dict[str, Any]:
    checks = [
        ("case_strict_success_rate", ">=", args.min_case_strict_success),
        ("target_resolution_accuracy", ">=", args.min_target_resolution),
        ("chronology_phase_accuracy", ">=", args.min_chronology_phase),
        ("action_recall", ">=", args.min_action_recall),
        ("runtime_fallback_rate", "<=", args.max_runtime_fallback),
    ]
    results: list[dict[str, Any]] = []
    for metric_name, operator, threshold in checks:
        raw_value = metrics.get(metric_name)
        try:
            value = float(raw_value)
        except (TypeError, ValueError):
            passed = False
            value = None
        else:
            passed = value >= threshold if operator == ">=" else value <= threshold
        results.append(
            {
                "metric": metric_name,
                "value": value,
                "operator": operator,
                "threshold": threshold,
                "pass": passed,
            }
        )
    return {
        "pass": all(row["pass"] for row in results),
        "checks": results,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Run V9.3 post-training benchmark, mining and demo parity.")
    parser.add_argument("--predictions", type=Path, default=DEFAULT_PREDICTIONS)
    parser.add_argument("--run-root", type=Path, default=DEFAULT_RUN_ROOT)
    parser.add_argument("--model-id", default="dataset_v9_3_event_sft")
    parser.add_argument("--model-name", default="V9.3 slot-event SFT")
    parser.add_argument("--skip-demo-parity", action="store_true")
    parser.add_argument("--min-case-strict-success", type=float, default=0.65)
    parser.add_argument("--min-target-resolution", type=float, default=0.99)
    parser.add_argument("--min-chronology-phase", type=float, default=0.985)
    parser.add_argument("--min-action-recall", type=float, default=0.99)
    parser.add_argument("--max-runtime-fallback", type=float, default=0.25)
    args = parser.parse_args()

    predictions = args.predictions.resolve()
    run_root = args.run_root.resolve()
    if not predictions.exists():
        raise FileNotFoundError(
            f"Predictions file not found: {predictions}\n"
            "Put Colab output there first, or pass --predictions /path/to/dataset_v9_3_event_sft_seed42.event_predictions.jsonl"
        )

    eval_artifacts_dir = run_root / "eval_artifacts"
    ensure_baseline(eval_artifacts_dir)

    env = dict(**__import__("os").environ)
    env["PYTHONPATH"] = f"{REPO_ROOT / 'docs/SGv7pipeline'}:{REPO_ROOT / 'docs/SGv8pipeline'}"

    run(
        [
            sys.executable,
            "docs/SGv9pipeline/v9/04_run_v9_local_benchmark.py",
            "--run-root",
            str(run_root),
            "--event-predictions-jsonl",
            str(predictions),
            "--model-id",
            args.model_id,
            "--model-name",
            args.model_name,
        ],
        env=env,
    )

    event_results = eval_artifacts_dir / f"{args.model_id}_seed42.event_case_results.jsonl"
    compiled_predictions = eval_artifacts_dir / f"{args.model_id}_seed42.compiled_predictions.jsonl"
    if not event_results.exists():
        raise FileNotFoundError(f"Benchmark did not produce event case results: {event_results}")
    if not compiled_predictions.exists():
        raise FileNotFoundError(f"Benchmark did not produce compiled predictions: {compiled_predictions}")

    run(
        [
            sys.executable,
            "docs/SGv9pipeline/v9/05_mine_v9_hard_cases.py",
            "--eval-cases",
            str(DEFAULT_EVAL_CASES),
            "--event-case-results",
            str(event_results),
            "--output-dir",
            str(run_root / "post_benchmark_failure_mining"),
            "--max-per-cluster",
            "80",
        ]
    )

    parity_status = "skipped"
    if not args.skip_demo_parity:
        parity_cmd = [
            sys.executable,
            "docs/SGv9pipeline/v9/12_validate_v9_demo_parity.py",
            "--compiled-predictions",
            str(compiled_predictions),
            "--output-dir",
            str(run_root / "demo_parity_validation"),
        ]
        try:
            run(parity_cmd)
            parity_status = "passed"
        except subprocess.CalledProcessError:
            parity_status = "failed"

    summary_path = run_root / "v9_3_post_train_eval_summary.json"
    report_path = run_root / "benchmark_results_seed42/aggregate/scientific_report.md"
    set_metrics_path = run_root / f"benchmark_results_seed42/reports/{args.model_id}/seed_42/set_metrics.json"
    mining_manifest = run_root / "post_benchmark_failure_mining/v9_hard_case_manifest.json"
    parity_results = run_root / "demo_parity_validation/demo_parity_results.json"
    set_metrics = read_json(set_metrics_path) if set_metrics_path.exists() else {}
    overall_metrics = (set_metrics.get("overall") or {}).get("metrics") if isinstance(set_metrics.get("overall"), dict) else {}
    if not isinstance(overall_metrics, dict):
        overall_metrics = {}
    acceptance = evaluate_acceptance(overall_metrics, args)
    summary = {
        "predictions": str(predictions),
        "run_root": str(run_root),
        "model_id": args.model_id,
        "scientific_report": str(report_path),
        "set_metrics": str(set_metrics_path),
        "acceptance": acceptance,
        "failure_mining_manifest": str(mining_manifest),
        "demo_parity_status": parity_status,
        "demo_parity_results": str(parity_results) if parity_results.exists() else None,
        "failure_mining": read_json(mining_manifest) if mining_manifest.exists() else None,
        "demo_parity": read_json(parity_results) if parity_results.exists() else None,
    }
    summary_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    if not acceptance["pass"]:
        raise SystemExit(1)
    if parity_status == "failed":
        raise SystemExit(1)


if __name__ == "__main__":
    main()
