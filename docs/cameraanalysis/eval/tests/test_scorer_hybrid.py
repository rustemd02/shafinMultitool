from __future__ import annotations

from compare import build_compare_report
from scorer import score_model
from scorer_hybrid import (
    _build_release_recommendation,
    extract_final_outputs,
    normalize_projection_rows,
    score_hybrid_variant,
    validate_hybrid_case_contract,
    validate_variant_projections,
)


def _pause_case(
    case_id: str,
    hybrid_eval: dict,
    required_issues: list[str],
    allowed_actions: list[str],
    forbidden_issues: list[str] | None = None,
    strengths: list[str] | None = None,
) -> dict:
    return {
        "eval_case_id": case_id,
        "eval_set": "pause_curated",
        "case_kind": "single_frame_pause",
        "bucket_tags": ["needs_fix"] if required_issues else ["good_frame_do_not_overcoach"],
        "input": {
            "feature_snapshot": {"frameId": case_id, "mode": "pause"},
            "scene_semantics": {
                "frameId": case_id,
                "mode": "pause",
                "primarySubject": {"kind": "person"},
            },
        },
        "hybrid_eval": hybrid_eval,
        "gold_expectations": {
            "verdict": "needs_fix" if required_issues else "good",
            "required_issues": required_issues,
            "forbidden_issues": forbidden_issues or [],
            "required_strengths": strengths or [],
            "forbidden_strengths": [],
            "allowed_primary_actions": allowed_actions,
            "required_fix_types": ["reframing"] if required_issues else [],
            "fallback_expected": False,
            "good_frame_policy": "must_not_confirm_good_frame" if required_issues else "must_confirm_good_frame",
            "explainability": {
                "required_issue_links": required_issues,
                "require_observation_interpretation_recommendation_chain": True,
                "summary_must_reference_any": ["edge"] if required_issues else ["good"],
            },
        },
    }


def _make_output(
    case_id: str,
    verdict: str,
    issue_types: list[str],
    action_type: str | None,
    summary_text: str,
    include_neural_trace: bool = False,
    neural_head_id: str = "subject_prominence",
) -> dict:
    issues = []
    for idx, issue_type in enumerate(issue_types):
        issues.append(
            {
                "id": f"{case_id}:issue:{idx}",
                "type": issue_type,
                "severity": 0.8,
                "suggestedFixTypes": ["reframing"],
                "evidence": [{"key": "snapshot.composition.horizontalOffset"}],
            }
        )
    primary_action = None
    if action_type is not None:
        primary_action = {
            "id": f"{case_id}:action:0",
            "actionType": action_type,
            "linkedIssueIds": [issue["id"] for issue in issues],
        }
    trace_items = []
    if include_neural_trace:
        trace_items = [
            {
                "id": f"{case_id}:trace:obs",
                "stage": "observation",
                "evidenceKeys": [f"neural.{neural_head_id}.score"],
                "dependsOn": [],
                "links": [],
            },
            {
                "id": f"{case_id}:trace:int",
                "stage": "interpretation",
                "evidenceKeys": [f"neural.{neural_head_id}.confidence", "rule.hybrid.fusion"],
                "dependsOn": [f"{case_id}:trace:obs"],
                "links": [{"kind": "issue", "refId": issues[0]["id"]}] if issues else [],
            },
            {
                "id": f"{case_id}:trace:rec",
                "stage": "recommendation",
                "evidenceKeys": ["planner.primary_action"],
                "dependsOn": [f"{case_id}:trace:int"],
                "links": [{"kind": "action", "refId": primary_action["id"]}] if primary_action else [],
            },
        ]
    return {
        "critique_report": {
            "verdict": verdict,
            "issues": issues,
            "strengths": [],
            "summary": {
                "id": f"{case_id}:summary",
                "shortVerdict": summary_text,
                "whyGood": summary_text if verdict == "good" else None,
                "whyProblematic": summary_text if verdict != "good" else None,
            },
            "fallbackUsed": False,
        },
        "recommendation_plan": {
            "mode": "pause",
            "primaryAction": primary_action,
            "secondaryActions": [],
            "noChangeRationale": "No changes needed." if action_type == "leave_frame_as_is" else None,
        },
        "explainability_trace": {"items": trace_items},
        "live_hint_projection": {"hintState": "hidden", "primaryAction": None},
        "unsupported_claims": 0,
    }


def _neural_snapshot(status_map: dict[str, str]) -> dict:
    ordered_heads = [
        "subject_prominence",
        "background_clutter",
        "lighting_quality",
        "face_saliency",
        "balance_confidence",
        "depth_separation",
        "cinematic_expressiveness",
        "shot_type_confidence",
    ]
    head_outputs = []
    for head_id in ordered_heads:
        status = status_map.get(head_id, "not_applicable")
        payload: dict[str, object]
        if head_id == "shot_type_confidence":
            payload = {
                "headId": head_id,
                "status": status,
                "affinities": [] if status != "available" else [{"categoryId": "unknown_affinity", "score": 0.6}],
                "confidence": 0.7 if status == "available" else 0.0,
                "mode": "pause",
                "supportingSignals": [],
            }
        else:
            payload = {
                "headId": head_id,
                "status": status,
                "score": 0.7 if status == "available" else None,
                "confidence": 0.8 if status == "available" else 0.0,
                "mode": "pause",
                "supportingSignals": [],
            }
        head_outputs.append({"headId": head_id, "payload": payload})
    return {
        "schemaVersion": "h1",
        "frameId": "frame",
        "mode": "pause",
        "capturedAt": "2026-04-22T00:00:00Z",
        "bundleVersion": "demo",
        "headOutputs": head_outputs,
    }


