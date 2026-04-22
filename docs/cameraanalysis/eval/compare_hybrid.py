#!/usr/bin/env python3
"""Summary helpers for hybrid eval reports."""

from __future__ import annotations

from typing import Any, Dict, List, Optional, Sequence


VERDICT_ORDER: Dict[str, int] = {
    "ship_candidate": 0,
    "research_only": 1,
    "regression_blocked": 2,
    "mobile_blocked": 3,
    "explainability_blocked": 4,
    "no_meaningful_gain": 5,
}


def _round(value: Optional[float]) -> Optional[float]:
    if value is None:
        return None
    return round(float(value), 6)


def _compare_strength_key(variant: Dict[str, Any]) -> tuple[int, float, float]:
    release = variant.get("release_recommendation", {})
    utility = variant.get("utility_metrics", {})
    core_compare = variant.get("anchor_compare", {}).get("overall", {})
    failure_count = release.get("failure_count")
    if not isinstance(failure_count, int):
        failure_count = 0
    issue_delta = core_compare.get("issue_f1", {}).get("delta")
    if not isinstance(issue_delta, (int, float)):
        issue_delta = -999.0
    ambiguity = utility.get("ambiguity_borderline_win_rate")
    if not isinstance(ambiguity, (int, float)):
        ambiguity = -1.0
    verdict = str(release.get("verdict", "no_meaningful_gain"))
    return (failure_count, VERDICT_ORDER.get(verdict, 99), -float(ambiguity), -float(issue_delta))


def select_best_local_variant(variants: Sequence[Dict[str, Any]]) -> Optional[str]:
    local_variants = [
        variant
        for variant in variants
        if variant.get("variant_id") != "deterministic_only"
        and not bool(variant.get("capabilities", {}).get("offload", False))
    ]
    if not local_variants:
        return None
    return min(local_variants, key=_compare_strength_key).get("variant_id")


def build_ablation_summary(
    bundle_id: str,
    anchor_variant_id: str,
    variants: Sequence[Dict[str, Any]],
) -> Dict[str, Any]:
    rows: List[Dict[str, Any]] = []
    offload_tiers: Dict[str, List[Dict[str, Any]]] = {
        "structured_only": [],
        "redacted_visual": [],
    }
    for variant in variants:
        utility = variant.get("utility_metrics", {})
        release = variant.get("release_recommendation", {})
        offload_summary = variant.get("offload_summary", {})
        offload_tier = offload_summary.get("tier")
        row = {
            "variant_id": variant.get("variant_id"),
            "parent_variant_id": variant.get("parent_variant_id"),
            "family": variant.get("family"),
            "release_verdict": release.get("verdict"),
            "reasons": list(release.get("reasons", [])),
            "pause_uplift_win_rate": _round(utility.get("pause_uplift_win_rate")),
            "ambiguity_borderline_win_rate": _round(utility.get("ambiguity_borderline_win_rate")),
            "style_vs_failure_conflict_win_rate": _round(
                utility.get("style_vs_failure_conflict_win_rate")
            ),
            "pause_neural_value_win_rate": _round(utility.get("pause_neural_value_win_rate")),
            "live_guarded_win_rate": _round(utility.get("live_guarded_win_rate")),
            "hybrid_degraded_fallback_win_rate": _round(
                utility.get("hybrid_degraded_fallback_win_rate")
            ),
            "offload_tier": offload_tier,
            "offload_completed_rate": _round(offload_summary.get("completed_rate")),
            "offload_response_applied_rate": _round(offload_summary.get("response_applied_rate")),
            "offload_boundary_compliance_rate": _round(offload_summary.get("boundary_compliance_rate")),
        }
        rows.append(row)
        if offload_tier in offload_tiers:
            offload_tiers[str(offload_tier)].append(row)

    return {
        "bundle_id": bundle_id,
        "anchor_variant_id": anchor_variant_id,
        "best_local_variant_id": select_best_local_variant(variants),
        "variants": rows,
        "offload_tiers": offload_tiers,
    }


