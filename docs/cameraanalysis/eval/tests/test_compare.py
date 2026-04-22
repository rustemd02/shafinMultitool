from __future__ import annotations

from compare import build_compare_report
from compare_hybrid import build_ablation_summary, render_hybrid_markdown_summary


def test_compare_uses_case_winner_priority_order() -> None:
    manifest = {"bundle_id": "demo_bundle", "critical_buckets": ["edge_pressure_portrait", "good_frame_do_not_overcoach"]}
    baseline_scores = {
        "set_metrics": {
            "issue_f1": 0.4,
            "primary_action_match_rate": 0.3,
            "good_frame_confirmation_rate": 0.2,
            "unsupported_claim_rate": 0.0,
            "summary_consistency_rate": 0.5,
            "verdict_accuracy": 0.5,
            "strength_f1": 0.0,
            "fallback_policy_accuracy": 0.3,
            "hint_visibility_policy_accuracy": 0.3,
            "explanation_faithfulness_score": 0.3,
        },
        "bucket_metrics": {
            "edge_pressure_portrait": {"issue_f1": 0.3, "primary_action_match_rate": 0.2},
            "good_frame_do_not_overcoach": {"issue_f1": 0.1, "good_frame_confirmation_rate": 0.0},
        },
        "case_results": [
            {
                "eval_case_id": "case-1",
                "metrics": {
                    "verdict_accuracy": 0.0,
                    "issue_f1": 0.4,
                    "primary_action_match_rate": 0.0,
                    "explanation_faithfulness_score": 0.2,
                },
            }
        ],
    }
    candidate_scores = {
        "set_metrics": {
            "issue_f1": 0.7,
            "primary_action_match_rate": 0.7,
            "good_frame_confirmation_rate": 0.8,
            "unsupported_claim_rate": 0.0,
            "summary_consistency_rate": 0.8,
            "verdict_accuracy": 0.8,
            "strength_f1": 0.5,
            "fallback_policy_accuracy": 0.9,
            "hint_visibility_policy_accuracy": 0.8,
            "explanation_faithfulness_score": 0.7,
        },
        "bucket_metrics": {
            "edge_pressure_portrait": {"issue_f1": 0.8, "primary_action_match_rate": 0.7},
            "good_frame_do_not_overcoach": {"issue_f1": 0.5, "good_frame_confirmation_rate": 1.0},
        },
        "case_results": [
            {
                "eval_case_id": "case-1",
                "metrics": {
                    "verdict_accuracy": 1.0,
                    "issue_f1": 0.0,
                    "primary_action_match_rate": 0.0,
                    "explanation_faithfulness_score": 0.0,
                },
            }
        ],
    }

    report = build_compare_report(
        bundle_id="demo_bundle",
        baseline_id="legacy_suggestion_engine",
        candidate_id="camera_analysis_v1_core",
        baseline_scores=baseline_scores,
        candidate_scores=candidate_scores,
        manifest=manifest,
    )

    assert report["case_deltas"][0]["winner"] == "candidate"
    assert report["release_recommendation"]["status"] == "pass"


def test_hybrid_summary_splits_offload_tiers() -> None:
    variants = [
        {
            "variant_id": "hybrid_pause_live_offload_structured",
            "parent_variant_id": "hybrid_pause_live_local",
            "family": "runtime_policy",
            "release_recommendation": {"verdict": "research_only", "reasons": ["structured uplift"], "failure_count": 0},
            "utility_metrics": {
                "pause_uplift_win_rate": 0.6,
                "ambiguity_borderline_win_rate": 0.7,
                "style_vs_failure_conflict_win_rate": 0.4,
                "pause_neural_value_win_rate": 0.5,
                "live_guarded_win_rate": 0.3,
                "hybrid_degraded_fallback_win_rate": 0.9,
                "safe_noop_rate": 1.0,
                "case_neural_coverage_rate": 0.8,
                "applied_fusion_rate": 0.5,
            },
            "anchor_compare": {"overall": {"issue_f1": {"delta": 0.05}, "primary_action_match_rate": {"baseline": 0.8, "candidate": 0.82}, "good_frame_confirmation_rate": {"baseline": 0.9, "candidate": 0.9}}},
            "agreement_metrics": {
                "fusion_trace_coverage_rate": 1.0,
                "head_policy_agreement_rate": 1.0,
                "status_trace_consistency_rate": 1.0,
            },
            "mobile_metrics": {"pause_latency_p95_ms": 35.0, "live_latency_p95_ms": 24.0, "peak_memory_p95_mb": 100.0},
            "offload_summary": {
                "tier": "structured_only",
                "completed_rate": 0.7,
                "response_applied_rate": 0.5,
                "boundary_compliance_rate": 1.0,
            },
            "representative_cases": ["case-1"],
        },
        {
            "variant_id": "hybrid_pause_live_offload_visual",
            "parent_variant_id": "hybrid_pause_live_local",
            "family": "runtime_policy",
            "release_recommendation": {"verdict": "research_only", "reasons": ["visual uplift"], "failure_count": 0},
            "utility_metrics": {
                "pause_uplift_win_rate": 0.4,
                "ambiguity_borderline_win_rate": 0.5,
                "style_vs_failure_conflict_win_rate": 0.2,
                "pause_neural_value_win_rate": 0.3,
                "live_guarded_win_rate": 0.1,
                "hybrid_degraded_fallback_win_rate": 0.6,
                "safe_noop_rate": 1.0,
                "case_neural_coverage_rate": 0.7,
                "applied_fusion_rate": 0.4,
            },
            "anchor_compare": {"overall": {"issue_f1": {"delta": 0.03}, "primary_action_match_rate": {"baseline": 0.8, "candidate": 0.81}, "good_frame_confirmation_rate": {"baseline": 0.9, "candidate": 0.9}}},
            "agreement_metrics": {
                "fusion_trace_coverage_rate": 1.0,
                "head_policy_agreement_rate": 1.0,
                "status_trace_consistency_rate": 1.0,
            },
            "mobile_metrics": {"pause_latency_p95_ms": 36.0, "live_latency_p95_ms": 25.0, "peak_memory_p95_mb": 105.0},
            "offload_summary": {
                "tier": "redacted_visual",
                "completed_rate": 0.3,
                "response_applied_rate": 0.2,
                "boundary_compliance_rate": 1.0,
            },
            "representative_cases": ["case-2"],
        },
    ]

    ablation = build_ablation_summary(
        bundle_id="camera_analysis_hybrid_eval_v1",
        anchor_variant_id="deterministic_only",
        variants=variants,
    )
    summary = render_hybrid_markdown_summary(
        bundle_id="camera_analysis_hybrid_eval_v1",
        anchor_variant_id="deterministic_only",
        variants=variants,
    )

    assert ablation["offload_tiers"]["structured_only"][0]["variant_id"] == "hybrid_pause_live_offload_structured"
    assert ablation["offload_tiers"]["redacted_visual"][0]["variant_id"] == "hybrid_pause_live_offload_visual"
    assert "## Offload Tier Split" in summary
    assert "`structured_only` / `hybrid_pause_live_offload_structured`" in summary
    assert "`redacted_visual` / `hybrid_pause_live_offload_visual`" in summary