def test_score_hybrid_variant_reports_pause_metrics_and_gate() -> None:
    cases = [
        _pause_case(
            "case-borderline",
            {
                "ambiguityBucket": "borderline",
                "conflictBucket": "style_vs_failure",
                "expectedGainMode": "pause_only",
                "expectedEligibleHeadIds": ["subject_prominence", "face_saliency"],
                "expectedFusionBehavior": "reinforce",
                "forbiddenAppliedHeadIds": ["lighting_quality"],
            },
            required_issues=["subject_too_close_to_edge"],
            allowed_actions=["move_frame_left"],
        ),
        _pause_case(
            "case-degraded",
            {
                "ambiguityBucket": "clear",
                "conflictBucket": "weak_signal",
                "expectedGainMode": "pause_only",
                "expectedEligibleHeadIds": ["subject_prominence"],
                "expectedFusionBehavior": "noop",
            },
            required_issues=[],
            allowed_actions=["leave_frame_as_is"],
            strengths=["good_subject_isolation"],
        ),
    ]

    deterministic_projections = {
        "case-borderline": {
            "evalCaseId": "case-borderline",
            "projectionKind": "single_frame",
            "deterministicOutput": _make_output("case-borderline", "good", [], None, "Looks good"),
            "finalOutput": _make_output("case-borderline", "good", [], None, "Looks good"),
            "localPhaseOutput": _make_output("case-borderline", "good", [], None, "Looks good"),
            "fusionDecisions": [],
            "inferenceOutcome": {"status": "disabled", "mode": "pause", "hasSnapshot": False, "failureReason": None},
        },
        "case-degraded": {
            "evalCaseId": "case-degraded",
            "projectionKind": "single_frame",
            "deterministicOutput": _make_output("case-degraded", "good", [], "leave_frame_as_is", "Good frame"),
            "finalOutput": _make_output("case-degraded", "good", [], "leave_frame_as_is", "Good frame"),
            "localPhaseOutput": _make_output("case-degraded", "good", [], "leave_frame_as_is", "Good frame"),
            "fusionDecisions": [],
            "inferenceOutcome": {"status": "disabled", "mode": "pause", "hasSnapshot": False, "failureReason": None},
        },
    }
    validate_variant_projections(cases, deterministic_projections, {"pauseLocalHybrid": False, "liveHybrid": False, "offload": False})
    anchor_scores = score_model(cases, extract_final_outputs(deterministic_projections))

    hybrid_projections = {
        "case-borderline": {
            "evalCaseId": "case-borderline",
            "projectionKind": "single_frame",
            "deterministicOutput": deterministic_projections["case-borderline"]["finalOutput"],
            "finalOutput": _make_output(
                "case-borderline",
                "needs_fix",
                ["subject_too_close_to_edge"],
                "move_frame_left",
                "Edge pressure is hurting the frame.",
                include_neural_trace=True,
            ),
            "localPhaseOutput": _make_output(
                "case-borderline",
                "needs_fix",
                ["subject_too_close_to_edge"],
                "move_frame_left",
                "Edge pressure is hurting the frame.",
                include_neural_trace=True,
            ),
            "neuralSnapshot": _neural_snapshot({"subject_prominence": "available", "face_saliency": "available"}),
            "fusionDecisions": [
                {
                    "decisionId": "d1",
                    "targetKind": "issue",
                    "targetId": "case-borderline:issue:0",
                    "targetType": "subject_too_close_to_edge",
                    "outcome": "reinforced",
                    "delta": 0.07,
                    "appliedHeadIds": ["subject_prominence"],
                }
            ],
            "inferenceOutcome": {"status": "executed", "mode": "pause", "hasSnapshot": True, "failureReason": None},
            "runtimeSample": {
                "variantId": "hybrid_pause_local",
                "evalCaseId": "case-borderline",
                "mode": "pause",
                "executionProfile": "normal",
                "thermalTier": "unrestricted",
                "peakMemoryMB": 82,
                "staleDropped": False,
                "inferenceLatencyMs": 28,
            },
        },
        "case-degraded": {
            "evalCaseId": "case-degraded",
            "projectionKind": "single_frame",
            "deterministicOutput": deterministic_projections["case-degraded"]["finalOutput"],
            "finalOutput": deterministic_projections["case-degraded"]["finalOutput"],
            "localPhaseOutput": deterministic_projections["case-degraded"]["finalOutput"],
            "neuralSnapshot": _neural_snapshot({"subject_prominence": "available"}),
            "fusionDecisions": [],
            "inferenceOutcome": {"status": "executed", "mode": "pause", "hasSnapshot": True, "failureReason": None},
            "runtimeSample": {
                "variantId": "hybrid_pause_local",
                "evalCaseId": "case-degraded",
                "mode": "pause",
                "executionProfile": "degraded_pause_profile",
                "thermalTier": "constrained",
                "peakMemoryMB": 90,
                "staleDropped": False,
                "inferenceLatencyMs": 35,
            },
        },
    }
    validate_variant_projections(cases, hybrid_projections, {"pauseLocalHybrid": True, "liveHybrid": False, "offload": False})
    hybrid_scores = score_model(cases, extract_final_outputs(hybrid_projections))
    compare_report = build_compare_report(
        bundle_id="camera_analysis_hybrid_eval_v1",
        baseline_id="deterministic_only",
        candidate_id="hybrid_pause_local",
        baseline_scores=anchor_scores,
        candidate_scores=hybrid_scores,
        manifest={
            "bundle_id": "camera_analysis_hybrid_eval_v1",
            "critical_buckets": [],
        },
    )

    report = score_hybrid_variant(
        variant_id="hybrid_pause_local",
        parent_variant_id="deterministic_only",
        family="runtime_policy",
        capabilities={"pauseLocalHybrid": True, "liveHybrid": False, "offload": False},
        cases=cases,
        projections_by_case_id=hybrid_projections,
        core_scores=hybrid_scores,
        anchor_core_scores=anchor_scores,
        anchor_compare=compare_report,
    )

    utility = report["utility_metrics"]
    agreement = report["agreement_metrics"]
    mobile = report["mobile_metrics"]

    assert utility["eligible_head_availability_rate"] == 1.0
    assert utility["case_neural_coverage_rate"] == 1.0
    assert utility["hybrid_degraded_fallback_score"] == 1.0
    assert utility["hybrid_degraded_fallback_win_rate"] == 1.0
    assert agreement["fusion_expectation_agreement_rate"] == 1.0
    assert agreement["forbidden_head_violation_rate"] == 0.0
    assert mobile["pause_execute_success_rate"] == 1.0
    assert mobile["pause_degraded_execution_rate"] == 0.5
    assert mobile["pause_failure_rate"] == 0.0
    assert report["release_recommendation"]["verdict"] == "ship_candidate"


