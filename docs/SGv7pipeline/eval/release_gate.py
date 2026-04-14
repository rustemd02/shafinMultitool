from __future__ import annotations

from dataclasses import dataclass
from typing import Any


class ReleaseGateError(ValueError):
    """Raised when release gate inputs are malformed."""


CORE_METRICS = [
    "json_valid_rate",
    "marked_object_recall",
    "exact_marked_object_id_accuracy",
    "beat_count_accuracy",
    "action_recall",
    "described_action_precision",
    "dangling_target_rate",
    "ordinal_actor_binding_accuracy",
    "target_resolution_accuracy",
    "chronology_phase_accuracy",
    "llm_accept_rate",
    "llm_merge_rate",
    "llm_reject_rate",
    "runtime_fallback_rate",
]

LOWER_IS_BETTER = {"dangling_target_rate", "llm_merge_rate", "llm_reject_rate"}

CRITICAL_BUCKETS = [
    "ordinal_cases",
    "marked_object_morphology",
    "same_type_markers",
    "unsupported_action_cases",
    "three_beat_cases",
    "exact_marker_identity_cases",
    "reviewed_merge_cases",
]

GATE2_METRIC_SET = [
    "exact_marked_object_id_accuracy",
    "ordinal_actor_binding_accuracy",
    "target_resolution_accuracy",
    "chronology_phase_accuracy",
    "runtime_fallback_rate",
    "dangling_target_rate",
]

GATE1_FLOORS = {
    "json_valid_rate": 0.95,
    "marked_object_recall": 0.90,
    "exact_marked_object_id_accuracy": 0.90,
    "beat_count_accuracy": 0.85,
    "action_recall": 0.85,
    "described_action_precision": 0.85,
    "ordinal_actor_binding_accuracy": 0.90,
    "target_resolution_accuracy": 0.90,
    "chronology_phase_accuracy": 0.85,
}


@dataclass(frozen=True)
class ReleaseGateRequest:
    candidate_set_metrics: dict[str, Any]
    candidate_bucket_metrics: dict[str, Any]
    candidate_case_results: list[dict[str, Any]]
    candidate_contract: dict[str, Any]
    baseline_set_metrics: dict[str, Any] | None = None
    baseline_bucket_metrics: dict[str, Any] | None = None
    baseline_case_results: list[dict[str, Any]] | None = None
    baseline_contract: dict[str, Any] | None = None


def _metrics(payload: dict[str, Any], *, set_name: str = "overall") -> dict[str, Any]:
    sets = payload.get("sets", {})
    if set_name == "overall":
        container = payload.get("overall", {})
    else:
        if not isinstance(sets, dict):
            raise ReleaseGateError("set_metrics.sets must be object")
        container = sets.get(set_name, {})
    if not isinstance(container, dict):
        raise ReleaseGateError(f"set_metrics.{set_name} must be object")
    metrics = container.get("metrics", {})
    if not isinstance(metrics, dict):
        raise ReleaseGateError(f"set_metrics.{set_name}.metrics must be object")
    return metrics


def _bucket(payload: dict[str, Any], bucket_name: str) -> dict[str, Any]:
    buckets = payload.get("buckets", {})
    if not isinstance(buckets, dict):
        raise ReleaseGateError("bucket_metrics.buckets must be object")
    bucket = buckets.get(bucket_name, {})
    if not isinstance(bucket, dict):
        raise ReleaseGateError(f"bucket_metrics.buckets.{bucket_name} must be object")
    metrics = bucket.get("metrics", {})
    if not isinstance(metrics, dict):
        raise ReleaseGateError(f"bucket_metrics.buckets.{bucket_name}.metrics must be object")
    return bucket


def _cluster_counts(case_results: list[dict[str, Any]], eval_set: str) -> dict[str, int]:
    counts: dict[str, int] = {}
    for row in case_results:
        if str(row.get("eval_set", "")) != eval_set:
            continue
        cluster = row.get("failure_cluster", {})
        cluster_id = ""
        if isinstance(cluster, dict):
            cluster_id = str(cluster.get("cluster_id", "")).strip()
        if not cluster_id:
            continue
        counts[cluster_id] = counts.get(cluster_id, 0) + 1
    return counts


def _top3(case_results: list[dict[str, Any]], eval_set: str) -> dict[str, int]:
    counts = _cluster_counts(case_results, eval_set)
    ordered = sorted(counts.items(), key=lambda item: (-item[1], item[0]))
    return {cluster_id: count for cluster_id, count in ordered[:3]}


def _bucket_failed_cases(case_results: list[dict[str, Any]], bucket_name: str) -> int:
    failed = 0
    for row in case_results:
        tags = row.get("bucket_tags", [])
        if not isinstance(tags, list) or bucket_name not in tags:
            continue
        flags = row.get("metric_flags", {})
        if not isinstance(flags, dict):
            continue
        if (
            not bool(flags.get("exact_marked_object_id_pass", False))
            or not bool(flags.get("ordinal_binding_pass", False))
            or not bool(flags.get("target_resolution_pass", False))
            or not bool(flags.get("chronology_phase_pass", False))
            or str(row.get("runtime_policy_decision", "")) == "reject"
        ):
            failed += 1
    return failed