def render_hybrid_markdown_summary(
    bundle_id: str,
    anchor_variant_id: str,
    variants: Sequence[Dict[str, Any]],
) -> str:
    best_local_variant = select_best_local_variant(variants) or "n/a"
    lines = [
        "# Hybrid Eval Summary",
        "",
        "Run",
        f"- bundle: `{bundle_id}`",
        f"- anchor: `{anchor_variant_id}`",
        f"- best local variant: `{best_local_variant}`",
        "",
        "## Executive Summary",
    ]

    if not variants:
        lines.append("- no hybrid variants were evaluated")
    else:
        for variant in variants:
            release = variant.get("release_recommendation", {})
            utility = variant.get("utility_metrics", {})
            lines.append(
                "- "
                f"`{variant.get('variant_id')}` -> `{release.get('verdict', 'unknown')}`; "
                f"`safe_noop_rate={_format_metric(utility.get('safe_noop_rate'))}`, "
                f"`ambiguity_win={_format_metric(utility.get('ambiguity_borderline_win_rate'))}`"
            )

    lines.extend(
        [
            "",
            "## Core Non-Regression",
        ]
    )
    for variant in variants:
        overall = variant.get("anchor_compare", {}).get("overall", {})
        lines.append(
            "- "
            f"`{variant.get('variant_id')}`: "
            f"`issue_f1 {_format_triplet(overall.get('issue_f1'))}`, "
            f"`primary_action_match_rate {_format_triplet(overall.get('primary_action_match_rate'))}`, "
            f"`good_frame_confirmation_rate {_format_triplet(overall.get('good_frame_confirmation_rate'))}`"
        )

    lines.extend(
        [
            "",
            "## Hybrid Utility",
        ]
    )
    for variant in variants:
        utility = variant.get("utility_metrics", {})
        lines.append(
            "- "
            f"`{variant.get('variant_id')}`: "
            f"`safe_noop_rate={_format_metric(utility.get('safe_noop_rate'))}`, "
            f"`case_neural_coverage_rate={_format_metric(utility.get('case_neural_coverage_rate'))}`, "
            f"`applied_fusion_rate={_format_metric(utility.get('applied_fusion_rate'))}`"
        )

    lines.extend(
        [
            "",
            "## Explainability Agreement",
        ]
    )
    for variant in variants:
        agreement = variant.get("agreement_metrics", {})
        lines.append(
            "- "
            f"`{variant.get('variant_id')}`: "
            f"`fusion_trace_coverage_rate={_format_metric(agreement.get('fusion_trace_coverage_rate'))}`, "
            f"`head_policy_agreement_rate={_format_metric(agreement.get('head_policy_agreement_rate'))}`, "
            f"`status_trace_consistency_rate={_format_metric(agreement.get('status_trace_consistency_rate'))}`"
        )

    lines.extend(
        [
            "",
            "## Mobile Viability",
        ]
    )
    for variant in variants:
        mobile = variant.get("mobile_metrics", {})
        lines.append(
            "- "
            f"`{variant.get('variant_id')}`: "
            f"`pause_latency_p95_ms={_format_metric(mobile.get('pause_latency_p95_ms'))}`, "
            f"`live_latency_p95_ms={_format_metric(mobile.get('live_latency_p95_ms'))}`, "
            f"`peak_memory_p95_mb={_format_metric(mobile.get('peak_memory_p95_mb'))}`"
        )

    lines.extend(
        [
            "",
            "## Ablation Highlights",
        ]
    )
    for variant in variants:
        release = variant.get("release_recommendation", {})
        reasons = list(release.get("reasons", []))
        reason = reasons[0] if reasons else "no notable highlight"
        lines.append(f"- `{variant.get('variant_id')}`: {reason}")

    offload_variants = [variant for variant in variants if variant.get("offload_summary", {}).get("tier")]
    if offload_variants:
        lines.extend(
            [
                "",
                "## Offload Tier Split",
            ]
        )
        for tier in ("structured_only", "redacted_visual"):
            tier_rows = [
                variant for variant in offload_variants if variant.get("offload_summary", {}).get("tier") == tier
            ]
            if not tier_rows:
                continue
            for variant in tier_rows:
                offload_summary = variant.get("offload_summary", {})
                lines.append(
                    "- "
                    f"`{tier}` / `{variant.get('variant_id')}`: "
                    f"`completed_rate={_format_metric(offload_summary.get('completed_rate'))}`, "
                    f"`response_applied_rate={_format_metric(offload_summary.get('response_applied_rate'))}`, "
                    f"`boundary_compliance_rate={_format_metric(offload_summary.get('boundary_compliance_rate'))}`"
                )

    lines.extend(
        [
            "",
            "## Representative Cases",
        ]
    )
    for variant in variants:
        representative = variant.get("representative_cases", [])
        if representative:
            for case_id in representative[:3]:
                lines.append(f"- `{variant.get('variant_id')}`: `{case_id}`")
        else:
            lines.append(f"- `{variant.get('variant_id')}`: no representative hybrid cases")

    lines.extend(
        [
            "",
            "## Release Recommendation",
        ]
    )
    for variant in variants:
        release = variant.get("release_recommendation", {})
        lines.append(
            "- "
            f"`{variant.get('variant_id')}`: verdict `{release.get('verdict', 'unknown')}`"
        )
        for reason in release.get("reasons", [])[:3]:
            lines.append(f"  - {reason}")

    return "\n".join(lines) + "\n"


def _format_metric(value: Any) -> str:
    if not isinstance(value, (int, float)):
        return "n/a"
    return f"{float(value):.2f}"


def _format_triplet(payload: Any) -> str:
    if not isinstance(payload, dict):
        return "n/a"
    baseline = payload.get("baseline")
    candidate = payload.get("candidate")
    if not isinstance(baseline, (int, float)) or not isinstance(candidate, (int, float)):
        return "n/a"
    return f"{float(baseline):.2f}->{float(candidate):.2f}"
