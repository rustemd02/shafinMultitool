from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any

from .bundle import EvalBundleError, load_eval_bundle
from .compare import CompareReportsRequest, compare_reports
from .contract import ContractDriftError, validate_contract
from .inference import InferenceError, InferenceRequest, run_inference
from .io import read_json, read_jsonl, write_json, write_jsonl
from .release_gate import ReleaseGateRequest, evaluate_release_gate
from .reporter import write_eval_summary_markdown, write_run_manifest
from .scorer import ScoreCasesRequest, score_cases


class EvalHarnessError(ValueError):
    """Raised when eval score execution cannot proceed."""


@dataclass(frozen=True)
class EvalScoreRequest:
    eval_bundle_dir: Path
    checkpoint_id: str
    output_dir: Path
    seed: int
    model_path: Path | None = None
    predictions_jsonl: Path | None = None
    baseline_report_dir: Path | None = None


def _merge_run_metadata(
    *,
    bundle_manifest: dict[str, Any],
    checkpoint_id: str,
    seed: int,
    contract_summary: dict[str, Any],
) -> dict[str, Any]:
    hashes = contract_summary.get("snapshot_hashes", {})
    if not isinstance(hashes, dict):
        hashes = {}
    return {
        "bundle_id": str(bundle_manifest.get("bundle_id", "")),
        "bundle_version": str(bundle_manifest.get("bundle_version", "")),
        "contract_version": str(bundle_manifest.get("contract_version", "")),
        "checkpoint_id": checkpoint_id,
        "seed": seed,
        "prompt_snapshot_hash": str(hashes.get("prompt_contract_snapshot.json", "")),
        "decoding_snapshot_hash": str(hashes.get("decoding_config_snapshot.json", "")),
        "grammar_snapshot_hash": str(hashes.get("grammar_constraint_snapshot.json", "")),
        "normalization_snapshot_hash": str(hashes.get("normalization_policy_snapshot.json", "")),
        "runtime_policy_snapshot_hash": str(hashes.get("runtime_policy_snapshot.json", "")),
    }


def _load_baseline_contract(baseline_report_dir: Path) -> dict[str, Any] | None:
    run_manifest_path = baseline_report_dir / "run_manifest.json"
    if not run_manifest_path.exists():
        return None
    payload = read_json(run_manifest_path)
    summary = payload.get("contract_summary")
    return summary if isinstance(summary, dict) else None


def score_checkpoint(request: EvalScoreRequest) -> dict[str, Any]:
    try:
        bundle = load_eval_bundle(request.eval_bundle_dir)
    except EvalBundleError as exc:
        raise EvalHarnessError(str(exc)) from exc

    try:
        contract_summary = validate_contract(bundle)
    except ContractDriftError as exc:
        raise EvalHarnessError(str(exc)) from exc

    runtime_policy_snapshot = contract_summary.get("snapshot_meta", {}).get("runtime_policy_snapshot.json", {})
    if not isinstance(runtime_policy_snapshot, dict):
        runtime_policy_snapshot = {}

    try:
        raw_outputs, predicted_by_case = run_inference(
            InferenceRequest(
                cases=bundle.cases,
                checkpoint_id=request.checkpoint_id,
                model_path=request.model_path,
                predictions_jsonl=request.predictions_jsonl,
                seed=request.seed,
            )
        )
    except InferenceError as exc:
        raise EvalHarnessError(str(exc)) from exc

    scored = score_cases(
        ScoreCasesRequest(
            checkpoint_id=request.checkpoint_id,
            cases=bundle.cases,
            predicted_by_case=predicted_by_case,
            runtime_policy_snapshot=runtime_policy_snapshot,
        )
    )

    run_metadata = _merge_run_metadata(
        bundle_manifest=bundle.manifest,
        checkpoint_id=request.checkpoint_id,
        seed=request.seed,
        contract_summary=contract_summary,
    )
    set_metrics_payload = dict(scored["set_metrics"])
    set_metrics_payload["run_metadata"] = run_metadata
    bucket_metrics_payload = dict(scored["bucket_metrics"])
    bucket_metrics_payload["run_metadata"] = run_metadata

    baseline_set_metrics = None
    baseline_bucket_metrics = None
    baseline_case_results = None
    baseline_contract = None
    if request.baseline_report_dir is not None:
        baseline_set_metrics = read_json(request.baseline_report_dir / "set_metrics.json")
        baseline_bucket_metrics = read_json(request.baseline_report_dir / "bucket_metrics.json")
        baseline_case_results = read_jsonl(request.baseline_report_dir / "case_results.jsonl")
        baseline_contract = _load_baseline_contract(request.baseline_report_dir)

    release_gate_summary = evaluate_release_gate(
        ReleaseGateRequest(
            candidate_set_metrics=set_metrics_payload,
            candidate_bucket_metrics=bucket_metrics_payload,
            candidate_case_results=scored["case_results"],
            candidate_contract=contract_summary,
            baseline_set_metrics=baseline_set_metrics,
            baseline_bucket_metrics=baseline_bucket_metrics,
            baseline_case_results=baseline_case_results,
            baseline_contract=baseline_contract,
        )
    )
    release_gate_summary["run_metadata"] = run_metadata

    request.output_dir.mkdir(parents=True, exist_ok=True)
    write_jsonl(raw_outputs, request.output_dir / "raw_outputs.jsonl")
    write_jsonl(scored["case_results"], request.output_dir / "case_results.jsonl")
    write_json(set_metrics_payload, request.output_dir / "set_metrics.json")
    write_json(bucket_metrics_payload, request.output_dir / "bucket_metrics.json")
    write_json(release_gate_summary, request.output_dir / "release_gate_summary.json")
    write_eval_summary_markdown(
        output_path=request.output_dir / "eval_summary.md",
        run_metadata=run_metadata,
        set_metrics=set_metrics_payload,
        bucket_metrics=bucket_metrics_payload,
        release_gate_summary=release_gate_summary,
    )
    write_run_manifest(
        output_path=request.output_dir / "run_manifest.json",
        run_metadata=run_metadata,
        contract_summary=contract_summary,
        set_metrics=set_metrics_payload,
        bucket_metrics=bucket_metrics_payload,
    )

    ab_summary = None
    if request.baseline_report_dir is not None:
        ab_summary = compare_reports(
            CompareReportsRequest(
                candidate_report_dir=request.output_dir,
                baseline_report_dir=request.baseline_report_dir,
                output_dir=request.output_dir,
            )
        )

    return {
        "run_metadata": run_metadata,
        "release_gate_summary": release_gate_summary,
        "ab_summary": ab_summary,
    }