def test_validate_hybrid_case_contract_rejects_contradictory_redacted_visual_metadata() -> None:
    cases = [
        _pause_case(
            "case-redacted-invalid",
                {
                    "ambiguityBucket": "clear",
                    "conflictBucket": "none",
                    "expectedGainMode": "pause_only",
                    "offloadTierAllowed": "redacted_visual",
                    "visualReplayRef": "optional://redacted/frame.png",
                    "visualReplayTrigger": "eval_sampling",
                },
            required_issues=[],
            allowed_actions=["leave_frame_as_is"],
        )
    ]

    try:
        validate_hybrid_case_contract(cases)
    except ValueError as exc:
        assert "visualReplayTrigger=explicit_user_request" in str(exc)
    else:
        raise AssertionError("validate_hybrid_case_contract must fail for contradictory redacted_visual metadata")


def test_validate_variant_projections_requires_runtime_sidecar_for_executed_pause_hybrid() -> None:
    cases = [
        _pause_case(
            "case-sidecar-required",
            {
                "ambiguityBucket": "borderline",
                "conflictBucket": "none",
                "expectedGainMode": "pause_only",
            },
            required_issues=["subject_too_close_to_edge"],
            allowed_actions=["move_frame_left"],
        )
    ]

    projections = {
        "case-sidecar-required": {
            "evalCaseId": "case-sidecar-required",
            "projectionKind": "single_frame",
            "deterministicOutput": _make_output("case-sidecar-required", "good", [], None, "Looks good"),
            "finalOutput": _make_output(
                "case-sidecar-required",
                "needs_fix",
                ["subject_too_close_to_edge"],
                "move_frame_left",
                "Edge pressure is hurting the frame.",
                include_neural_trace=True,
            ),
            "localPhaseOutput": _make_output(
                "case-sidecar-required",
                "needs_fix",
                ["subject_too_close_to_edge"],
                "move_frame_left",
                "Edge pressure is hurting the frame.",
                include_neural_trace=True,
            ),
            "inferenceOutcome": {"status": "executed", "mode": "pause", "hasSnapshot": True, "failureReason": None},
            "fusionDecisions": [],
        }
    }

    try:
        validate_variant_projections(
            cases,
            projections,
            {"pauseLocalHybrid": True, "liveHybrid": False, "offload": False},
        )
    except ValueError as exc:
        assert "runtimeSample" in str(exc)
    else:
        raise AssertionError("validate_variant_projections must fail when executed pause hybrid lacks runtimeSample")


def test_normalize_projection_rows_rejects_duplicate_case_ids() -> None:
    rows = [
        {"evalCaseId": "dup-case", "projectionKind": "single_frame"},
        {"evalCaseId": "dup-case", "projectionKind": "single_frame"},
    ]

    try:
        normalize_projection_rows(rows)
    except ValueError as exc:
        assert "duplicate projection row" in str(exc)
    else:
        raise AssertionError("normalize_projection_rows must fail for duplicate evalCaseId rows")


def test_release_gate_blocks_safe_noop_drift() -> None:
    release = _build_release_recommendation(
        capabilities={"pauseLocalHybrid": True, "liveHybrid": False, "offload": False},
        anchor_compare={
            "overall": {
                "issue_f1": {"delta": 0.0},
                "primary_action_match_rate": {"delta": 0.0},
                "good_frame_confirmation_rate": {"delta": 0.0},
                "unsupported_claim_rate": {"delta": 0.0},
            }
        },
        utility_metrics={
            "safe_noop_rate": 0.5,
            "ambiguity_borderline_win_rate": 1.0,
            "style_vs_failure_conflict_win_rate": 1.0,
            "pause_neural_value_win_rate": 0.0,
            "hybrid_degraded_fallback_win_rate": 0.0,
        },
        agreement_metrics={
            "fusion_trace_coverage_rate": 1.0,
            "head_policy_agreement_rate": 1.0,
            "status_trace_consistency_rate": 1.0,
        },
        mobile_metrics={
            "pause_execute_success_rate": 1.0,
            "pause_failure_rate": 0.0,
            "pause_degraded_execution_rate": 0.5,
            "pause_latency_p95_ms": 30.0,
            "peak_memory_p95_mb": 90.0,
        },
        has_degraded_pause_samples=True,
        live_sample_count=0,
    )

    assert release["verdict"] == "regression_blocked"
    assert any("safe_noop_rate" in reason for reason in release["reasons"])


