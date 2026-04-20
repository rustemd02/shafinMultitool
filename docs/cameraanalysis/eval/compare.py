#!/usr/bin/env python3
"""Baseline-vs-candidate compare helpers for eval harness."""

from __future__ import annotations

from typing import Any, Dict, Iterable, List, Optional, Sequence, Tuple


CASE_WINNER_ORDER: Tuple[str, ...] = (
    "verdict_accuracy",
    "issue_f1",
    "primary_action_match_rate",
    "explanation_faithfulness_score",
)

OVERALL_COMPARE_METRICS: Tuple[str, ...] = (
    "verdict_accuracy",
    "issue_f1",
    "strength_f1",
    "primary_action_match_rate",
    "good_frame_confirmation_rate",
    "fallback_policy_accuracy",
    "hint_visibility_policy_accuracy",
    "explanation_faithfulness_score",
    "summary_consistency_rate",
    "unsupported_claim_rate",
)


def _round(value: Optional[float]) -> Optional[float]:
    if value is None:
        return None
    return round(float(value), 6)


def _delta(candidate: Optional[float], baseline: Optional[float]) -> Optional[float]:
    if candidate is None or baseline is None:
        return None
    return candidate - baseline


def _winner_by_priority(
    baseline_metrics: Dict[str, Any],
    candidate_metrics: Dict[str, Any],
    order: Sequence[str],
) -> Tuple[str, Optional[str]]:
    for key in order:
        base = baseline_metrics.get(key)
        cand = candidate_metrics.get(key)
        if not isinstance(base, (int, float)) or not isinstance(cand, (int, float)):
            continue
        if abs(cand - base) <= 1e-9:
            continue
        if cand > base:
            return "candidate", key
        return "baseline", key
    return "tie", None


def _metric_triplet(
    baseline_metrics: Dict[str, Any],
    candidate_metrics: Dict[str, Any],
    metric: str,
) -> Dict[str, Optional[float]]:
    base = baseline_metrics.get(metric)
    cand = candidate_metrics.get(metric)
    base_float = float(base) if isinstance(base, (int, float)) else None
    cand_float = float(cand) if isinstance(cand, (int, float)) else None
    return {
        "baseline": _round(base_float),
        "candidate": _round(cand_float),
        "delta": _round(_delta(cand_float, base_float)),
    }


def _index_case_results(case_results: Sequence[Dict[str, Any]]) -> Dict[str, Dict[str, Any]]:
    return {str(item["eval_case_id"]): item for item in case_results}


def build_compare_report(
    bundle_id: str,
    baseline_id: str,
    candidate_id: str,
    baseline_scores: Dict[str, Any],
    candidate_scores: Dict[str, Any],
    manifest: Dict[str, Any],
) -> Dict[str, Any]:
    baseline_set = baseline_scores.get("set_metrics", {})
    candidate_set = candidate_scores.get("set_metrics", {})

    overall: Dict[str, Dict[str, Optional[float]]] = {}
    for metric in OVERALL_COMPARE_METRICS:
        overall[metric] = _metric_triplet(baseline_set, candidate_set, metric)

    baseline_case_map = _index_case_results(baseline_scores.get("case_results", []))
    candidate_case_map = _index_case_results(candidate_scores.get("case_results", []))
    all_case_ids = sorted(set(baseline_case_map.keys()) | set(candidate_case_map.keys()))

    case_deltas: List[Dict[str, Any]] = []
    bucket_win_counts = {"candidate": 0, "baseline": 0, "tie": 0}
    for case_id in all_case_ids:
        base_metrics = baseline_case_map.get(case_id, {}).get("metrics", {})
        cand_metrics = candidate_case_map.get(case_id, {}).get("metrics", {})
        winner, deciding_metric = _winner_by_priority(base_metrics, cand_metrics, CASE_WINNER_ORDER)
        reason = (
            f"decided by {deciding_metric}"
            if deciding_metric is not None
            else "all priority metrics tied"
        )
        case_deltas.append(
            {
                "eval_case_id": case_id,
                "winner": winner,
                "why": [reason],
            }
        )
        if winner in bucket_win_counts:
            bucket_win_counts[winner] += 1

    baseline_buckets = baseline_scores.get("bucket_metrics", {})
    candidate_buckets = candidate_scores.get("bucket_metrics", {})
    all_buckets = sorted(set(baseline_buckets.keys()) | set(candidate_buckets.keys()))
    bucket_wins = {"candidate": 0, "baseline": 0, "tie": 0}
    for bucket in all_buckets:
        base_metrics = baseline_buckets.get(bucket, {})
        cand_metrics = candidate_buckets.get(bucket, {})
        winner, _ = _winner_by_priority(base_metrics, cand_metrics, CASE_WINNER_ORDER)
        bucket_wins[winner] += 1

    critical_buckets = manifest.get("critical_buckets", [])
    critical_bucket_delta: Dict[str, Dict[str, float]] = {}
    improved_critical_count = 0
    for bucket in critical_buckets:
        base_metrics = baseline_buckets.get(bucket, {})
        cand_metrics = candidate_buckets.get(bucket, {})
        bucket_delta: Dict[str, float] = {}
        for metric in (
            "issue_f1",
            "primary_action_match_rate",
            "good_frame_confirmation_rate",
            "fallback_policy_accuracy",
            "hint_visibility_policy_accuracy",
        ):
            delta = _delta(
                float(cand_metrics[metric]) if isinstance(cand_metrics.get(metric), (int, float)) else None,
                float(base_metrics[metric]) if isinstance(base_metrics.get(metric), (int, float)) else None,
            )
            if delta is not None:
                bucket_delta[f"{metric}_delta"] = _round(delta) or 0.0
        if bucket_delta:
            critical_bucket_delta[str(bucket)] = bucket_delta
            if any(value > 0.0 for value in bucket_delta.values()):
                improved_critical_count += 1

    release = _release_recommendation(
        baseline_set=baseline_set,
        candidate_set=candidate_set,
        improved_critical_count=improved_critical_count,
    )

    return {
        "compare_id": manifest.get("bundle_id", bundle_id) + "_compare",
        "bundle_id": bundle_id,
        "baseline_id": baseline_id,
        "candidate_id": candidate_id,
        "overall": overall,
        "bucket_wins": bucket_wins,
        "case_deltas": case_deltas,
        "critical_bucket_delta": critical_bucket_delta,
        "release_recommendation": release,
    }


