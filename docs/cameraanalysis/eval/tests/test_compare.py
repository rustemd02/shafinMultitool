from __future__ import annotations

from compare import build_compare_report


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