def test_optional_agreement_metrics_do_not_block_ship_candidate() -> None:
    release = _build_release_recommendation(
        capabilities={"pauseLocalHybrid": True, "liveHybrid": False, "offload": False},
        anchor_compare={
            "overall": {
                "issue_f1": {"delta": 0.0},
                "primary_action_match_rate": {"delta": 0.0},
                "good_frame_confirmation_rate": {"delta": 0.0},
                "unsupported_claim_rate": {"delta": 0.0},
            }
        },
        utility_metrics={
            "safe_noop_rate": 1.0,
            "ambiguity_borderline_win_rate": 1.0,
            "style_vs_failure_conflict_win_rate": 1.0,
            "pause_neural_value_win_rate": 0.0,
            "hybrid_degraded_fallback_win_rate": 0.0,
        },
        agreement_metrics={
            "fusion_trace_coverage_rate": 1.0,
            "head_policy_agreement_rate": 1.0,
            "status_trace_consistency_rate": 1.0,
        },
        mobile_metrics={
            "pause_execute_success_rate": 1.0,
            "pause_failure_rate": 0.0,
            "pause_degraded_execution_rate": 0.5,
            "pause_latency_p95_ms": 30.0,
            "peak_memory_p95_mb": 90.0,
        },
        has_degraded_pause_samples=True,
        live_sample_count=0,
    )

    assert release["verdict"] == "ship_candidate"


def test_live_guarded_bucket_counts_toward_meaningful_gain() -> None:
    release = _build_release_recommendation(
        capabilities={"pauseLocalHybrid": True, "liveHybrid": True, "offload": False},
        anchor_compare={
            "overall": {
                "issue_f1": {"delta": 0.0},
                "primary_action_match_rate": {"delta": 0.0},
                "good_frame_confirmation_rate": {"delta": 0.0},
                "unsupported_claim_rate": {"delta": 0.0},
            }
        },
        utility_metrics={
            "safe_noop_rate": 1.0,
            "ambiguity_borderline_win_rate": 1.0,
            "style_vs_failure_conflict_win_rate": 0.0,
            "pause_neural_value_win_rate": 0.0,
            "hybrid_degraded_fallback_win_rate": 0.0,
            "live_guarded_win_rate": 1.0,
        },
        agreement_metrics={
            "fusion_trace_coverage_rate": 1.0,
            "head_policy_agreement_rate": 1.0,
            "status_trace_consistency_rate": 1.0,
        },
        mobile_metrics={
            "pause_execute_success_rate": 1.0,
            "pause_failure_rate": 0.0,
            "pause_degraded_execution_rate": None,
            "pause_latency_p95_ms": 30.0,
            "peak_memory_p95_mb": 90.0,
            "live_latency_p95_ms": 20.0,
            "live_policy_skip_rate": 0.5,
            "critical_thermal_skip_rate": 1.0,
        },
        has_degraded_pause_samples=False,
        live_sample_count=12,
    )

    assert release["verdict"] == "ship_candidate"


def test_live_gate_without_critical_thermal_coverage_stays_research_only() -> None:
    release = _build_release_recommendation(
        capabilities={"pauseLocalHybrid": True, "liveHybrid": True, "offload": False},
        anchor_compare={
            "overall": {
                "issue_f1": {"delta": 0.0},
                "primary_action_match_rate": {"delta": 0.0},
                "good_frame_confirmation_rate": {"delta": 0.0},
                "unsupported_claim_rate": {"delta": 0.0},
            }
        },
        utility_metrics={
            "safe_noop_rate": 1.0,
            "ambiguity_borderline_win_rate": 1.0,
            "style_vs_failure_conflict_win_rate": 0.0,
            "pause_neural_value_win_rate": 0.0,
            "hybrid_degraded_fallback_win_rate": 0.0,
            "live_guarded_win_rate": 1.0,
        },
        agreement_metrics={
            "fusion_trace_coverage_rate": 1.0,
            "head_policy_agreement_rate": 1.0,
            "status_trace_consistency_rate": 1.0,
        },
        mobile_metrics={
            "pause_execute_success_rate": 1.0,
            "pause_failure_rate": 0.0,
            "pause_degraded_execution_rate": None,
            "pause_latency_p95_ms": 30.0,
            "peak_memory_p95_mb": 90.0,
            "live_latency_p95_ms": 20.0,
            "live_policy_skip_rate": 0.5,
            "critical_thermal_skip_rate": None,
        },
        has_degraded_pause_samples=False,
        live_sample_count=12,
    )

    assert release["verdict"] == "research_only"
    assert any("critical thermal" in reason for reason in release["reasons"])


def test_live_gate_with_too_few_samples_stays_research_only() -> None:
    release = _build_release_recommendation(
        capabilities={"pauseLocalHybrid": True, "liveHybrid": True, "offload": False},
        anchor_compare={
            "overall": {
                "issue_f1": {"delta": 0.0},
                "primary_action_match_rate": {"delta": 0.0},
                "good_frame_confirmation_rate": {"delta": 0.0},
                "unsupported_claim_rate": {"delta": 0.0},
            }
        },
        utility_metrics={
            "safe_noop_rate": 1.0,
            "ambiguity_borderline_win_rate": 1.0,
            "style_vs_failure_conflict_win_rate": 0.0,
            "pause_neural_value_win_rate": 0.0,
            "hybrid_degraded_fallback_win_rate": 0.0,
            "live_guarded_win_rate": 1.0,
        },
        agreement_metrics={
            "fusion_trace_coverage_rate": 1.0,
            "head_policy_agreement_rate": 1.0,
            "status_trace_consistency_rate": 1.0,
        },
        mobile_metrics={
            "pause_execute_success_rate": 1.0,
            "pause_failure_rate": 0.0,
            "pause_degraded_execution_rate": None,
            "pause_latency_p95_ms": 30.0,
            "peak_memory_p95_mb": 90.0,
            "live_latency_p95_ms": 20.0,
            "live_policy_skip_rate": 0.5,
            "critical_thermal_skip_rate": 1.0,
        },
        has_degraded_pause_samples=False,
        live_sample_count=6,
    )

    assert release["verdict"] == "research_only"
    assert any("release-conclusive minimum" in reason for reason in release["reasons"])