def _pp_delta(current: float, baseline: float, *, lower_is_better: bool) -> float:
    if lower_is_better:
        return (baseline - current) * 100.0
    return (current - baseline) * 100.0


def evaluate_release_gate(request: ReleaseGateRequest) -> dict[str, Any]:
    blocking_reasons: list[str] = []
    passed_checks: list[str] = []
    watchlist: list[str] = []
    critical_deltas: dict[str, float] = {}
    bucket_deltas: dict[str, dict[str, float]] = {}

    # Gate 0: contract integrity.
    candidate_contract_hashes = request.candidate_contract.get("snapshot_hashes", {})
    if not isinstance(candidate_contract_hashes, dict) or not candidate_contract_hashes:
        blocking_reasons.append("gate0:missing_candidate_contract_snapshot_hashes")
    if request.baseline_contract is not None:
        baseline_hashes = request.baseline_contract.get("snapshot_hashes", {})
        if not isinstance(baseline_hashes, dict) or not baseline_hashes:
            blocking_reasons.append("gate0:missing_baseline_contract_snapshot_hashes")
        elif baseline_hashes != candidate_contract_hashes:
            blocking_reasons.append("gate0:contract_snapshot_hash_mismatch_vs_baseline")
    if not blocking_reasons:
        passed_checks.append("gate0_contract_integrity")

    candidate_overall = _metrics(request.candidate_set_metrics, set_name="overall")

    # Gate 1: no regression vs baseline or floors.
    if request.baseline_set_metrics is None:
        for metric_name, floor in sorted(GATE1_FLOORS.items()):
            if float(candidate_overall.get(metric_name, 0.0)) < floor:
                blocking_reasons.append(f"gate1:floor_not_met:{metric_name}")
        if float(candidate_overall.get("runtime_fallback_rate", 1.0)) > 0.25:
            blocking_reasons.append("gate1:floor_not_met:runtime_fallback_rate")
    else:
        baseline_overall = _metrics(request.baseline_set_metrics, set_name="overall")
        for metric_name in CORE_METRICS:
            current = float(candidate_overall.get(metric_name, 0.0))
            baseline = float(baseline_overall.get(metric_name, 0.0))
            if metric_name == "runtime_fallback_rate":
                if not current < baseline:
                    blocking_reasons.append("gate1:runtime_fallback_must_decrease")
                critical_deltas[metric_name] = _pp_delta(current, baseline, lower_is_better=True)
                continue
            lower_is_better = metric_name in LOWER_IS_BETTER
            regression = current > baseline if lower_is_better else current < baseline
            if regression:
                blocking_reasons.append(f"gate1:core_regression:{metric_name}")
            critical_deltas[metric_name] = _pp_delta(current, baseline, lower_is_better=lower_is_better)
    if not any(reason.startswith("gate1:") for reason in blocking_reasons):
        passed_checks.append("gate1_core_no_regression")

    # Gate 2: bucket guardrails.
    gate2_failures: list[str] = []
    if request.baseline_bucket_metrics is None or request.baseline_case_results is None:
        watchlist.append("gate2_skipped_no_baseline_bucket_reference")
    else:
        for bucket_name in CRITICAL_BUCKETS:
            candidate_bucket = _bucket(request.candidate_bucket_metrics, bucket_name)
            baseline_bucket = _bucket(request.baseline_bucket_metrics, bucket_name)
            support = int(candidate_bucket.get("case_count", 0) or 0)
            metric_delta_payload: dict[str, float] = {}
            for metric_name in GATE2_METRIC_SET:
                lower_is_better = metric_name in {"runtime_fallback_rate", "dangling_target_rate"}
                candidate_metric = float(candidate_bucket.get("metrics", {}).get(metric_name, 0.0))
                baseline_metric = float(baseline_bucket.get("metrics", {}).get(metric_name, 0.0))
                delta_pp = _pp_delta(candidate_metric, baseline_metric, lower_is_better=lower_is_better)
                metric_delta_payload[metric_name] = delta_pp
            bucket_deltas[bucket_name] = metric_delta_payload

            if support >= 40:
                for metric_name, delta_pp in metric_delta_payload.items():
                    if delta_pp < -0.2:
                        gate2_failures.append(f"gate2:bucket_regression:{bucket_name}:{metric_name}")
            else:
                candidate_failed = _bucket_failed_cases(request.candidate_case_results, bucket_name)
                baseline_failed = _bucket_failed_cases(request.baseline_case_results, bucket_name)
                if candidate_failed - baseline_failed > 1:
                    gate2_failures.append(f"gate2:small_bucket_failed_case_delta:{bucket_name}")
    blocking_reasons.extend(gate2_failures)
    if not gate2_failures:
        passed_checks.append("gate2_hard_bucket_guardrails")

    # Gate 3: improvement requirement.
    gate3_failed = False
    if request.baseline_bucket_metrics is None:
        watchlist.append("gate3_improvement_check_skipped_no_baseline")
    else:
        improvements_ge_05 = 0
        improvements_ge_10 = 0
        hard_set_candidate = _metrics(request.candidate_set_metrics, set_name="hard_heldout")
        hard_set_baseline = _metrics(request.baseline_set_metrics or {}, set_name="hard_heldout")
        hard_regression = False
        for metric_name in GATE2_METRIC_SET:
            lower_is_better = metric_name in {"runtime_fallback_rate", "dangling_target_rate"}
            delta_pp = _pp_delta(
                float(hard_set_candidate.get(metric_name, 0.0)),
                float(hard_set_baseline.get(metric_name, 0.0)),
                lower_is_better=lower_is_better,
            )
            if delta_pp < 0:
                hard_regression = True
        for _, deltas in bucket_deltas.items():
            for _, delta_pp in deltas.items():
                if delta_pp >= 0.5:
                    improvements_ge_05 += 1
                if delta_pp >= 1.0:
                    improvements_ge_10 += 1
        real_runtime_candidate = _metrics(request.candidate_set_metrics, set_name="real_runtime")
        real_runtime_baseline = _metrics(request.baseline_set_metrics or {}, set_name="real_runtime")
        fallback_improved = float(real_runtime_candidate.get("runtime_fallback_rate", 1.0)) < float(
            real_runtime_baseline.get("runtime_fallback_rate", 1.0)
        )
        improvement_condition = (improvements_ge_05 >= 2) or (improvements_ge_10 >= 1)
        if not improvement_condition or hard_regression or not fallback_improved:
            gate3_failed = True
            blocking_reasons.append("gate3:improvement_requirement_failed")
    if not gate3_failed:
        passed_checks.append("gate3_improvement_requirement")

    # Gate 4: runtime sanity and top-3 clusters.
    gate4_failures: list[str] = []
    if request.baseline_set_metrics is None or request.baseline_case_results is None:
        watchlist.append("gate4_runtime_sanity_skipped_no_baseline")
    else:
        runtime_candidate = _metrics(request.candidate_set_metrics, set_name="real_runtime")
        runtime_baseline = _metrics(request.baseline_set_metrics, set_name="real_runtime")
        if float(runtime_candidate.get("llm_reject_rate", 0.0)) > float(runtime_baseline.get("llm_reject_rate", 0.0)):
            gate4_failures.append("gate4:llm_reject_rate_increase")
        merge_increase = float(runtime_candidate.get("llm_merge_rate", 0.0)) > float(runtime_baseline.get("llm_merge_rate", 0.0))
        reject_decrease = float(runtime_candidate.get("llm_reject_rate", 0.0)) < float(runtime_baseline.get("llm_reject_rate", 0.0))
        grounding_non_regression = (
            float(runtime_candidate.get("exact_marked_object_id_accuracy", 0.0))
            >= float(runtime_baseline.get("exact_marked_object_id_accuracy", 0.0))
            and float(runtime_candidate.get("ordinal_actor_binding_accuracy", 0.0))
            >= float(runtime_baseline.get("ordinal_actor_binding_accuracy", 0.0))
            and float(runtime_candidate.get("target_resolution_accuracy", 0.0))
            >= float(runtime_baseline.get("target_resolution_accuracy", 0.0))
        )
        if merge_increase and not (reject_decrease and grounding_non_regression):
            gate4_failures.append("gate4:llm_merge_rate_increase_without_required_compensation")

        for eval_set in ("hard_heldout", "real_runtime"):
            baseline_top3 = _top3(request.baseline_case_results, eval_set)
            candidate_cluster_counts = _cluster_counts(request.candidate_case_results, eval_set)
            for cluster_id, baseline_count in baseline_top3.items():
                if cluster_id not in candidate_cluster_counts:
                    continue
                candidate_count = candidate_cluster_counts[cluster_id]
                allowed_increase = max(2, int(round(baseline_count * 0.10)))
                if candidate_count - baseline_count > allowed_increase:
                    gate4_failures.append(f"gate4:cluster_regression:{eval_set}:{cluster_id}")
    blocking_reasons.extend(gate4_failures)
    if not gate4_failures:
        passed_checks.append("gate4_runtime_outcome_sanity")

    gate_status = "pass"
    if blocking_reasons:
        gate_status = "fail"
    elif watchlist:
        gate_status = "pass_with_watchlist"

    return {
        "gate_status": gate_status,
        "blocking_reasons": sorted(blocking_reasons),
        "passed_checks": sorted(passed_checks),
        "watchlist": sorted(watchlist),
        "critical_deltas": critical_deltas,
        "bucket_deltas": bucket_deltas,
        "recommended_action": (
            "promote_candidate_checkpoint"
            if gate_status == "pass"
            else "promote_with_watchlist" if gate_status == "pass_with_watchlist" else "do_not_promote"
        ),
    }
