from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path


def test_run_hybrid_eval_generates_required_artifacts(tmp_path: Path) -> None:
    eval_dir = Path(__file__).resolve().parents[1]
    bundle_dir = tmp_path / "bundle"
    bundle_dir.mkdir(parents=True, exist_ok=True)

    manifest = {
        "bundle_id": "camera_analysis_hybrid_eval_v1",
        "critical_buckets": [],
    }
    (bundle_dir / "eval_bundle_manifest.json").write_text(json.dumps(manifest) + "\n", encoding="utf-8")

    cases = [
        {
            "eval_case_id": "case-borderline",
            "eval_set": "pause_curated",
            "case_kind": "single_frame_pause",
            "bucket_tags": ["needs_fix"],
            "input": {
                "feature_snapshot": {"frameId": "case-borderline", "mode": "pause"},
                "scene_semantics": {"primarySubject": {"kind": "person"}},
            },
            "hybrid_eval": {
                "ambiguityBucket": "borderline",
                "conflictBucket": "style_vs_failure",
                "expectedGainMode": "pause_only",
                "expectedEligibleHeadIds": ["subject_prominence"],
                "expectedFusionBehavior": "reinforce",
            },
            "gold_expectations": {
                "verdict": "needs_fix",
                "required_issues": ["subject_too_close_to_edge"],
                "forbidden_issues": [],
                "required_strengths": [],
                "forbidden_strengths": [],
                "allowed_primary_actions": ["move_frame_left"],
                "required_fix_types": ["reframing"],
                "fallback_expected": False,
                "good_frame_policy": "must_not_confirm_good_frame",
                "explainability": {
                    "required_issue_links": ["subject_too_close_to_edge"],
                    "require_observation_interpretation_recommendation_chain": True,
                    "summary_must_reference_any": ["edge"],
                },
            },
        },
        {
            "eval_case_id": "case-degraded",
            "eval_set": "pause_curated",
            "case_kind": "single_frame_pause",
            "bucket_tags": ["good_frame_do_not_overcoach", "weak_signal_fallback"],
            "input": {
                "feature_snapshot": {"frameId": "case-degraded", "mode": "pause"},
                "scene_semantics": {"primarySubject": {"kind": "person"}},
            },
            "hybrid_eval": {
                "ambiguityBucket": "clear",
                "conflictBucket": "weak_signal",
                "expectedGainMode": "pause_only",
                "expectedEligibleHeadIds": ["subject_prominence"],
                "expectedFusionBehavior": "noop",
            },
            "gold_expectations": {
                "verdict": "good",
                "required_issues": [],
                "forbidden_issues": ["subject_too_close_to_edge"],
                "required_strengths": [],
                "forbidden_strengths": [],
                "allowed_primary_actions": ["leave_frame_as_is"],
                "required_fix_types": [],
                "fallback_expected": False,
                "good_frame_policy": "must_confirm_good_frame",
                "explainability": {
                    "required_issue_links": [],
                    "require_observation_interpretation_recommendation_chain": True,
                    "summary_must_reference_any": ["good"],
                },
            },
        },
    ]
    with (bundle_dir / "golden_cases.jsonl").open("w", encoding="utf-8") as handle:
        for row in cases:
            handle.write(json.dumps(row) + "\n")

    deterministic_outputs = [
        {
            "evalCaseId": "case-borderline",
            "projectionKind": "single_frame",
            "deterministicOutput": {
                "critique_report": {"verdict": "good", "issues": [], "strengths": [], "summary": {"shortVerdict": "Looks good", "whyGood": "Looks good", "whyProblematic": None}, "fallbackUsed": False},
                "recommendation_plan": {"mode": "pause", "primaryAction": None, "secondaryActions": [], "noChangeRationale": None},
                "explainability_trace": {"items": []},
                "live_hint_projection": {"hintState": "hidden", "primaryAction": None},
            },
            "finalOutput": {
                "critique_report": {"verdict": "good", "issues": [], "strengths": [], "summary": {"shortVerdict": "Looks good", "whyGood": "Looks good", "whyProblematic": None}, "fallbackUsed": False},
                "recommendation_plan": {"mode": "pause", "primaryAction": None, "secondaryActions": [], "noChangeRationale": None},
                "explainability_trace": {"items": []},
                "live_hint_projection": {"hintState": "hidden", "primaryAction": None},
            },
            "localPhaseOutput": {
                "critique_report": {"verdict": "good", "issues": [], "strengths": [], "summary": {"shortVerdict": "Looks good", "whyGood": "Looks good", "whyProblematic": None}, "fallbackUsed": False},
                "recommendation_plan": {"mode": "pause", "primaryAction": None, "secondaryActions": [], "noChangeRationale": None},
                "explainability_trace": {"items": []},
                "live_hint_projection": {"hintState": "hidden", "primaryAction": None},
            },
            "fusionDecisions": [],
            "inferenceOutcome": {"status": "disabled", "mode": "pause", "hasSnapshot": False, "failureReason": None},
        },
        {
            "evalCaseId": "case-degraded",
            "projectionKind": "single_frame",
            "deterministicOutput": {
                "critique_report": {"verdict": "good", "issues": [], "strengths": [], "summary": {"shortVerdict": "Good frame", "whyGood": "Good frame", "whyProblematic": None}, "fallbackUsed": False},
                "recommendation_plan": {"mode": "pause", "primaryAction": {"id": "a1", "actionType": "leave_frame_as_is", "linkedIssueIds": []}, "secondaryActions": [], "noChangeRationale": "No changes needed."},
                "explainability_trace": {"items": []},
                "live_hint_projection": {"hintState": "hidden", "primaryAction": None},
            },
            "finalOutput": {
                "critique_report": {"verdict": "good", "issues": [], "strengths": [], "summary": {"shortVerdict": "Good frame", "whyGood": "Good frame", "whyProblematic": None}, "fallbackUsed": False},
                "recommendation_plan": {"mode": "pause", "primaryAction": {"id": "a1", "actionType": "leave_frame_as_is", "linkedIssueIds": []}, "secondaryActions": [], "noChangeRationale": "No changes needed."},
                "explainability_trace": {"items": []},
                "live_hint_projection": {"hintState": "hidden", "primaryAction": None},
            },
            "localPhaseOutput": {
                "critique_report": {"verdict": "good", "issues": [], "strengths": [], "summary": {"shortVerdict": "Good frame", "whyGood": "Good frame", "whyProblematic": None}, "fallbackUsed": False},
                "recommendation_plan": {"mode": "pause", "primaryAction": {"id": "a1", "actionType": "leave_frame_as_is", "linkedIssueIds": []}, "secondaryActions": [], "noChangeRationale": "No changes needed."},
                "explainability_trace": {"items": []},
                "live_hint_projection": {"hintState": "hidden", "primaryAction": None},
            },
            "fusionDecisions": [],
            "inferenceOutcome": {"status": "disabled", "mode": "pause", "hasSnapshot": False, "failureReason": None},
        },
    ]

    hybrid_outputs = [
        {
            "evalCaseId": "case-borderline",
            "projectionKind": "single_frame",
            "deterministicOutput": deterministic_outputs[0]["finalOutput"],
            "finalOutput": {
                "critique_report": {
                    "verdict": "needs_fix",
                    "issues": [{"id": "i1", "type": "subject_too_close_to_edge", "severity": 0.8, "suggestedFixTypes": ["reframing"], "evidence": [{"key": "snapshot.composition.horizontalOffset"}]}],
                    "strengths": [],
                    "summary": {"shortVerdict": "Edge pressure", "whyGood": None, "whyProblematic": "Edge pressure hurts the shot"},
                    "fallbackUsed": False,
                },
                "recommendation_plan": {"mode": "pause", "primaryAction": {"id": "a1", "actionType": "move_frame_left", "linkedIssueIds": ["i1"]}, "secondaryActions": [], "noChangeRationale": None},
                "explainability_trace": {"items": [
                    {"id": "obs", "stage": "observation", "evidenceKeys": ["neural.subject_prominence.score"], "dependsOn": [], "links": []},
                    {"id": "int", "stage": "interpretation", "evidenceKeys": ["neural.subject_prominence.confidence", "rule.hybrid.fusion"], "dependsOn": ["obs"], "links": [{"kind": "issue", "refId": "i1"}]},
                    {"id": "rec", "stage": "recommendation", "evidenceKeys": ["planner.primary_action"], "dependsOn": ["int"], "links": [{"kind": "action", "refId": "a1"}]}
                ]},
                "live_hint_projection": {"hintState": "hidden", "primaryAction": None},
            },
            "localPhaseOutput": {
                "critique_report": {
                    "verdict": "needs_fix",
                    "issues": [{"id": "i1", "type": "subject_too_close_to_edge", "severity": 0.8, "suggestedFixTypes": ["reframing"], "evidence": [{"key": "snapshot.composition.horizontalOffset"}]}],
                    "strengths": [],
                    "summary": {"shortVerdict": "Edge pressure", "whyGood": None, "whyProblematic": "Edge pressure hurts the shot"},
                    "fallbackUsed": False,
                },
                "recommendation_plan": {"mode": "pause", "primaryAction": {"id": "a1", "actionType": "move_frame_left", "linkedIssueIds": ["i1"]}, "secondaryActions": [], "noChangeRationale": None},
                "explainability_trace": {"items": [
                    {"id": "obs", "stage": "observation", "evidenceKeys": ["neural.subject_prominence.score"], "dependsOn": [], "links": []},
                    {"id": "int", "stage": "interpretation", "evidenceKeys": ["neural.subject_prominence.confidence", "rule.hybrid.fusion"], "dependsOn": ["obs"], "links": [{"kind": "issue", "refId": "i1"}]},
                    {"id": "rec", "stage": "recommendation", "evidenceKeys": ["planner.primary_action"], "dependsOn": ["int"], "links": [{"kind": "action", "refId": "a1"}]}
                ]},
                "live_hint_projection": {"hintState": "hidden", "primaryAction": None},
            },
            "neuralSnapshot": {
                "schemaVersion": "h1",
                "frameId": "case-borderline",
                "mode": "pause",
                "capturedAt": "2026-04-22T00:00:00Z",
                "bundleVersion": "demo",
                "headOutputs": [
                    {"headId": "subject_prominence", "payload": {"headId": "subject_prominence", "status": "available", "score": 0.7, "confidence": 0.8, "mode": "pause", "supportingSignals": []}},
                    {"headId": "background_clutter", "payload": {"headId": "background_clutter", "status": "not_applicable", "score": None, "confidence": 0.0, "mode": "pause", "supportingSignals": []}},
                    {"headId": "lighting_quality", "payload": {"headId": "lighting_quality", "status": "not_applicable", "score": None, "confidence": 0.0, "mode": "pause", "supportingSignals": []}},
                    {"headId": "face_saliency", "payload": {"headId": "face_saliency", "status": "not_applicable", "score": None, "confidence": 0.0, "mode": "pause", "supportingSignals": []}},
                    {"headId": "balance_confidence", "payload": {"headId": "balance_confidence", "status": "not_applicable", "score": None, "confidence": 0.0, "mode": "pause", "supportingSignals": []}},
                    {"headId": "depth_separation", "payload": {"headId": "depth_separation", "status": "not_applicable", "score": None, "confidence": 0.0, "mode": "pause", "supportingSignals": []}},
                    {"headId": "cinematic_expressiveness", "payload": {"headId": "cinematic_expressiveness", "status": "not_applicable", "score": None, "confidence": 0.0, "mode": "pause", "supportingSignals": []}},
                    {"headId": "shot_type_confidence", "payload": {"headId": "shot_type_confidence", "status": "not_applicable", "affinities": [], "confidence": 0.0, "mode": "pause", "supportingSignals": []}}
                ]
            },
            "fusionDecisions": [{"decisionId": "d1", "targetKind": "issue", "targetId": "i1", "targetType": "subject_too_close_to_edge", "outcome": "reinforced", "delta": 0.07, "appliedHeadIds": ["subject_prominence"]}],
            "inferenceOutcome": {"status": "executed", "mode": "pause", "hasSnapshot": True, "failureReason": None},
            "runtimeSample": {"variantId": "hybrid_pause_local", "evalCaseId": "case-borderline", "mode": "pause", "executionProfile": "normal", "thermalTier": "unrestricted", "peakMemoryMB": 80, "staleDropped": False, "inferenceLatencyMs": 28}
        },
        {
            "evalCaseId": "case-degraded",
            "projectionKind": "single_frame",
            "deterministicOutput": deterministic_outputs[1]["finalOutput"],
            "finalOutput": deterministic_outputs[1]["finalOutput"],
            "localPhaseOutput": deterministic_outputs[1]["finalOutput"],
            "neuralSnapshot": {
                "schemaVersion": "h1",
                "frameId": "case-degraded",
                "mode": "pause",
                "capturedAt": "2026-04-22T00:00:00Z",
                "bundleVersion": "demo",
                "headOutputs": [
                    {"headId": "subject_prominence", "payload": {"headId": "subject_prominence", "status": "available", "score": 0.7, "confidence": 0.8, "mode": "pause", "supportingSignals": []}},
                    {"headId": "background_clutter", "payload": {"headId": "background_clutter", "status": "not_applicable", "score": None, "confidence": 0.0, "mode": "pause", "supportingSignals": []}},
                    {"headId": "lighting_quality", "payload": {"headId": "lighting_quality", "status": "not_applicable", "score": None, "confidence": 0.0, "mode": "pause", "supportingSignals": []}},
                    {"headId": "face_saliency", "payload": {"headId": "face_saliency", "status": "not_applicable", "score": None, "confidence": 0.0, "mode": "pause", "supportingSignals": []}},
                    {"headId": "balance_confidence", "payload": {"headId": "balance_confidence", "status": "not_applicable", "score": None, "confidence": 0.0, "mode": "pause", "supportingSignals": []}},
                    {"headId": "depth_separation", "payload": {"headId": "depth_separation", "status": "not_applicable", "score": None, "confidence": 0.0, "mode": "pause", "supportingSignals": []}},
                    {"headId": "cinematic_expressiveness", "payload": {"headId": "cinematic_expressiveness", "status": "not_applicable", "score": None, "confidence": 0.0, "mode": "pause", "supportingSignals": []}},
                    {"headId": "shot_type_confidence", "payload": {"headId": "shot_type_confidence", "status": "not_applicable", "affinities": [], "confidence": 0.0, "mode": "pause", "supportingSignals": []}}
                ]
            },
            "fusionDecisions": [],
            "inferenceOutcome": {"status": "executed", "mode": "pause", "hasSnapshot": True, "failureReason": None},
            "runtimeSample": {"variantId": "hybrid_pause_local", "evalCaseId": "case-degraded", "mode": "pause", "executionProfile": "degraded_pause_profile", "thermalTier": "constrained", "peakMemoryMB": 90, "staleDropped": False, "inferenceLatencyMs": 35}
        }
    ]

    deterministic_path = tmp_path / "deterministic_outputs.jsonl"
    hybrid_path = tmp_path / "hybrid_outputs.jsonl"
    deterministic_path.write_text("\n".join(json.dumps(row) for row in deterministic_outputs) + "\n", encoding="utf-8")
    hybrid_path.write_text("\n".join(json.dumps(row) for row in hybrid_outputs) + "\n", encoding="utf-8")

    matrix = {
        "anchorVariantId": "deterministic_only",
        "variants": [
            {
                "variantId": "deterministic_only",
                "source": {"kind": "jsonl", "path": str(deterministic_path)},
                "capabilities": {"pauseLocalHybrid": False, "liveHybrid": False, "offload": False},
            },
            {
                "variantId": "hybrid_pause_local",
                "parentVariantId": "deterministic_only",
                "family": "runtime_policy",
                "source": {"kind": "jsonl", "path": str(hybrid_path)},
                "capabilities": {"pauseLocalHybrid": True, "liveHybrid": False, "offload": False},
            },
        ],
    }
    matrix_path = tmp_path / "variant_matrix.json"
    matrix_path.write_text(json.dumps(matrix) + "\n", encoding="utf-8")

    script = eval_dir / "run_hybrid_eval.py"
    cmd = [
        sys.executable,
        str(script),
        "--bundle",
        str(bundle_dir),
        "--matrix",
        str(matrix_path),
        "--output",
        str(tmp_path / "out"),
    ]
    subprocess.run(cmd, check=True)

    out_dir = tmp_path / "out"
    for name in (
        "hybrid_metrics.json",
        "explainability_agreement.json",
        "mobile_system_metrics.json",
        "ablation_summary.json",
        "hybrid_eval_summary.md",
    ):
        assert (out_dir / name).exists(), f"missing {name}"

    summary = (out_dir / "hybrid_eval_summary.md").read_text(encoding="utf-8")
    assert "hybrid_pause_local" in summary
    assert (out_dir / "pairwise_compare" / "deterministic_only__vs__hybrid_pause_local.json").exists()
    assert (out_dir / "variant_outputs" / "hybrid_pause_local.jsonl").exists()