def test_live_gate_without_gain_stays_no_meaningful_gain_even_if_coverage_limited() -> None:
    release = _build_release_recommendation(
        capabilities={"pauseLocalHybrid": True, "liveHybrid": True, "offload": False},
        anchor_compare={
            "overall": {
                "issue_f1": {"delta": 0.0},
                "primary_action_match_rate": {"delta": 0.0},
                "good_frame_confirmation_rate": {"delta": 0.0},
                "unsupported_claim_rate": {"delta": 0.0},
            }
        },
        utility_metrics={
            "safe_noop_rate": 1.0,
            "ambiguity_borderline_win_rate": 0.0,
            "style_vs_failure_conflict_win_rate": 0.0,
            "pause_neural_value_win_rate": 0.0,
            "hybrid_degraded_fallback_win_rate": 0.0,
            "live_guarded_win_rate": 0.0,
        },
        agreement_metrics={
            "fusion_trace_coverage_rate": 1.0,
            "head_policy_agreement_rate": 1.0,
            "status_trace_consistency_rate": 1.0,
        },
        mobile_metrics={
            "pause_execute_success_rate": 1.0,
            "pause_failure_rate": 0.0,
            "pause_degraded_execution_rate": None,
            "pause_latency_p95_ms": 30.0,
            "peak_memory_p95_mb": 90.0,
            "live_latency_p95_ms": 20.0,
            "live_policy_skip_rate": 0.5,
            "critical_thermal_skip_rate": None,
        },
        has_degraded_pause_samples=False,
        live_sample_count=6,
    )

    assert release["verdict"] == "no_meaningful_gain"
    assert any("critical thermal" in reason for reason in release["reasons"])


def test_regressions_are_not_mislabeled_as_no_meaningful_gain() -> None:
    release = _build_release_recommendation(
        capabilities={"pauseLocalHybrid": True, "liveHybrid": False, "offload": False},
        anchor_compare={
            "overall": {
                "issue_f1": {"delta": -0.2},
                "primary_action_match_rate": {"delta": 0.0},
                "good_frame_confirmation_rate": {"delta": 0.0},
                "unsupported_claim_rate": {"delta": 0.0},
            }
        },
        utility_metrics={
            "safe_noop_rate": 1.0,
            "ambiguity_borderline_win_rate": 0.0,
            "style_vs_failure_conflict_win_rate": 0.0,
            "pause_neural_value_win_rate": 0.0,
            "hybrid_degraded_fallback_win_rate": 0.0,
        },
        agreement_metrics={
            "fusion_trace_coverage_rate": 1.0,
            "head_policy_agreement_rate": 1.0,
            "status_trace_consistency_rate": 1.0,
        },
        mobile_metrics={
            "pause_execute_success_rate": 1.0,
            "pause_failure_rate": 0.0,
            "pause_degraded_execution_rate": None,
            "pause_latency_p95_ms": 30.0,
            "peak_memory_p95_mb": 90.0,
        },
        has_degraded_pause_samples=False,
        live_sample_count=0,
    )

    assert release["verdict"] == "regression_blocked"


