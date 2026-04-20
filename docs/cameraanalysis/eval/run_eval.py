#!/usr/bin/env python3
"""Run reproducible eval harness for Camera Analysis v1."""

from __future__ import annotations

import argparse
import random
from pathlib import Path
from typing import Any, Dict, List, Tuple

from adapters import CandidateDeterministicRunner, LegacyBaselineRunner
from compare import build_compare_report, render_markdown_summary
from eval_io import load_bundle, output_map_from_jsonl, write_json, write_jsonl
from scorer import score_model, validate_sequence_contract


BUILTIN_BASELINES = {"legacy_suggestion_engine", "legacy_baseline", "legacy"}
BUILTIN_CANDIDATES = {"camera_analysis_v1_core", "candidate_deterministic", "candidate"}


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Camera Analysis eval harness runner")
    parser.add_argument("--bundle", required=True, help="Path to eval bundle directory")
    parser.add_argument("--candidate", required=True, help="Candidate mode or outputs jsonl path")
    parser.add_argument("--baseline", required=True, help="Baseline mode or outputs jsonl path")
    parser.add_argument("--output", required=True, help="Report output directory")
    return parser.parse_args()


def _is_jsonl_path(value: str) -> bool:
    path = Path(value)
    return path.exists() and path.is_file() and path.suffix.lower() == ".jsonl"


def _generate_outputs_for_mode(mode_id: str, cases: List[Dict[str, Any]]) -> Dict[str, Dict[str, Any]]:
    if mode_id in BUILTIN_BASELINES:
        runner = LegacyBaselineRunner()
    elif mode_id in BUILTIN_CANDIDATES:
        runner = CandidateDeterministicRunner()
    else:
        raise ValueError(
            f"unknown mode '{mode_id}'. "
            "Use built-ins (legacy_suggestion_engine/camera_analysis_v1_core) or pass a .jsonl path."
        )

    outputs: Dict[str, Dict[str, Any]] = {}
    for case in sorted(cases, key=lambda item: item["eval_case_id"]):
        outputs[case["eval_case_id"]] = runner.run_case(case)
    return outputs


def _resolve_outputs(source: str, cases: List[Dict[str, Any]]) -> Tuple[str, Dict[str, Dict[str, Any]]]:
    if _is_jsonl_path(source):
        output_map = output_map_from_jsonl(Path(source))
        return Path(source).stem, output_map
    return source, _generate_outputs_for_mode(source, cases)


def _ordered_outputs_jsonl(mode_id: str, outputs: Dict[str, Dict[str, Any]]) -> List[Dict[str, Any]]:
    rows: List[Dict[str, Any]] = []
    for case_id in sorted(outputs.keys()):
        rows.append({"eval_case_id": case_id, "mode_id": mode_id, "output": outputs[case_id]})
    return rows


def _build_case_results(
    baseline_scores: Dict[str, Any],
    candidate_scores: Dict[str, Any],
    compare_report: Dict[str, Any],
) -> List[Dict[str, Any]]:
    baseline_case = {
        row["eval_case_id"]: row
        for row in baseline_scores.get("case_results", [])
        if isinstance(row, dict) and "eval_case_id" in row
    }
    candidate_case = {
        row["eval_case_id"]: row
        for row in candidate_scores.get("case_results", [])
        if isinstance(row, dict) and "eval_case_id" in row
    }
    winner_by_case = {
        row["eval_case_id"]: row.get("winner")
        for row in compare_report.get("case_deltas", [])
        if isinstance(row, dict) and "eval_case_id" in row
    }

    rows: List[Dict[str, Any]] = []
    for case_id in sorted(set(baseline_case.keys()) | set(candidate_case.keys())):
        rows.append(
            {
                "eval_case_id": case_id,
                "winner": winner_by_case.get(case_id, "tie"),
                "baseline_metrics": baseline_case.get(case_id, {}).get("metrics", {}),
                "candidate_metrics": candidate_case.get(case_id, {}).get("metrics", {}),
            }
        )
    return rows


def main() -> None:
    args = _parse_args()
    random.seed(0)
    bundle_dir = Path(args.bundle).resolve()
    output_dir = Path(args.output).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    bundle = load_bundle(bundle_dir)
    manifest = bundle["manifest"]
    cases = bundle["cases"]
    validate_sequence_contract(cases)

    baseline_id, baseline_outputs = _resolve_outputs(args.baseline, cases)
    candidate_id, candidate_outputs = _resolve_outputs(args.candidate, cases)

    baseline_scores = score_model(cases, baseline_outputs)
    candidate_scores = score_model(cases, candidate_outputs)

    compare_report = build_compare_report(
        bundle_id=str(manifest.get("bundle_id", "eval_bundle")),
        baseline_id=baseline_id,
        candidate_id=candidate_id,
        baseline_scores=baseline_scores,
        candidate_scores=candidate_scores,
        manifest=manifest,
    )

    case_results = _build_case_results(
        baseline_scores=baseline_scores,
        candidate_scores=candidate_scores,
        compare_report=compare_report,
    )

    set_metrics = {
        "bundle_id": manifest.get("bundle_id"),
        "baseline_id": baseline_id,
        "candidate_id": candidate_id,
        "baseline": baseline_scores.get("set_metrics", {}),
        "candidate": candidate_scores.get("set_metrics", {}),
    }
    bucket_metrics = {
        "bundle_id": manifest.get("bundle_id"),
        "baseline_id": baseline_id,
        "candidate_id": candidate_id,
        "baseline": baseline_scores.get("bucket_metrics", {}),
        "candidate": candidate_scores.get("bucket_metrics", {}),
    }

    write_jsonl(output_dir / "baseline_outputs.jsonl", _ordered_outputs_jsonl(baseline_id, baseline_outputs))
    write_jsonl(output_dir / "candidate_outputs.jsonl", _ordered_outputs_jsonl(candidate_id, candidate_outputs))
    write_jsonl(output_dir / "case_results.jsonl", case_results)
    write_json(output_dir / "set_metrics.json", set_metrics)
    write_json(output_dir / "bucket_metrics.json", bucket_metrics)
    write_json(output_dir / "compare_report.json", compare_report)

    summary_md = render_markdown_summary(
        bundle_id=str(manifest.get("bundle_id", "eval_bundle")),
        baseline_id=baseline_id,
        candidate_id=candidate_id,
        compare_report=compare_report,
    )
    (output_dir / "eval_summary.md").write_text(summary_md, encoding="utf-8")


if __name__ == "__main__":
    main()
