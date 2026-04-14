from __future__ import annotations

from pathlib import Path
from typing import Any

from .io import write_json


def _fmt(value: float) -> str:
    return f"{value:.4f}"


def write_eval_summary_markdown(
    *,
    output_path: Path,
    run_metadata: dict[str, Any],
    set_metrics: dict[str, Any],
    bucket_metrics: dict[str, Any],
    release_gate_summary: dict[str, Any],
) -> None:
    sets = set_metrics.get("sets", {})
    if not isinstance(sets, dict):
        sets = {}
    buckets = bucket_metrics.get("buckets", {})
    if not isinstance(buckets, dict):
        buckets = {}

    lines = [
        "# Eval Summary",
        "",
        "## Run Metadata",
        f"- bundle_id: {run_metadata.get('bundle_id', '')}",
        f"- checkpoint_id: {run_metadata.get('checkpoint_id', '')}",
        f"- contract_version: {run_metadata.get('contract_version', '')}",
        f"- decoding_config: {run_metadata.get('decoding_snapshot_hash', '')}",
        f"- grammar_snapshot: {run_metadata.get('grammar_snapshot_hash', '')}",
        f"- normalization_snapshot: {run_metadata.get('normalization_snapshot_hash', '')}",
        f"- runtime_policy_snapshot: {run_metadata.get('runtime_policy_snapshot_hash', '')}",
        "",
        "## Set Metrics",
        "| Set | json_valid_rate | exact_marked_object_id_accuracy | ordinal_actor_binding_accuracy | target_resolution_accuracy | chronology_phase_accuracy | runtime_fallback_rate |",
        "| --- | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]
    for set_name in ("synthetic_heldout", "hard_heldout", "real_runtime"):
        metrics = sets.get(set_name, {}).get("metrics", {})
        if not isinstance(metrics, dict):
            metrics = {}
        lines.append(
            "| {set_name} | {jvr} | {exact} | {ordinal} | {target} | {chrono} | {fallback} |".format(
                set_name=set_name,
                jvr=_fmt(float(metrics.get("json_valid_rate", 0.0))),
                exact=_fmt(float(metrics.get("exact_marked_object_id_accuracy", 0.0))),
                ordinal=_fmt(float(metrics.get("ordinal_actor_binding_accuracy", 0.0))),
                target=_fmt(float(metrics.get("target_resolution_accuracy", 0.0)),
                ),
                chrono=_fmt(float(metrics.get("chronology_phase_accuracy", 0.0))),
                fallback=_fmt(float(metrics.get("runtime_fallback_rate", 0.0))),
            )
        )

    lines.extend(
        [
            "",
            "## Critical Buckets",
            "| Bucket | cases | exact_marked_object_id_accuracy | ordinal_actor_binding_accuracy | chronology_phase_accuracy | runtime_fallback_rate | delta_vs_baseline |",
            "| --- | ---: | ---: | ---: | ---: | ---: | ---: |",
        ]
    )
    bucket_deltas = release_gate_summary.get("bucket_deltas", {})
    if not isinstance(bucket_deltas, dict):
        bucket_deltas = {}
    for bucket_name in (
        "ordinal_cases",
        "marked_object_morphology",
        "same_type_markers",
        "unsupported_action_cases",
        "three_beat_cases",
        "exact_marker_identity_cases",
        "reviewed_merge_cases",
    ):
        payload = buckets.get(bucket_name, {})
        metrics = payload.get("metrics", {}) if isinstance(payload, dict) else {}
        if not isinstance(metrics, dict):
            metrics = {}
        cases = int(payload.get("case_count", 0) if isinstance(payload, dict) else 0)
        deltas = bucket_deltas.get(bucket_name, {})
        if not isinstance(deltas, dict):
            deltas = {}
        delta_hint = max((float(value) for value in deltas.values()), default=0.0)
        lines.append(
            "| {bucket} | {cases} | {exact} | {ordinal} | {chrono} | {fallback} | {delta:.3f} |".format(
                bucket=bucket_name,
                cases=cases,
                exact=_fmt(float(metrics.get("exact_marked_object_id_accuracy", 0.0))),
                ordinal=_fmt(float(metrics.get("ordinal_actor_binding_accuracy", 0.0))),
                chrono=_fmt(float(metrics.get("chronology_phase_accuracy", 0.0))),
                fallback=_fmt(float(metrics.get("runtime_fallback_rate", 0.0))),
                delta=delta_hint,
            )
        )

    lines.extend(
        [
            "",
            "## Release Gate",
            f"- status: {release_gate_summary.get('gate_status', '')}",
            f"- blockers: {', '.join(release_gate_summary.get('blocking_reasons', [])) if release_gate_summary.get('blocking_reasons') else 'none'}",
            f"- improvements: {', '.join(sorted(release_gate_summary.get('critical_deltas', {}).keys())) if isinstance(release_gate_summary.get('critical_deltas'), dict) else 'none'}",
            f"- recommended_action: {release_gate_summary.get('recommended_action', '')}",
            "",
            "## Top Failure Clusters",
        ]
    )
    for set_name in ("hard_heldout", "real_runtime"):
        top = sets.get(set_name, {}).get("top_failure_clusters", [])
        if not isinstance(top, list):
            top = []
        lines.append(f"- {set_name}: " + ", ".join(f"{item.get('cluster_id')} ({item.get('count')})" for item in top) if top else f"- {set_name}: none")

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_run_manifest(
    *,
    output_path: Path,
    run_metadata: dict[str, Any],
    contract_summary: dict[str, Any],
    set_metrics: dict[str, Any],
    bucket_metrics: dict[str, Any],
) -> None:
    payload = {
        "run_metadata": run_metadata,
        "contract_summary": contract_summary,
        "overall_metrics": set_metrics.get("overall", {}),
        "bucket_case_counts": {
            bucket_name: int(bucket_payload.get("case_count", 0))
            for bucket_name, bucket_payload in (bucket_metrics.get("buckets", {}) or {}).items()
            if isinstance(bucket_payload, dict)
        },
    }
    write_json(payload, output_path)