def test_live_sequence_frame_artifacts_contribute_to_hybrid_metrics() -> None:
    case = {
        "eval_case_id": "live-sequence-hybrid",
        "eval_set": "live_sequence",
        "case_kind": "live_sequence",
        "bucket_tags": ["weak_signal_fallback"],
        "hybrid_eval": {
            "expectedGainMode": "pause_and_live",
            "expectedFusionBehavior": "reinforce",
            "expectedEligibleHeadIds": ["subject_prominence"],
        },
        "sequenceMeta": {
            "stabilityAnchorFrame": 2,
            "stablePrimaryAction": "move_frame_left",
            "maxFramesToStable": 1,
        },
        "sequence": [
            {
                "frameOrdinal": 1,
                "expectedHintState": "hidden_due_to_motion",
                "jitterExempt": True,
                "countsTowardStability": False,
                "featureSnapshot": {"frameId": "f1", "mode": "live"},
                "sceneSemantics": {"primarySubject": {"kind": "person"}},
            },
            {
                "frameOrdinal": 2,
                "expectedHintState": "visible_action",
                "jitterExempt": False,
                "countsTowardStability": True,
                "featureSnapshot": {"frameId": "f2", "mode": "live"},
                "sceneSemantics": {"primarySubject": {"kind": "person"}},
            },
        ],
    }

    baseline_projection = {
        "evalCaseId": "live-sequence-hybrid",
        "projectionKind": "live_sequence",
        "deterministicOutput": {
            "frame_outputs": [
                {"frameOrdinal": 1, "hintState": "hidden_due_to_motion", "primaryAction": None},
                {"frameOrdinal": 2, "hintState": "hidden_due_to_motion", "primaryAction": None},
            ]
        },
        "finalOutput": {
            "frame_outputs": [
                {"frameOrdinal": 1, "hintState": "hidden_due_to_motion", "primaryAction": None},
                {"frameOrdinal": 2, "hintState": "hidden_due_to_motion", "primaryAction": None},
            ]
        },
    }
    validate_variant_projections([case], {"live-sequence-hybrid": baseline_projection}, {"pauseLocalHybrid": False, "liveHybrid": False, "offload": False})
    anchor_scores = score_model([case], extract_final_outputs({"live-sequence-hybrid": baseline_projection}))

    hybrid_projection = {
        "evalCaseId": "live-sequence-hybrid",
        "projectionKind": "live_sequence",
        "deterministicOutput": baseline_projection["finalOutput"],
        "finalOutput": {
            "frame_outputs": [
                {"frameOrdinal": 1, "hintState": "hidden_due_to_motion", "primaryAction": None},
                {"frameOrdinal": 2, "hintState": "visible_action", "primaryAction": "move_frame_left"},
            ],
            "explainability_trace": {
                "items": [
                    {
                        "id": "obs",
                        "stage": "observation",
                        "evidenceKeys": ["neural.subject_prominence.score"],
                        "dependsOn": [],
                        "links": [],
                    },
                    {
                        "id": "int",
                        "stage": "interpretation",
                        "evidenceKeys": ["neural.subject_prominence.confidence", "rule.hybrid.fusion"],
                        "dependsOn": ["obs"],
                        "links": [],
                    },
                    {
                        "id": "rec",
                        "stage": "recommendation",
                        "evidenceKeys": ["planner.primary_action"],
                        "dependsOn": ["int"],
                        "links": [],
                    },
                ]
            },
        },
        "frameArtifacts": [
            {
                "frameOrdinal": 1,
                "staleDropped": False,
                "inferenceOutcome": {"status": "policySkipped", "mode": "live", "hasSnapshot": False, "failureReason": None},
                "runtimeSample": {
                    "variantId": "hybrid_pause_live_local",
                    "evalCaseId": "live-sequence-hybrid",
                    "frameOrdinal": 1,
                    "mode": "live",
                    "executionProfile": "normal",
                    "thermalTier": "unrestricted",
                    "peakMemoryMB": 80,
                    "staleDropped": False,
                    "inferenceLatencyMs": 10,
                },
                "fusionDecisions": [],
            },
            {
                "frameOrdinal": 2,
                "staleDropped": False,
                "inferenceOutcome": {"status": "executed", "mode": "live", "hasSnapshot": True, "failureReason": None},
                "runtimeSample": {
                    "variantId": "hybrid_pause_live_local",
                    "evalCaseId": "live-sequence-hybrid",
                    "frameOrdinal": 2,
                    "mode": "live",
                    "executionProfile": "normal",
                    "thermalTier": "unrestricted",
                    "peakMemoryMB": 82,
                    "staleDropped": False,
                    "inferenceLatencyMs": 12,
                },
                "neuralSnapshot": {
                    "schemaVersion": "h1",
                    "frameId": "f2",
                    "mode": "live",
                    "capturedAt": "2026-04-22T00:00:00Z",
                    "bundleVersion": "demo",
                    "headOutputs": [
                        {"headId": "subject_prominence", "payload": {"headId": "subject_prominence", "status": "available", "score": 0.8, "confidence": 0.9, "mode": "live", "supportingSignals": []}},
                        {"headId": "background_clutter", "payload": {"headId": "background_clutter", "status": "not_applicable", "score": None, "confidence": 0.0, "mode": "live", "supportingSignals": []}},
                        {"headId": "lighting_quality", "payload": {"headId": "lighting_quality", "status": "not_applicable", "score": None, "confidence": 0.0, "mode": "live", "supportingSignals": []}},
                        {"headId": "face_saliency", "payload": {"headId": "face_saliency", "status": "not_applicable", "score": None, "confidence": 0.0, "mode": "live", "supportingSignals": []}},
                        {"headId": "balance_confidence", "payload": {"headId": "balance_confidence", "status": "not_applicable", "score": None, "confidence": 0.0, "mode": "live", "supportingSignals": []}},
                        {"headId": "depth_separation", "payload": {"headId": "depth_separation", "status": "not_applicable", "score": None, "confidence": 0.0, "mode": "live", "supportingSignals": []}},
                        {"headId": "cinematic_expressiveness", "payload": {"headId": "cinematic_expressiveness", "status": "not_applicable", "score": None, "confidence": 0.0, "mode": "live", "supportingSignals": []}},
                        {"headId": "shot_type_confidence", "payload": {"headId": "shot_type_confidence", "status": "not_applicable", "affinities": [], "confidence": 0.0, "mode": "live", "supportingSignals": []}},
                    ],
                },
                "fusionDecisions": [
                    {
                        "decisionId": "fd1",
                        "targetKind": "issue",
                        "targetId": "live-sequence-hybrid:f2:issue:0",
                        "targetType": "subject_too_close_to_edge",
                        "outcome": "reinforced",
                        "delta": 0.06,
                        "appliedHeadIds": ["subject_prominence"],
                    }
                ],
                "traceItems": [
                    {
                        "id": "obs-f2",
                        "stage": "observation",
                        "evidenceKeys": ["neural.subject_prominence.score"],
                        "dependsOn": [],
                        "links": [],
                    },
                    {
                        "id": "int-f2",
                        "stage": "interpretation",
                        "evidenceKeys": ["neural.subject_prominence.confidence", "rule.hybrid.fusion"],
                        "dependsOn": ["obs-f2"],
                        "links": [],
                    },
                    {
                        "id": "rec-f2",
                        "stage": "recommendation",
                        "evidenceKeys": ["planner.primary_action"],
                        "dependsOn": ["int-f2"],
                        "links": [],
                    },
                ],
            },
        ],
    }
    validate_variant_projections([case], {"live-sequence-hybrid": hybrid_projection}, {"pauseLocalHybrid": False, "liveHybrid": True, "offload": False})
    hybrid_scores = score_model([case], extract_final_outputs({"live-sequence-hybrid": hybrid_projection}))
    compare_report = build_compare_report(
        bundle_id="camera_analysis_hybrid_eval_v1",
        baseline_id="deterministic_only",
        candidate_id="hybrid_pause_live_local",
        baseline_scores=anchor_scores,
        candidate_scores=hybrid_scores,
        manifest={"bundle_id": "camera_analysis_hybrid_eval_v1", "critical_buckets": []},
    )

    report = score_hybrid_variant(
        variant_id="hybrid_pause_live_local",
        parent_variant_id="hybrid_pause_local",
        family="runtime_policy",
        capabilities={"pauseLocalHybrid": False, "liveHybrid": True, "offload": False},
        cases=[case],
        projections_by_case_id={"live-sequence-hybrid": hybrid_projection},
        core_scores=hybrid_scores,
        anchor_core_scores=anchor_scores,
        anchor_compare=compare_report,
    )

    assert report["utility_metrics"]["applied_fusion_rate"] == 1.0
    assert report["agreement_metrics"]["fusion_trace_coverage_rate"] == 1.0
    assert report["agreement_metrics"]["head_policy_agreement_rate"] == 1.0
    assert report["agreement_metrics"]["status_trace_consistency_rate"] == 1.0
    assert report["utility_metrics"]["live_guarded_win_rate"] == 1.0