def _release_recommendation(
    baseline_set: Dict[str, Any],
    candidate_set: Dict[str, Any],
    improved_critical_count: int,
) -> Dict[str, Any]:
    reasons: List[str] = []
    failures: List[str] = []

    issue_f1_base = baseline_set.get("issue_f1")
    issue_f1_cand = candidate_set.get("issue_f1")
    if isinstance(issue_f1_base, (int, float)) and isinstance(issue_f1_cand, (int, float)):
        if issue_f1_cand < issue_f1_base - 0.03:
            failures.append("issue_f1 regressed more than 0.03")
        else:
            reasons.append("no critical regression on issue_f1")

    action_base = baseline_set.get("primary_action_match_rate")
    action_cand = candidate_set.get("primary_action_match_rate")
    if isinstance(action_base, (int, float)) and isinstance(action_cand, (int, float)):
        if action_cand < action_base - 0.03:
            failures.append("primary_action_match_rate regressed more than 0.03")
        else:
            reasons.append("no critical regression on primary_action_match_rate")

    good_base = baseline_set.get("good_frame_confirmation_rate")
    good_cand = candidate_set.get("good_frame_confirmation_rate")
    if isinstance(good_base, (int, float)) and isinstance(good_cand, (int, float)):
        if good_cand < good_base:
            failures.append("good_frame_confirmation_rate regressed")
        else:
            reasons.append("good frame confirmation did not regress")

    unsupported_base = baseline_set.get("unsupported_claim_rate")
    unsupported_cand = candidate_set.get("unsupported_claim_rate")
    if isinstance(unsupported_base, (int, float)) and isinstance(unsupported_cand, (int, float)):
        if unsupported_cand > unsupported_base:
            failures.append("unsupported_claim_rate increased")
        else:
            reasons.append("unsupported claims did not increase")

    if improved_critical_count >= 2:
        reasons.append("critical buckets improved in at least two categories")
    else:
        failures.append("not enough critical bucket improvements")

    status = "pass" if not failures else "fail"
    merged_reasons = reasons if status == "pass" else failures + reasons
    return {"status": status, "reasons": merged_reasons}


def render_markdown_summary(
    bundle_id: str,
    baseline_id: str,
    candidate_id: str,
    compare_report: Dict[str, Any],
) -> str:
    overall = compare_report.get("overall", {})
    release = compare_report.get("release_recommendation", {})

    def metric_line(metric: str) -> str:
        payload = overall.get(metric, {})
        base = payload.get("baseline")
        cand = payload.get("candidate")
        if base is None or cand is None:
            return f"- `{metric}`: n/a"
        return f"- `{metric}`: `{base:.2f}` -> `{cand:.2f}`"

    lines = [
        "# Camera Analysis Eval Summary",
        "",
        "Run:",
        f"- bundle: `{bundle_id}`",
        f"- baseline: `{baseline_id}`",
        f"- candidate: `{candidate_id}`",
        "",
        "## Strengths",
        metric_line("issue_f1"),
        metric_line("primary_action_match_rate"),
        metric_line("good_frame_confirmation_rate"),
        "",
        "## Issues",
        metric_line("unsupported_claim_rate"),
        metric_line("hint_visibility_policy_accuracy"),
        metric_line("hint_jitter_rate"),
        "",
        "## Actions",
        metric_line("fallback_policy_accuracy"),
        metric_line("summary_consistency_rate"),
        "",
        "## Explanation Faithfulness",
        metric_line("explanation_faithfulness_score"),
        "",
        "## Release / Merge Recommendation",
        "",
        f"Status: `{release.get('status', 'unknown')}`",
        "",
        "Why:",
    ]
    for reason in release.get("reasons", []):
        lines.append(f"- {reason}")
    return "\n".join(lines) + "\n"