def test_validate_variant_projections_rejects_live_sequence_artifact_count_mismatch() -> None:
    case = {
        "eval_case_id": "live-seq-bad",
        "case_kind": "live_sequence",
        "sequenceMeta": {
            "stabilityAnchorFrame": 1,
            "stablePrimaryAction": "move_frame_left",
            "maxFramesToStable": 1,
        },
        "sequence": [
            {"frameOrdinal": 1, "expectedHintState": "visible_action", "jitterExempt": False, "countsTowardStability": True}
        ],
    }
    projections = {
        "live-seq-bad": {
            "evalCaseId": "live-seq-bad",
            "projectionKind": "live_sequence",
            "deterministicOutput": {"frame_outputs": [{"frameOrdinal": 1, "hintState": "visible_action", "primaryAction": "move_frame_left"}]},
            "finalOutput": {"frame_outputs": [{"frameOrdinal": 1, "hintState": "visible_action", "primaryAction": "move_frame_left"}]},
            "frameArtifacts": [],
        }
    }

    try:
        validate_variant_projections([case], projections, {"pauseLocalHybrid": False, "liveHybrid": True, "offload": False})
    except ValueError as exc:
        assert "frameArtifacts.count" in str(exc)
    else:
        raise AssertionError("validate_variant_projections must fail when frameArtifacts count mismatches frame_outputs")


def test_validate_variant_projections_rejects_live_sequence_runtime_mismatch() -> None:
    case = {
        "eval_case_id": "live-seq-runtime-mismatch",
        "case_kind": "live_sequence",
        "sequenceMeta": {
            "stabilityAnchorFrame": 1,
            "stablePrimaryAction": "move_frame_left",
            "maxFramesToStable": 1,
        },
        "sequence": [
            {"frameOrdinal": 1, "expectedHintState": "visible_action", "jitterExempt": False, "countsTowardStability": True}
        ],
    }
    projections = {
        "live-seq-runtime-mismatch": {
            "evalCaseId": "live-seq-runtime-mismatch",
            "projectionKind": "live_sequence",
            "deterministicOutput": {"frame_outputs": [{"frameOrdinal": 1, "hintState": "visible_action", "primaryAction": "move_frame_left"}]},
            "finalOutput": {"frame_outputs": [{"frameOrdinal": 1, "hintState": "visible_action", "primaryAction": "move_frame_left"}]},
            "frameArtifacts": [
                {
                    "frameOrdinal": 1,
                    "staleDropped": False,
                    "inferenceOutcome": {"status": "executed", "mode": "live", "hasSnapshot": True, "failureReason": None},
                    "runtimeSample": {
                        "variantId": "hybrid_pause_live_local",
                        "evalCaseId": "live-seq-runtime-mismatch",
                        "frameOrdinal": 99,
                        "mode": "live",
                        "executionProfile": "normal",
                        "thermalTier": "unrestricted",
                        "peakMemoryMB": 80,
                        "staleDropped": False,
                        "inferenceLatencyMs": 10,
                    },
                    "fusionDecisions": [],
                }
            ],
        }
    }

    try:
        validate_variant_projections([case], projections, {"pauseLocalHybrid": False, "liveHybrid": True, "offload": False})
    except ValueError as exc:
        assert "runtimeSample.frameOrdinal" in str(exc)
    else:
        raise AssertionError("validate_variant_projections must fail when frame runtimeSample ordinal mismatches frame artifact ordinal")


def test_validate_variant_projections_rejects_live_sequence_without_stale_dropped_flag() -> None:
    case = {
        "eval_case_id": "live-seq-stale-missing",
        "case_kind": "live_sequence",
        "sequenceMeta": {
            "stabilityAnchorFrame": 1,
            "stablePrimaryAction": "move_frame_left",
            "maxFramesToStable": 1,
        },
        "sequence": [
            {"frameOrdinal": 1, "expectedHintState": "visible_action", "jitterExempt": False, "countsTowardStability": True}
        ],
    }
    projections = {
        "live-seq-stale-missing": {
            "evalCaseId": "live-seq-stale-missing",
            "projectionKind": "live_sequence",
            "deterministicOutput": {"frame_outputs": [{"frameOrdinal": 1, "hintState": "visible_action", "primaryAction": "move_frame_left"}]},
            "finalOutput": {"frame_outputs": [{"frameOrdinal": 1, "hintState": "visible_action", "primaryAction": "move_frame_left"}]},
            "frameArtifacts": [
                {
                    "frameOrdinal": 1,
                    "inferenceOutcome": {"status": "policySkipped", "mode": "live", "hasSnapshot": False, "failureReason": None},
                    "runtimeSample": {
                        "variantId": "hybrid_pause_live_local",
                        "evalCaseId": "live-seq-stale-missing",
                        "frameOrdinal": 1,
                        "mode": "live",
                        "executionProfile": "normal",
                        "thermalTier": "unrestricted",
                        "peakMemoryMB": 80,
                        "staleDropped": False,
                        "inferenceLatencyMs": 10,
                    },
                    "fusionDecisions": [],
                }
            ],
        }
    }

    try:
        validate_variant_projections([case], projections, {"pauseLocalHybrid": False, "liveHybrid": True, "offload": False})
    except ValueError as exc:
        assert "staleDropped" in str(exc)
    else:
        raise AssertionError("validate_variant_projections must fail when frame artifact omits staleDropped")


def test_validate_variant_projections_rejects_offload_response_applied_mismatch() -> None:
    case = _pause_case(
        "offload-mismatch",
        {
            "expectedGainMode": "pause_only",
            "offloadTierAllowed": "structured_only",
        },
        required_issues=["subject_too_close_to_edge"],
        allowed_actions=["move_frame_left"],
    )
    local_output = _make_output("offload-mismatch", "needs_fix", ["subject_too_close_to_edge"], "move_frame_left", "Edge pressure")
    augmented_output = _make_output("offload-mismatch", "good", [], "leave_frame_as_is", "Looks good")
    projections = {
        "offload-mismatch": {
            "evalCaseId": "offload-mismatch",
            "projectionKind": "single_frame",
            "deterministicOutput": local_output,
            "finalOutput": local_output,
            "localPhaseOutput": local_output,
            "augmentedOutput": augmented_output,
            "offloadOutcome": {
                "status": "completed",
                "tier": "structured_only",
                "trigger": "ambiguous_local_case",
                "failureKind": "none",
                "responseApplied": True,
                "boundarySafe": True,
                "localFirstPublished": True,
            },
            "inferenceOutcome": {"status": "disabled", "mode": "pause", "hasSnapshot": False, "failureReason": None},
        }
    }

    try:
        validate_variant_projections([case], projections, {"pauseLocalHybrid": False, "liveHybrid": False, "offload": True})
    except ValueError as exc:
        assert "score-equivalent augmentedOutput" in str(exc)
    else:
        raise AssertionError("validate_variant_projections must fail when completed offload claims responseApplied but finalOutput does not match augmentedOutput")


def test_validate_variant_projections_rejects_non_local_first_offload() -> None:
    case = _pause_case(
        "offload-not-local-first",
        {
            "expectedGainMode": "pause_only",
            "offloadTierAllowed": "structured_only",
        },
        required_issues=["subject_too_close_to_edge"],
        allowed_actions=["move_frame_left"],
    )
    local_output = _make_output(
        "offload-not-local-first",
        "needs_fix",
        ["subject_too_close_to_edge"],
        "move_frame_left",
        "Edge pressure",
    )
    projections = {
        "offload-not-local-first": {
            "evalCaseId": "offload-not-local-first",
            "projectionKind": "single_frame",
            "deterministicOutput": local_output,
            "finalOutput": local_output,
            "localPhaseOutput": local_output,
            "offloadOutcome": {
                "status": "failed",
                "tier": "structured_only",
                "trigger": "ambiguous_local_case",
                "failureKind": "timeout",
                "responseApplied": False,
                "boundarySafe": True,
                "localFirstPublished": False,
            },
            "inferenceOutcome": {"status": "disabled", "mode": "pause", "hasSnapshot": False, "failureReason": None},
        }
    }

    try:
        validate_variant_projections([case], projections, {"pauseLocalHybrid": False, "liveHybrid": False, "offload": True})
    except ValueError as exc:
        assert "localFirstPublished" in str(exc)
    else:
        raise AssertionError("validate_variant_projections must fail when offload path violates local-first contract")


def test_validate_variant_projections_rejects_failed_offload_without_failure_kind() -> None:
    case = _pause_case(
        "offload-failure-kind",
        {
            "expectedGainMode": "pause_only",
            "offloadTierAllowed": "structured_only",
        },
        required_issues=["subject_too_close_to_edge"],
        allowed_actions=["move_frame_left"],
    )
    local_output = _make_output(
        "offload-failure-kind",
        "needs_fix",
        ["subject_too_close_to_edge"],
        "move_frame_left",
        "Edge pressure",
    )
    projections = {
        "offload-failure-kind": {
            "evalCaseId": "offload-failure-kind",
            "projectionKind": "single_frame",
            "deterministicOutput": local_output,
            "finalOutput": local_output,
            "localPhaseOutput": local_output,
            "offloadOutcome": {
                "status": "failed",
                "tier": "structured_only",
                "trigger": "ambiguous_local_case",
                "failureKind": "none",
                "responseApplied": False,
                "boundarySafe": True,
                "localFirstPublished": True,
            },
            "inferenceOutcome": {"status": "disabled", "mode": "pause", "hasSnapshot": False, "failureReason": None},
        }
    }

    try:
        validate_variant_projections([case], projections, {"pauseLocalHybrid": False, "liveHybrid": False, "offload": True})
    except ValueError as exc:
        assert "failed offload" in str(exc)
    else:
        raise AssertionError("validate_variant_projections must fail when failed offload uses non-failure failureKind")
