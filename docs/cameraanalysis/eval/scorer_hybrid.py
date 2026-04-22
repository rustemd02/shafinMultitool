#!/usr/bin/env python3
"""Hybrid metrics and release gates for PR-H14."""

from __future__ import annotations

import math
from typing import Any, Dict, List, Optional, Sequence, Set, Tuple

from compare import CASE_WINNER_ORDER
from scorer import score_case


POLICY_HEADS: Dict[str, Tuple[str, ...]] = {
    "pause": (
        "subject_prominence",
        "background_clutter",
        "lighting_quality",
        "face_saliency",
        "balance_confidence",
        "depth_separation",
        "shot_type_confidence",
    ),
    "live": (
        "subject_prominence",
        "background_clutter",
        "lighting_quality",
        "face_saliency",
    ),
}

DEGRADED_ACTIVE_HEADS: Set[str] = set(POLICY_HEADS["live"])
PERSON_CENTRIC_SUBJECTS = {"face", "person", "group"}
EFFECTIVE_FUSION_OUTCOMES = {"reinforced", "softened"}
HYBRID_PAUSE_BUCKETS = (
    "ambiguity_borderline",
    "style_vs_failure_conflict",
    "pause_neural_value",
    "hybrid_degraded_fallback",
)
SUPPORTING_SIGNAL_ORDER: Tuple[str, ...] = (
    "subject_scale",
    "subject_attention_pull",
    "subject_readability",
    "object_density",
    "texture_noise",
    "attention_competition",
    "subject_exposure_readability",
    "facial_light_support",
    "tonal_structure",
    "face_attention_pull",
    "eye_region_visibility",
    "facial_anchor_strength",
    "frame_balance",
    "subject_placement_stability",
    "negative_space_fit",
    "foreground_background_split",
    "subject_background_contrast",
    "layering_clarity",
    "stylistic_intent",
    "production_value_residual",
    "visual_harmony_residual",
)
SUPPORTING_SIGNAL_INDEX = {tag: idx for idx, tag in enumerate(SUPPORTING_SIGNAL_ORDER)}
HEAD_SUPPORTING_TAGS: Dict[str, Set[str]] = {
    "subject_prominence": {"subject_scale", "subject_attention_pull", "subject_readability"},
    "background_clutter": {"object_density", "texture_noise", "attention_competition"},
    "lighting_quality": {"subject_exposure_readability", "facial_light_support", "tonal_structure"},
    "face_saliency": {"face_attention_pull", "eye_region_visibility", "facial_anchor_strength", "facial_light_support"},
    "balance_confidence": {"frame_balance", "subject_placement_stability", "negative_space_fit"},
    "depth_separation": {"foreground_background_split", "subject_background_contrast", "layering_clarity"},
    "cinematic_expressiveness": {"stylistic_intent", "production_value_residual", "visual_harmony_residual"},
    "shot_type_confidence": set(),
}
EXPECTED_FUSION_BEHAVIORS = {"noop", "reinforce", "soften", "mixed"}
OFFLOAD_TIERS = {"none", "structured_only", "redacted_visual"}
OFFLOAD_STATUSES = {"disabled", "notTriggered", "blocked", "completed", "failed"}
OFFLOAD_FAILURE_KINDS = {
    "none",
    "timeout",
    "transport_error",
    "policy_refused",
    "capability_mismatch",
    "validation_failed",
    "unknown",
}
VISUAL_REPLAY_TRIGGERS = {
    "explicit_user_request",
    "ambiguous_local_case",
    "fusion_disagreement_probe",
    "partial_local_failure",
    "eval_sampling",
}
ALLOWED_HEADS_BY_TARGET: Dict[str, Set[str]] = {
    "subject_too_close_to_edge": {"face_saliency", "subject_prominence", "balance_confidence", "shot_type_confidence"},
    "subject_not_prominent_enough": {"subject_prominence", "background_clutter", "face_saliency", "depth_separation"},
    "background_competes_with_subject": {"background_clutter", "subject_prominence", "depth_separation"},
    "insufficient_look_space": {"face_saliency", "subject_prominence", "balance_confidence", "shot_type_confidence"},
    "backlight_hides_subject": {"lighting_quality", "face_saliency", "depth_separation", "shot_type_confidence"},
    "scene_has_no_clear_focus": {"subject_prominence", "background_clutter", "balance_confidence"},
    "frame_visually_overloaded": {"background_clutter", "subject_prominence", "balance_confidence"},
    "horizon_distracts": {"balance_confidence"},
    "good_subject_isolation": {"subject_prominence", "background_clutter", "depth_separation"},
    "good_light_emphasis": {"lighting_quality", "face_saliency", "depth_separation"},
    "clear_focus_hierarchy": {"subject_prominence", "background_clutter", "balance_confidence"},
    "stable_horizon_supports_scene": {"balance_confidence"},
    "balanced_composition_for_scene": {"balance_confidence", "face_saliency", "shot_type_confidence"},
}


def _pick(mapping: Dict[str, Any], *keys: str, default: Any = None) -> Any:
    for key in keys:
        if isinstance(mapping, dict) and key in mapping:
            return mapping[key]
    return default


def _round_metric(value: Optional[float]) -> Optional[float]:
    if value is None:
        return None
    return round(float(value), 6)


def _safe_div(num: float, den: float) -> Optional[float]:
    if den == 0:
        return None
    return num / den


def _mean(values: Sequence[float]) -> Optional[float]:
    if not values:
        return None
    return sum(values) / float(len(values))


def _percentile(values: Sequence[float], percentile: float) -> Optional[float]:
    if not values:
        return None
    ordered = sorted(float(value) for value in values)
    if len(ordered) == 1:
        return ordered[0]
    position = (len(ordered) - 1) * percentile
    low = int(math.floor(position))
    high = int(math.ceil(position))
    if low == high:
        return ordered[low]
    lower_value = ordered[low]
    upper_value = ordered[high]
    weight = position - low
    return lower_value + (upper_value - lower_value) * weight


def _mode_for_case(case: Dict[str, Any]) -> str:
    if case.get("case_kind") in {"single_frame_live", "live_sequence"}:
        return "live"
    return "pause"


def _winner_by_priority(
    baseline_metrics: Dict[str, Any],
    candidate_metrics: Dict[str, Any],
    order: Sequence[str] = CASE_WINNER_ORDER,
) -> Tuple[str, Optional[str]]:
    for key in order:
        baseline = baseline_metrics.get(key)
        candidate = candidate_metrics.get(key)
        if not isinstance(baseline, (int, float)) or not isinstance(candidate, (int, float)):
            continue
        if abs(float(candidate) - float(baseline)) <= 1e-9:
            continue
        return ("candidate", key) if float(candidate) > float(baseline) else ("baseline", key)
    return "tie", None


def _has_metric_regression(
    baseline_metrics: Dict[str, Any],
    candidate_metrics: Dict[str, Any],
    metric_names: Sequence[str] = CASE_WINNER_ORDER,
) -> bool:
    for name in metric_names:
        baseline = baseline_metrics.get(name)
        candidate = candidate_metrics.get(name)
        if isinstance(baseline, (int, float)) and isinstance(candidate, (int, float)):
            if float(candidate) + 1e-9 < float(baseline):
                return True
    return False


def _winner_for_live_guarded(
    baseline_metrics: Dict[str, Any],
    candidate_metrics: Dict[str, Any],
) -> Tuple[str, Optional[str]]:
    for key in ("hint_visibility_policy_accuracy",):
        baseline = baseline_metrics.get(key)
        candidate = candidate_metrics.get(key)
        if not isinstance(baseline, (int, float)) or not isinstance(candidate, (int, float)):
            continue
        if abs(float(candidate) - float(baseline)) <= 1e-9:
            continue
        return ("candidate", key) if float(candidate) > float(baseline) else ("baseline", key)

    for key in ("frames_to_stable_correct_hint", "hint_jitter_rate", "unsupported_claim_rate"):
        baseline = baseline_metrics.get(key)
        candidate = candidate_metrics.get(key)
        if not isinstance(baseline, (int, float)) or not isinstance(candidate, (int, float)):
            continue
        if abs(float(candidate) - float(baseline)) <= 1e-9:
            continue
        return ("candidate", key) if float(candidate) < float(baseline) else ("baseline", key)

    return "tie", None


def _normalize_case_id(row: Dict[str, Any]) -> str:
    case_id = _pick(row, "evalCaseId", "eval_case_id", default=None)
    if not isinstance(case_id, str) or not case_id:
        raise ValueError(f"variant output row is missing evalCaseId/eval_case_id: {row!r}")
    return case_id


def _head_payload_map(snapshot: Optional[Dict[str, Any]]) -> Dict[str, Dict[str, Any]]:
    if not isinstance(snapshot, dict):
        return {}
    entries = _pick(snapshot, "headOutputs", "head_outputs", default=[]) or []
    out: Dict[str, Dict[str, Any]] = {}
    for entry in entries:
        if not isinstance(entry, dict):
            continue
        head_id = _pick(entry, "headId", "head_id", default=None)
        payload = _pick(entry, "payload", default=None)
        if isinstance(head_id, str) and isinstance(payload, dict):
            out[head_id] = payload
    return out


def _effective_fusion_decisions(decisions: Sequence[Dict[str, Any]]) -> List[Dict[str, Any]]:
    out: List[Dict[str, Any]] = []
    for decision in decisions:
        if not isinstance(decision, dict):
            continue
        outcome = _pick(decision, "outcome", default=None)
        delta = _pick(decision, "delta", default=None)
        if outcome in EFFECTIVE_FUSION_OUTCOMES and isinstance(delta, (int, float)) and abs(float(delta)) >= 0.03:
            out.append(decision)
    return out


def _trace_items(output: Optional[Dict[str, Any]]) -> List[Dict[str, Any]]:
    if not isinstance(output, dict):
        return []
    trace = _pick(output, "explainability_trace", "explainabilityTrace", default={}) or {}
    items = _pick(trace, "items", default=[]) or []
    return [item for item in items if isinstance(item, dict)]


def _frame_outputs(output: Optional[Dict[str, Any]]) -> List[Dict[str, Any]]:
    if not isinstance(output, dict):
        return []
    items = _pick(output, "frame_outputs", "sequence_outputs", default=[]) or []
    return [item for item in items if isinstance(item, dict)]


def _evidence_keys(item: Dict[str, Any]) -> List[str]:
    keys = _pick(item, "evidenceKeys", "evidence_keys", default=[]) or []
    return [key for key in keys if isinstance(key, str)]


def _score_equivalent(case: Dict[str, Any], lhs: Optional[Dict[str, Any]], rhs: Optional[Dict[str, Any]]) -> bool:
    if not isinstance(lhs, dict) or not isinstance(rhs, dict):
        return False
    return score_case(case, lhs).get("metrics", {}) == score_case(case, rhs).get("metrics", {})


def _artifact_trace_items(
    artifact: Dict[str, Any],
    fallback_output: Optional[Dict[str, Any]] = None,
) -> List[Dict[str, Any]]:
    explicit = _pick(artifact, "traceItems", "trace_items", default=None)
    if isinstance(explicit, list):
        return [item for item in explicit if isinstance(item, dict)]
    return _trace_items(fallback_output)


def _decision_policy_ok(
    decision: Dict[str, Any],
    mode: str,
    eligible_heads: Set[str],
    head_map: Dict[str, Dict[str, Any]],
) -> bool:
    target_type = _pick(decision, "targetType", "target_type", default=None)
    allowed_heads = ALLOWED_HEADS_BY_TARGET.get(str(target_type), set())
    applied_head_ids = [
        head_id
        for head_id in (_pick(decision, "appliedHeadIds", "applied_head_ids", default=[]) or [])
        if isinstance(head_id, str)
    ]
    for head_id in applied_head_ids:
        if head_id not in allowed_heads:
            return False
        if head_id not in POLICY_HEADS[mode]:
            return False
        if head_id not in eligible_heads:
            return False
        if _pick(head_map.get(head_id, {}), "status", default=None) != "available":
            return False
    return True


def _supporting_signal_contract_score(head_map: Dict[str, Dict[str, Any]]) -> Optional[float]:
    available_head_validity: List[float] = []
    for head_id, payload in head_map.items():
        if _pick(payload, "status", default=None) != "available":
            continue
        tags = [
            tag
            for tag in (_pick(payload, "supportingSignals", "supporting_signals", default=[]) or [])
            if isinstance(tag, str)
        ]
        allowed_tags = HEAD_SUPPORTING_TAGS.get(head_id, set())
        valid = True
        if head_id == "shot_type_confidence" and tags:
            valid = False
        if len(tags) > 2:
            valid = False
        if any(tag not in allowed_tags for tag in tags):
            valid = False
        if tags != sorted(tags, key=lambda value: SUPPORTING_SIGNAL_INDEX.get(value, 999)):
            valid = False
        available_head_validity.append(1.0 if valid else 0.0)
    return _mean(available_head_validity)


def _hybrid_buckets_for_case(case: Dict[str, Any]) -> List[str]:
    hybrid_eval = case.get("hybrid_eval", {})
    bucket_tags = set(case.get("bucket_tags", []) or [])
    buckets: List[str] = []

    ambiguity = hybrid_eval.get("ambiguityBucket")
    if ambiguity in {"borderline", "hard_ambiguous"}:
        buckets.append("ambiguity_borderline")

    if hybrid_eval.get("conflictBucket") == "style_vs_failure":
        buckets.append("style_vs_failure_conflict")

    if hybrid_eval.get("expectedGainMode") in {"pause_only", "pause_and_live"}:
        buckets.append("pause_neural_value")

    if hybrid_eval.get("expectedGainMode") == "pause_and_live":
        buckets.append("live_guarded_value")

    if hybrid_eval.get("conflictBucket") == "weak_signal" or "weak_signal_fallback" in bucket_tags:
        buckets.append("hybrid_degraded_fallback")

    return buckets


def _scene_semantics(case: Dict[str, Any]) -> Dict[str, Any]:
    payload = case.get("input", {})
    return _pick(payload, "scene_semantics", "sceneSemantics", default={}) or {}


def _semantic_applicable(case: Dict[str, Any], head_id: str) -> bool:
    mode = _mode_for_case(case)
    if head_id in {"balance_confidence", "depth_separation", "shot_type_confidence"} and mode == "live":
        return False
    if head_id != "face_saliency":
        return True
    semantics = _scene_semantics(case)
    primary = _pick(semantics, "primarySubject", "primary_subject", default={}) or {}
    kind = _pick(primary, "kind", default=None)
    return kind in PERSON_CENTRIC_SUBJECTS


def _effective_eligible_heads(
    case: Dict[str, Any],
    execution_profile: Optional[str],
) -> Set[str]:
    mode = _mode_for_case(case)
    heads = set(POLICY_HEADS[mode])
    heads = {head_id for head_id in heads if _semantic_applicable(case, head_id)}
    if execution_profile == "degraded_pause_profile":
        heads &= DEGRADED_ACTIVE_HEADS
    hybrid_eval = case.get("hybrid_eval", {})
    expected = hybrid_eval.get("expectedEligibleHeadIds")
    if isinstance(expected, list) and expected:
        heads &= {head_id for head_id in expected if isinstance(head_id, str)}
    return heads


def _realized_fusion_behavior(decisions: Sequence[Dict[str, Any]]) -> str:
    outcomes = {_pick(decision, "outcome", default=None) for decision in _effective_fusion_decisions(decisions)}
    if not outcomes:
        return "noop"
    if outcomes == {"reinforced"}:
        return "reinforce"
    if outcomes == {"softened"}:
        return "soften"
    return "mixed"


def _extract_neural_refs(trace_items: Sequence[Dict[str, Any]]) -> Set[str]:
    refs: Set[str] = set()
    for item in trace_items:
        for key in _evidence_keys(item):
            if not key.startswith("neural."):
                continue
            parts = key.split(".")
            if len(parts) >= 2:
                refs.add(parts[1])
    return refs


def _decision_has_complete_trace(decision: Dict[str, Any], trace_items: Sequence[Dict[str, Any]]) -> bool:
    head_ids = [head_id for head_id in (_pick(decision, "appliedHeadIds", "applied_head_ids", default=[]) or []) if isinstance(head_id, str)]
    if not head_ids:
        return False

    observation_match = False
    interpretation_match = False
    recommendation_neural_direct = False
    for item in trace_items:
        stage = _pick(item, "stage", default=None)
        evidence_keys = _evidence_keys(item)
        if stage == "observation":
            if any(any(key.startswith(f"neural.{head_id}.") for key in evidence_keys) for head_id in head_ids):
                observation_match = True
        elif stage == "interpretation":
            if any(any(key.startswith(f"neural.{head_id}.") for key in evidence_keys) for head_id in head_ids):
                interpretation_match = True
        elif stage == "recommendation":
            if any(key.startswith("neural.") for key in evidence_keys):
                recommendation_neural_direct = True
    return observation_match and interpretation_match and not recommendation_neural_direct


def extract_final_outputs(projections_by_case_id: Dict[str, Dict[str, Any]]) -> Dict[str, Dict[str, Any]]:
    outputs: Dict[str, Dict[str, Any]] = {}
    for case_id, projection in projections_by_case_id.items():
        final_output = _pick(projection, "finalOutput", "final_output", default=None)
        if isinstance(final_output, dict):
            outputs[case_id] = final_output
        else:
            outputs[case_id] = {}
    return outputs


def normalize_projection_rows(rows: Sequence[Dict[str, Any]]) -> Dict[str, Dict[str, Any]]:
    projections: Dict[str, Dict[str, Any]] = {}
    for row in rows:
        if not isinstance(row, dict):
            raise ValueError(f"invalid hybrid output row: {row!r}")
        case_id = _normalize_case_id(row)
        if case_id in projections:
            raise ValueError(f"{case_id}: duplicate projection row")
        projection_kind = _pick(row, "projectionKind", "projection_kind", default=None)
        if projection_kind not in {"single_frame", "live_sequence"}:
            raise ValueError(f"{case_id}: missing or invalid projectionKind")
        projections[case_id] = dict(row)
    return projections


def validate_hybrid_case_contract(cases: Sequence[Dict[str, Any]]) -> None:
    for case in cases:
        hybrid_eval = case.get("hybrid_eval")
        if hybrid_eval is None:
            continue
        if not isinstance(hybrid_eval, dict):
            raise ValueError(f"{case['eval_case_id']}: hybrid_eval must be an object")

        mode = _mode_for_case(case)
        policy_heads = set(POLICY_HEADS[mode])

        expected_behavior = hybrid_eval.get("expectedFusionBehavior")
        if expected_behavior is not None and expected_behavior not in EXPECTED_FUSION_BEHAVIORS:
            raise ValueError(
                f"{case['eval_case_id']}: expectedFusionBehavior must be one of "
                f"{sorted(EXPECTED_FUSION_BEHAVIORS)}"
            )

        offload_tier = hybrid_eval.get("offloadTierAllowed", "none")
        if offload_tier not in OFFLOAD_TIERS:
            raise ValueError(
                f"{case['eval_case_id']}: offloadTierAllowed must be one of {sorted(OFFLOAD_TIERS)}"
            )
        if offload_tier == "redacted_visual":
            if not isinstance(hybrid_eval.get("visualReplayRef"), str) or not hybrid_eval.get("visualReplayRef"):
                raise ValueError(
                    f"{case['eval_case_id']}: redacted_visual cases must declare visualReplayRef"
                )
            if hybrid_eval.get("visualReplayTrigger") != "explicit_user_request":
                raise ValueError(
                    f"{case['eval_case_id']}: redacted_visual cases must use "
                    "visualReplayTrigger=explicit_user_request"
                )
        replay_trigger = hybrid_eval.get("visualReplayTrigger")
        if replay_trigger is not None and replay_trigger not in VISUAL_REPLAY_TRIGGERS:
            raise ValueError(
                f"{case['eval_case_id']}: visualReplayTrigger must be one of "
                f"{sorted(VISUAL_REPLAY_TRIGGERS)}"
            )

        for field_name in ("expectedEligibleHeadIds", "forbiddenAppliedHeadIds"):
            field_value = hybrid_eval.get(field_name)
            if field_value is None:
                continue
            if not isinstance(field_value, list):
                raise ValueError(f"{case['eval_case_id']}: {field_name} must be a list")
            head_ids = [head_id for head_id in field_value if isinstance(head_id, str)]
            if len(head_ids) != len(field_value):
                raise ValueError(f"{case['eval_case_id']}: {field_name} must contain only string head ids")
            if len(set(head_ids)) != len(head_ids):
                raise ValueError(f"{case['eval_case_id']}: {field_name} must not contain duplicates")
            if any(head_id not in policy_heads for head_id in head_ids):
                raise ValueError(
                    f"{case['eval_case_id']}: {field_name} cannot reference heads outside "
                    f"{mode} policy set {sorted(policy_heads)}"
                )


def validate_variant_projections(
    cases: Sequence[Dict[str, Any]],
    projections_by_case_id: Dict[str, Dict[str, Any]],
    capabilities: Dict[str, Any],
) -> None:
    offload_variant_tiers: Set[str] = set()
    for case in cases:
        case_id = str(case["eval_case_id"])
        if case_id not in projections_by_case_id:
            raise ValueError(f"{case_id}: missing hybrid projection row")
        projection = projections_by_case_id[case_id]
        kind = projection.get("projectionKind")
        case_kind = case.get("case_kind")
        if case_kind == "live_sequence" and kind != "live_sequence":
            raise ValueError(f"{case_id}: live_sequence case must use projectionKind=live_sequence")
        if case_kind != "live_sequence" and kind != "single_frame":
            raise ValueError(f"{case_id}: non-sequence case must use projectionKind=single_frame")
        if kind == "single_frame":
            for key in ("deterministicOutput", "finalOutput", "localPhaseOutput"):
                if not isinstance(projection.get(key), dict):
                    raise ValueError(f"{case_id}: single-frame projection missing {key}")
            is_live_case = case_kind == "single_frame_live"
            inference = _pick(projection, "inferenceOutcome", "inference_outcome", default=None)
            if (bool(capabilities.get("pauseLocalHybrid", False)) and not is_live_case) or (
                bool(capabilities.get("liveHybrid", False)) and is_live_case
            ):
                if not isinstance(inference, dict):
                    raise ValueError(f"{case_id}: implemented local hybrid path must materialize inferenceOutcome")
                status = _pick(inference, "status", default=None)
                if status not in {"disabled", "executed", "policySkipped", "failed"}:
                    raise ValueError(f"{case_id}: invalid inferenceOutcome.status '{status}'")
                if status in {"executed", "policySkipped", "failed"}:
                    runtime_sample = _pick(projection, "runtimeSample", "runtime_sample", default=None)
                    if not isinstance(runtime_sample, dict):
                        raise ValueError(
                            f"{case_id}: implemented local hybrid path with status={status} must materialize runtimeSample"
                        )
            offload = _pick(projection, "offloadOutcome", "offload_outcome", default=None)
            if bool(capabilities.get("offload", False)):
                if not isinstance(offload, dict):
                    raise ValueError(f"{case_id}: offload-capable variant must materialize offloadOutcome")
                offload_status = _pick(offload, "status", default=None)
                offload_tier = _pick(offload, "tier", default=None)
                offload_trigger = _pick(offload, "trigger", default=None)
                offload_failure_kind = _pick(offload, "failureKind", "failure_kind", default=None)
                local_first_published = _pick(offload, "localFirstPublished", "local_first_published", default=None)
                response_applied = _pick(offload, "responseApplied", "response_applied", default=None)
                boundary_safe = _pick(offload, "boundarySafe", "boundary_safe", default=None)
                if offload_status not in OFFLOAD_STATUSES:
                    raise ValueError(f"{case_id}: invalid offloadOutcome.status '{offload_status}'")
                if offload_tier not in OFFLOAD_TIERS:
                    raise ValueError(f"{case_id}: invalid offloadOutcome.tier '{offload_tier}'")
                if offload_trigger not in {"none", *VISUAL_REPLAY_TRIGGERS}:
                    raise ValueError(f"{case_id}: invalid offloadOutcome.trigger '{offload_trigger}'")
                if offload_failure_kind not in OFFLOAD_FAILURE_KINDS:
                    raise ValueError(f"{case_id}: invalid offloadOutcome.failureKind '{offload_failure_kind}'")
                if not isinstance(local_first_published, bool):
                    raise ValueError(f"{case_id}: offloadOutcome.localFirstPublished must be a bool")
                if not isinstance(response_applied, bool):
                    raise ValueError(f"{case_id}: offloadOutcome.responseApplied must be a bool")
                if not isinstance(boundary_safe, bool):
                    raise ValueError(f"{case_id}: offloadOutcome.boundarySafe must be a bool")
                if offload_tier in {"structured_only", "redacted_visual"}:
                    offload_variant_tiers.add(str(offload_tier))
                if offload_status != "disabled" and offload_tier == "none":
                    raise ValueError(f"{case_id}: offloadOutcome.tier cannot be none when offload path is active")
                if not local_first_published:
                    raise ValueError(f"{case_id}: offloadOutcome.localFirstPublished must stay true for local-first contract")
                allowed_tier = _pick(case.get("hybrid_eval", {}), "offloadTierAllowed", default="none")
                if offload_tier == "structured_only" and allowed_tier == "none" and offload_status not in {"disabled", "blocked", "notTriggered"}:
                    raise ValueError(f"{case_id}: structured_only offload cannot run when case forbids offloading")
                if offload_tier == "redacted_visual":
                    if allowed_tier != "redacted_visual" and offload_status not in {"disabled", "blocked", "notTriggered"}:
                        raise ValueError(f"{case_id}: redacted_visual offload cannot run for this case")
                    if offload_status == "completed" and offload_trigger != "explicit_user_request":
                        raise ValueError(
                            f"{case_id}: redacted_visual completed offload must use trigger=explicit_user_request"
                        )
                augmented_output = _pick(projection, "augmentedOutput", "augmented_output", default=None)
                if offload_status == "completed":
                    if offload_failure_kind != "none":
                        raise ValueError(f"{case_id}: completed offload must use failureKind=none")
                    if not isinstance(augmented_output, dict):
                        raise ValueError(f"{case_id}: completed offloadOutcome must materialize augmentedOutput")
                    if response_applied:
                        if not _score_equivalent(case, projection.get("finalOutput"), augmented_output):
                            raise ValueError(
                                f"{case_id}: completed+responseApplied offload must make finalOutput score-equivalent augmentedOutput"
                            )
                    else:
                        if not _score_equivalent(case, projection.get("finalOutput"), projection.get("localPhaseOutput")):
                            raise ValueError(
                                f"{case_id}: completed+not-applied offload must keep finalOutput score-equivalent localPhaseOutput"
                            )
                else:
                    if isinstance(augmented_output, dict):
                        raise ValueError(f"{case_id}: augmentedOutput is only allowed for completed offload")
                    if response_applied:
                        raise ValueError(f"{case_id}: non-completed offload cannot have responseApplied=true")
                    if not _score_equivalent(case, projection.get("finalOutput"), projection.get("localPhaseOutput")):
                        raise ValueError(
                            f"{case_id}: non-completed offload must keep finalOutput score-equivalent localPhaseOutput"
                        )
                    if offload_status in {"disabled", "notTriggered"} and offload_failure_kind != "none":
                        raise ValueError(f"{case_id}: {offload_status} offload must use failureKind=none")
                    if offload_status == "blocked" and offload_failure_kind not in {
                        "policy_refused",
                        "capability_mismatch",
                        "validation_failed",
                    }:
                        raise ValueError(f"{case_id}: blocked offload must use policy/capability/validation failureKind")
                    if offload_status == "failed" and offload_failure_kind not in {
                        "timeout",
                        "transport_error",
                        "unknown",
                    }:
                        raise ValueError(f"{case_id}: failed offload must use transport/runtime failureKind")
            elif offload is not None:
                raise ValueError(f"{case_id}: non-offloading variant must not materialize offloadOutcome")
        if kind == "live_sequence":
            if not isinstance(projection.get("deterministicOutput"), dict):
                raise ValueError(f"{case_id}: live-sequence projection missing deterministicOutput")
            if not isinstance(projection.get("finalOutput"), dict):
                raise ValueError(f"{case_id}: live-sequence projection missing finalOutput")
            frame_outputs = _frame_outputs(projection.get("finalOutput"))
            if bool(capabilities.get("liveHybrid", False)) and not isinstance(projection.get("frameArtifacts"), list):
                raise ValueError(f"{case_id}: live-capable variant must materialize frameArtifacts")
            if bool(capabilities.get("liveHybrid", False)):
                frame_artifacts = projection.get("frameArtifacts", []) or []
                if len(frame_artifacts) != len(frame_outputs):
                    raise ValueError(
                        f"{case_id}: frameArtifacts.count must match materialized frame_outputs count"
                    )
                output_ordinals = []
                for item in frame_outputs:
                    ordinal = _pick(item, "frameOrdinal", "frame_ordinal", default=None)
                    if not isinstance(ordinal, int):
                        raise ValueError(f"{case_id}: frame_outputs entries must materialize integer frameOrdinal")
                    output_ordinals.append(ordinal)
                seen_ordinals: Set[int] = set()
                for artifact in frame_artifacts:
                    if not isinstance(artifact, dict):
                        raise ValueError(f"{case_id}: frameArtifacts must contain objects")
                    frame_ordinal = _pick(artifact, "frameOrdinal", "frame_ordinal", default=None)
                    if not isinstance(frame_ordinal, int):
                        raise ValueError(f"{case_id}: frame artifact must materialize integer frameOrdinal")
                    if frame_ordinal in seen_ordinals:
                        raise ValueError(f"{case_id}: duplicate frameArtifact.frameOrdinal {frame_ordinal}")
                    seen_ordinals.add(frame_ordinal)
                    if frame_ordinal not in output_ordinals:
                        raise ValueError(f"{case_id}: frameArtifact.frameOrdinal {frame_ordinal} not present in finalOutput.frame_outputs")
                    stale_dropped = _pick(artifact, "staleDropped", "stale_dropped", default=None)
                    if not isinstance(stale_dropped, bool):
                        raise ValueError(f"{case_id}: frame artifact must materialize staleDropped bool")
                    inference = _pick(artifact, "inferenceOutcome", "inference_outcome", default=None)
                    if not isinstance(inference, dict):
                        raise ValueError(f"{case_id}: live frame artifact missing inferenceOutcome")
                    status = _pick(inference, "status", default=None)
                    if status in {"executed", "policySkipped", "failed"}:
                        runtime_sample = _pick(artifact, "runtimeSample", "runtime_sample", default=None)
                        if not isinstance(runtime_sample, dict):
                            raise ValueError(
                                f"{case_id}: live frame artifact with status={status} must materialize runtimeSample"
                            )
                        runtime_ordinal = _pick(runtime_sample, "frameOrdinal", "frame_ordinal", default=None)
                        if runtime_ordinal != frame_ordinal:
                            raise ValueError(
                                f"{case_id}: runtimeSample.frameOrdinal must match frameArtifact.frameOrdinal"
                            )
                        runtime_stale = _pick(runtime_sample, "staleDropped", "stale_dropped", default=None)
                        if runtime_stale != stale_dropped:
                            raise ValueError(
                                f"{case_id}: runtimeSample.staleDropped must match frameArtifact.staleDropped"
                            )
    if len(offload_variant_tiers) > 1:
        raise ValueError(
            "offload-capable variant must not mix structured_only and redacted_visual tiers in one variant output"
        )


def score_hybrid_variant(
    variant_id: str,
    parent_variant_id: Optional[str],
    family: Optional[str],
    capabilities: Dict[str, Any],
    cases: Sequence[Dict[str, Any]],
    projections_by_case_id: Dict[str, Dict[str, Any]],
    core_scores: Dict[str, Any],
    anchor_core_scores: Dict[str, Any],
    anchor_compare: Dict[str, Any],
) -> Dict[str, Any]:
    case_by_id = {str(case["eval_case_id"]): case for case in cases}
    anchor_case_map = {
        str(row["eval_case_id"]): row
        for row in anchor_core_scores.get("case_results", [])
        if isinstance(row, dict) and "eval_case_id" in row
    }
    candidate_case_map = {
        str(row["eval_case_id"]): row
        for row in core_scores.get("case_results", [])
        if isinstance(row, dict) and "eval_case_id" in row
    }

    utility_lists: Dict[str, List[float]] = {
        "safe_noop_rate": [],
        "applied_fusion_rate": [],
        "case_neural_coverage_rate": [],
        "hybrid_degraded_fallback_case_pass_rate": [],
    }
    agreement_lists: Dict[str, List[float]] = {
        "fusion_trace_coverage_rate": [],
        "head_policy_agreement_rate": [],
        "forbidden_head_violation_rate": [],
        "fusion_expectation_agreement_rate": [],
        "status_trace_consistency_rate": [],
        "supporting_signal_contract_rate": [],
        "offload_boundary_compliance_rate": [],
    }
    bucket_values: Dict[str, List[float]] = {bucket: [] for bucket in HYBRID_PAUSE_BUCKETS + ("live_guarded_value",)}
    representative_cases: List[str] = []

    eligible_slots_total = 0.0
    eligible_slots_available = 0.0

    pause_denominator = 0.0
    pause_success = 0.0
    pause_failure = 0.0
    pause_degraded_success = 0.0
    pause_valid_executed = 0.0

    live_requests = 0.0
    live_policy_skipped = 0.0
    live_critical_total = 0.0
    live_critical_skipped = 0.0
    live_sample_count = 0

    pause_latencies: List[float] = []
    live_latencies: List[float] = []
    peak_memory_samples: List[float] = []
    stale_drop_values: List[float] = []
    has_degraded_pause_samples = False
    offload_tiers_seen: Set[str] = set()
    offload_completed = 0.0
    offload_candidates = 0.0
    offload_response_applied = 0.0

    for case_id in sorted(case_by_id.keys()):
        case = case_by_id[case_id]
        projection = projections_by_case_id[case_id]
        if projection.get("projectionKind") != "single_frame":
            deterministic_output = projection.get("deterministicOutput")
            final_output = projection.get("finalOutput")
            frame_outputs = _frame_outputs(final_output)
            frame_output_by_ordinal = {
                int(_pick(item, "frameOrdinal", "frame_ordinal", default=-1)): item
                for item in frame_outputs
                if isinstance(_pick(item, "frameOrdinal", "frame_ordinal", default=None), int)
            }
            last_frame_ordinal = max(frame_output_by_ordinal.keys()) if frame_output_by_ordinal else None
            sequence_has_effective_decisions = False
            sequence_has_eligible_denominator = False
            sequence_has_eligible_available = False
            sequence_effective_decisions: List[Dict[str, Any]] = []
            sequence_forbidden_violation = False
            sequence_has_forbidden_denominator = False
            for artifact in projection.get("frameArtifacts", []) or []:
                if not isinstance(artifact, dict):
                    continue
                inference = _pick(artifact, "inferenceOutcome", "inference_outcome", default={}) or {}
                runtime = _pick(artifact, "runtimeSample", "runtime_sample", default={}) or {}
                frame_ordinal = _pick(artifact, "frameOrdinal", "frame_ordinal", default=None)
                mode = str(_pick(inference, "mode", default="live"))
                if mode != "live":
                    continue
                live_requests += 1.0
                status = _pick(inference, "status", default=None)
                if status == "policySkipped":
                    live_policy_skipped += 1.0
                if status == "executed":
                    live_sample_count += 1
                latency = _pick(runtime, "inferenceLatencyMs", "inference_latency_ms", default=None)
                if isinstance(latency, (int, float)) and status == "executed":
                    live_latencies.append(float(latency))
                peak = _pick(runtime, "peakMemoryMB", "peak_memory_mb", default=None)
                if isinstance(peak, (int, float)):
                    peak_memory_samples.append(float(peak))
                if bool(_pick(runtime, "staleDropped", "stale_dropped", default=False)):
                    stale_drop_values.append(1.0)
                else:
                    stale_drop_values.append(0.0)
                if _pick(runtime, "thermalTier", "thermal_tier", default=None) == "critical":
                    live_critical_total += 1.0
                    if status == "policySkipped":
                        live_critical_skipped += 1.0
                snapshot = _pick(artifact, "neuralSnapshot", "neural_snapshot", default=None)
                head_map = _head_payload_map(snapshot)
                execution_profile = _pick(runtime, "executionProfile", "execution_profile", default=None)
                eligible_heads = _effective_eligible_heads(case, execution_profile if isinstance(execution_profile, str) else None)
                if eligible_heads:
                    sequence_has_eligible_denominator = True
                    eligible_slots_total += float(len(eligible_heads))
                    available_count = sum(
                        1
                        for head_id in eligible_heads
                        if _pick(head_map.get(head_id, {}), "status", default=None) == "available"
                    )
                    eligible_slots_available += float(available_count)
                    if available_count > 0:
                        sequence_has_eligible_available = True

                decisions = _pick(artifact, "fusionDecisions", "fusion_decisions", default=[]) or []
                effective_decisions = _effective_fusion_decisions(decisions)
                if effective_decisions:
                    sequence_has_effective_decisions = True
                    sequence_effective_decisions.extend(effective_decisions)
                    representative_cases.append(case_id)
                    trace_fallback = final_output if last_frame_ordinal is not None and frame_ordinal == last_frame_ordinal else None
                    trace_items = _artifact_trace_items(artifact, fallback_output=trace_fallback)
                    trace_hits = 0
                    policy_hits = 0
                    for decision in effective_decisions:
                        trace_hits += 1 if _decision_has_complete_trace(decision, trace_items) else 0
                        policy_hits += 1 if _decision_policy_ok(decision, mode, eligible_heads, head_map) else 0
                    agreement_lists["fusion_trace_coverage_rate"].append(
                        _safe_div(float(trace_hits), float(len(effective_decisions))) or 0.0
                    )
                    agreement_lists["head_policy_agreement_rate"].append(
                        _safe_div(float(policy_hits), float(len(effective_decisions))) or 0.0
                    )
                    neural_refs = _extract_neural_refs(trace_items)
                    if neural_refs:
                        consistent = all(
                            _pick(head_map.get(head_id, {}), "status", default=None) == "available"
                            for head_id in neural_refs
                        )
                        agreement_lists["status_trace_consistency_rate"].append(1.0 if consistent else 0.0)

                forbidden_heads = case.get("hybrid_eval", {}).get("forbiddenAppliedHeadIds")
                if isinstance(forbidden_heads, list) and forbidden_heads:
                    sequence_has_forbidden_denominator = True
                    forbidden = {head_id for head_id in forbidden_heads if isinstance(head_id, str)}
                    if any(
                        bool(forbidden & set(_pick(decision, "appliedHeadIds", "applied_head_ids", default=[]) or []))
                        for decision in effective_decisions
                    ):
                        sequence_forbidden_violation = True

                supporting_score = _supporting_signal_contract_score(head_map)
                if supporting_score is not None:
                    agreement_lists["supporting_signal_contract_rate"].append(supporting_score)

            if not sequence_has_effective_decisions:
                utility_lists["safe_noop_rate"].append(
                    1.0 if _score_equivalent(case, deterministic_output, final_output) else 0.0
                )
            utility_lists["applied_fusion_rate"].append(1.0 if sequence_has_effective_decisions else 0.0)
            if sequence_has_eligible_denominator:
                utility_lists["case_neural_coverage_rate"].append(1.0 if sequence_has_eligible_available else 0.0)
            if sequence_has_forbidden_denominator:
                agreement_lists["forbidden_head_violation_rate"].append(1.0 if sequence_forbidden_violation else 0.0)
            expected_behavior = case.get("hybrid_eval", {}).get("expectedFusionBehavior")
            if isinstance(expected_behavior, str):
                agreement_lists["fusion_expectation_agreement_rate"].append(
                    1.0 if _realized_fusion_behavior(sequence_effective_decisions) == expected_behavior else 0.0
                )

            hybrid_buckets = _hybrid_buckets_for_case(case)
            candidate_metrics = candidate_case_map.get(case_id, {}).get("metrics", {})
            anchor_metrics = anchor_case_map.get(case_id, {}).get("metrics", {})
            winner, _ = _winner_by_priority(anchor_metrics, candidate_metrics)
            if "hybrid_degraded_fallback" in hybrid_buckets:
                degraded_pass = 0.0
                fallback_accuracy = candidate_metrics.get("fallback_policy_accuracy")
                if isinstance(fallback_accuracy, (int, float)):
                    if float(fallback_accuracy) >= 1.0 - 1e-9 and _score_equivalent(case, deterministic_output, final_output):
                        degraded_pass = 1.0
                utility_lists["hybrid_degraded_fallback_case_pass_rate"].append(degraded_pass)
                no_regression = not _has_metric_regression(anchor_metrics, candidate_metrics)
                bucket_values["hybrid_degraded_fallback"].append(1.0 if degraded_pass == 1.0 and no_regression else 0.0)
            if capabilities.get("liveHybrid", False) and "live_guarded_value" in hybrid_buckets:
                live_winner, _ = _winner_for_live_guarded(anchor_metrics, candidate_metrics)
                no_extra_risk = not (
                    isinstance(candidate_metrics.get("hint_jitter_rate"), (int, float))
                    and isinstance(anchor_metrics.get("hint_jitter_rate"), (int, float))
                    and float(candidate_metrics["hint_jitter_rate"]) > float(anchor_metrics["hint_jitter_rate"]) + 1e-9
                ) and not (
                    isinstance(candidate_metrics.get("unsupported_claim_rate"), (int, float))
                    and isinstance(anchor_metrics.get("unsupported_claim_rate"), (int, float))
                    and float(candidate_metrics["unsupported_claim_rate"]) > float(anchor_metrics["unsupported_claim_rate"]) + 1e-9
                )
                bucket_values["live_guarded_value"].append(1.0 if live_winner == "candidate" and no_extra_risk else 0.0)
            continue

        deterministic_output = projection.get("deterministicOutput")
        final_output = projection.get("finalOutput")
        local_phase_output = projection.get("localPhaseOutput")
        runtime_sample = _pick(projection, "runtimeSample", "runtime_sample", default=None)
        inference = _pick(projection, "inferenceOutcome", "inference_outcome", default={}) or {}
        decisions = projection.get("fusionDecisions", []) or []
        effective_decisions = _effective_fusion_decisions(decisions)
        trace_items = _trace_items(final_output)
        snapshot = _pick(projection, "neuralSnapshot", "neural_snapshot", default=None)
        head_map = _head_payload_map(snapshot)
        execution_profile = _pick(runtime_sample or {}, "executionProfile", "execution_profile", default=None)
        mode = _mode_for_case(case)

        eligible_heads = _effective_eligible_heads(case, execution_profile if isinstance(execution_profile, str) else None)
        if eligible_heads:
            eligible_slots_total += float(len(eligible_heads))
            available_count = sum(
                1
                for head_id in eligible_heads
                if _pick(head_map.get(head_id, {}), "status", default=None) == "available"
            )
            eligible_slots_available += float(available_count)
            utility_lists["case_neural_coverage_rate"].append(1.0 if available_count > 0 else 0.0)

        no_effective_neural_path = not effective_decisions and not (
            isinstance(_pick(projection.get("offloadOutcome", {}) or {}, "responseApplied", "response_applied", default=None), bool)
            and bool(_pick(projection.get("offloadOutcome", {}) or {}, "responseApplied", "response_applied", default=False))
        )
        if no_effective_neural_path:
            utility_lists["safe_noop_rate"].append(1.0 if _score_equivalent(case, deterministic_output, final_output) else 0.0)

        utility_lists["applied_fusion_rate"].append(1.0 if effective_decisions else 0.0)
        if effective_decisions:
            representative_cases.append(case_id)

        if effective_decisions:
            trace_hits = 0
            policy_hits = 0
            for decision in effective_decisions:
                trace_hits += 1 if _decision_has_complete_trace(decision, trace_items) else 0
                policy_hits += 1 if _decision_policy_ok(decision, mode, eligible_heads, head_map) else 0
            agreement_lists["fusion_trace_coverage_rate"].append(
                _safe_div(float(trace_hits), float(len(effective_decisions))) or 0.0
            )
            agreement_lists["head_policy_agreement_rate"].append(
                _safe_div(float(policy_hits), float(len(effective_decisions))) or 0.0
            )

        forbidden_heads = case.get("hybrid_eval", {}).get("forbiddenAppliedHeadIds")
        if isinstance(forbidden_heads, list) and forbidden_heads:
            forbidden = {head_id for head_id in forbidden_heads if isinstance(head_id, str)}
            violation = any(
                bool(forbidden & set(_pick(decision, "appliedHeadIds", "applied_head_ids", default=[]) or []))
                for decision in effective_decisions
            )
            agreement_lists["forbidden_head_violation_rate"].append(1.0 if violation else 0.0)

        expected_behavior = case.get("hybrid_eval", {}).get("expectedFusionBehavior")
        if isinstance(expected_behavior, str):
            agreement_lists["fusion_expectation_agreement_rate"].append(
                1.0 if _realized_fusion_behavior(decisions) == expected_behavior else 0.0
            )

        neural_refs = _extract_neural_refs(trace_items)
        if neural_refs:
            consistent = all(_pick(head_map.get(head_id, {}), "status", default=None) == "available" for head_id in neural_refs)
            agreement_lists["status_trace_consistency_rate"].append(1.0 if consistent else 0.0)

        supporting_score = _supporting_signal_contract_score(head_map)
        if supporting_score is not None:
            agreement_lists["supporting_signal_contract_rate"].append(supporting_score)

        offload = projection.get("offloadOutcome")
        if capabilities.get("offload") and isinstance(offload, dict):
            offload_candidates += 1.0
            offload_tier = _pick(offload, "tier", default=None)
            if isinstance(offload_tier, str) and offload_tier in {"structured_only", "redacted_visual"}:
                offload_tiers_seen.add(offload_tier)
            boundary_safe = bool(_pick(offload, "boundarySafe", "boundary_safe", default=False))
            response_applied = bool(_pick(offload, "responseApplied", "response_applied", default=False))
            status = _pick(offload, "status", default=None)
            if status == "completed":
                offload_completed += 1.0
            if response_applied:
                offload_response_applied += 1.0
            if status != "completed" or not response_applied:
                boundary_safe = boundary_safe and _score_equivalent(case, local_phase_output, final_output)
            agreement_lists["offload_boundary_compliance_rate"].append(1.0 if boundary_safe else 0.0)

        hybrid_buckets = _hybrid_buckets_for_case(case)
        candidate_metrics = candidate_case_map.get(case_id, {}).get("metrics", {})
        anchor_metrics = anchor_case_map.get(case_id, {}).get("metrics", {})
        winner, _ = _winner_by_priority(anchor_metrics, candidate_metrics)
        if mode == "pause":
            for bucket in ("ambiguity_borderline", "style_vs_failure_conflict", "pause_neural_value"):
                if bucket in hybrid_buckets:
                    bucket_values[bucket].append(1.0 if winner == "candidate" else 0.0)

        if "hybrid_degraded_fallback" in hybrid_buckets:
            degraded_pass = 0.0
            fallback_accuracy = candidate_metrics.get("fallback_policy_accuracy")
            if isinstance(fallback_accuracy, (int, float)):
                if float(fallback_accuracy) >= 1.0 - 1e-9 and _score_equivalent(case, deterministic_output, final_output):
                    degraded_pass = 1.0
            utility_lists["hybrid_degraded_fallback_case_pass_rate"].append(degraded_pass)
            no_regression = not _has_metric_regression(anchor_metrics, candidate_metrics)
            bucket_values["hybrid_degraded_fallback"].append(1.0 if degraded_pass == 1.0 and no_regression else 0.0)

        if mode == "pause" and capabilities.get("pauseLocalHybrid", False):
            pause_denominator += 1.0
            status = _pick(inference, "status", default=None)
            if status == "executed":
                pause_success += 1.0
                pause_valid_executed += 1.0
                if execution_profile == "degraded_pause_profile":
                    pause_degraded_success += 1.0
                    has_degraded_pause_samples = True
            elif status == "failed":
                pause_failure += 1.0
            if execution_profile == "degraded_pause_profile":
                has_degraded_pause_samples = True
            latency = _pick(runtime_sample or {}, "inferenceLatencyMs", "inference_latency_ms", default=None)
            if isinstance(latency, (int, float)):
                pause_latencies.append(float(latency))
            peak = _pick(runtime_sample or {}, "peakMemoryMB", "peak_memory_mb", default=None)
            if isinstance(peak, (int, float)):
                peak_memory_samples.append(float(peak))

        if mode == "live" and capabilities.get("liveHybrid", False):
            live_requests += 1.0
            status = _pick(inference, "status", default=None)
            if status == "policySkipped":
                live_policy_skipped += 1.0
            if status == "executed":
                live_sample_count += 1
            latency = _pick(runtime_sample or {}, "inferenceLatencyMs", "inference_latency_ms", default=None)
            if isinstance(latency, (int, float)) and status == "executed":
                live_latencies.append(float(latency))
            peak = _pick(runtime_sample or {}, "peakMemoryMB", "peak_memory_mb", default=None)
            if isinstance(peak, (int, float)):
                peak_memory_samples.append(float(peak))
            stale_dropped = bool(_pick(runtime_sample or {}, "staleDropped", "stale_dropped", default=False))
            stale_drop_values.append(1.0 if stale_dropped else 0.0)
            if _pick(runtime_sample or {}, "thermalTier", "thermal_tier", default=None) == "critical":
                live_critical_total += 1.0
                if status == "policySkipped":
                    live_critical_skipped += 1.0
            if "live_guarded_value" in hybrid_buckets:
                live_winner, _ = _winner_for_live_guarded(anchor_metrics, candidate_metrics)
                no_extra_risk = not (
                    isinstance(candidate_metrics.get("hint_jitter_rate"), (int, float))
                    and isinstance(anchor_metrics.get("hint_jitter_rate"), (int, float))
                    and float(candidate_metrics["hint_jitter_rate"]) > float(anchor_metrics["hint_jitter_rate"]) + 1e-9
                ) and not (
                    isinstance(candidate_metrics.get("unsupported_claim_rate"), (int, float))
                    and isinstance(anchor_metrics.get("unsupported_claim_rate"), (int, float))
                    and float(candidate_metrics["unsupported_claim_rate"]) > float(anchor_metrics["unsupported_claim_rate"]) + 1e-9
                )
                bucket_values["live_guarded_value"].append(1.0 if live_winner == "candidate" and no_extra_risk else 0.0)

    utility_metrics = {
        "safe_noop_rate": _round_metric(_mean(utility_lists["safe_noop_rate"]) if utility_lists["safe_noop_rate"] else 1.0),
        "eligible_head_availability_rate": _round_metric(_safe_div(eligible_slots_available, eligible_slots_total)),
        "case_neural_coverage_rate": _round_metric(_mean(utility_lists["case_neural_coverage_rate"])),
        "applied_fusion_rate": _round_metric(_mean(utility_lists["applied_fusion_rate"])),
        "pause_uplift_win_rate": _round_metric(_mean(
            [value for bucket in ("ambiguity_borderline", "style_vs_failure_conflict", "pause_neural_value") for value in bucket_values[bucket]]
        )),
        "ambiguity_borderline_win_rate": _round_metric(_mean(bucket_values["ambiguity_borderline"])),
        "style_vs_failure_conflict_win_rate": _round_metric(_mean(bucket_values["style_vs_failure_conflict"])),
        "pause_neural_value_win_rate": _round_metric(_mean(bucket_values["pause_neural_value"])),
        "live_guarded_win_rate": _round_metric(_mean(bucket_values["live_guarded_value"])),
        "hybrid_degraded_fallback_case_pass_rate": _round_metric(_mean(utility_lists["hybrid_degraded_fallback_case_pass_rate"])),
        "hybrid_degraded_fallback_score": _round_metric(_mean(utility_lists["hybrid_degraded_fallback_case_pass_rate"])),
        "hybrid_degraded_fallback_win_rate": _round_metric(_mean(bucket_values["hybrid_degraded_fallback"])),
    }
    agreement_metrics = {
        name: _round_metric(_mean(values))
        for name, values in agreement_lists.items()
        if values
    }
    if "fusion_trace_coverage_rate" not in agreement_metrics:
        agreement_metrics["fusion_trace_coverage_rate"] = 1.0
    if "head_policy_agreement_rate" not in agreement_metrics:
        agreement_metrics["head_policy_agreement_rate"] = 1.0
    if "status_trace_consistency_rate" not in agreement_metrics:
        agreement_metrics["status_trace_consistency_rate"] = 1.0
    if capabilities.get("offload") and "offload_boundary_compliance_rate" not in agreement_metrics:
        agreement_metrics["offload_boundary_compliance_rate"] = None

    mobile_metrics = {
        "live_policy_skip_rate": _round_metric(_safe_div(live_policy_skipped, live_requests)),
        "live_latency_p50_ms": _round_metric(_percentile(live_latencies, 0.50)),
        "live_latency_p95_ms": _round_metric(_percentile(live_latencies, 0.95)),
        "pause_latency_p50_ms": _round_metric(_percentile(pause_latencies, 0.50)),
        "pause_latency_p95_ms": _round_metric(_percentile(pause_latencies, 0.95)),
        "pause_execute_success_rate": _round_metric(_safe_div(pause_success, pause_denominator)),
        "pause_degraded_execution_rate": _round_metric(_safe_div(pause_degraded_success, pause_valid_executed)),
        "pause_failure_rate": _round_metric(_safe_div(pause_failure, pause_denominator)),
        "peak_memory_p95_mb": _round_metric(_percentile(peak_memory_samples, 0.95)),
        "critical_thermal_skip_rate": _round_metric(_safe_div(live_critical_skipped, live_critical_total)),
        "stale_result_drop_rate": _round_metric(_mean(stale_drop_values)),
    }

    release = _build_release_recommendation(
        capabilities=capabilities,
        anchor_compare=anchor_compare,
        utility_metrics=utility_metrics,
        agreement_metrics=agreement_metrics,
        mobile_metrics=mobile_metrics,
        has_degraded_pause_samples=has_degraded_pause_samples,
        live_sample_count=live_sample_count,
    )

    return {
        "variant_id": variant_id,
        "parent_variant_id": parent_variant_id,
        "family": family,
        "capabilities": capabilities,
        "anchor_compare": anchor_compare,
        "utility_metrics": utility_metrics,
        "agreement_metrics": agreement_metrics,
        "mobile_metrics": mobile_metrics,
        "offload_summary": {
            "tier": sorted(offload_tiers_seen)[0] if len(offload_tiers_seen) == 1 else None,
            "completed_rate": _round_metric(_safe_div(offload_completed, offload_candidates)),
            "response_applied_rate": _round_metric(_safe_div(offload_response_applied, offload_candidates)),
            "boundary_compliance_rate": agreement_metrics.get("offload_boundary_compliance_rate"),
        },
        "release_recommendation": release,
        "representative_cases": sorted(set(representative_cases))[:5],
    }


def _build_release_recommendation(
    capabilities: Dict[str, Any],
    anchor_compare: Dict[str, Any],
    utility_metrics: Dict[str, Any],
    agreement_metrics: Dict[str, Any],
    mobile_metrics: Dict[str, Any],
    has_degraded_pause_samples: bool,
    live_sample_count: int,
) -> Dict[str, Any]:
    overall = anchor_compare.get("overall", {})
    reasons: List[str] = []
    failures: List[str] = []
    coverage_limits: List[str] = []
    core_failed = False

    issue_delta = _pick(overall.get("issue_f1", {}), "delta", default=None)
    if isinstance(issue_delta, (int, float)):
        if float(issue_delta) < -0.03:
            failures.append("issue_f1 regressed more than 0.03 vs deterministic_only")
            core_failed = True
        else:
            reasons.append("issue_f1 stayed within non-regression band")

    action_delta = _pick(overall.get("primary_action_match_rate", {}), "delta", default=None)
    if isinstance(action_delta, (int, float)):
        if float(action_delta) < -0.03:
            failures.append("primary_action_match_rate regressed more than 0.03")
            core_failed = True
        else:
            reasons.append("primary_action_match_rate stayed within non-regression band")

    good_delta = _pick(overall.get("good_frame_confirmation_rate", {}), "delta", default=None)
    if isinstance(good_delta, (int, float)):
        if float(good_delta) < 0.0:
            failures.append("good_frame_confirmation_rate regressed")
            core_failed = True

    unsupported_delta = _pick(overall.get("unsupported_claim_rate", {}), "delta", default=None)
    if isinstance(unsupported_delta, (int, float)):
        if float(unsupported_delta) > 0.0:
            failures.append("unsupported_claim_rate increased")
            core_failed = True

    safe_noop_rate = utility_metrics.get("safe_noop_rate")
    if capabilities.get("pauseLocalHybrid"):
        if not isinstance(safe_noop_rate, (int, float)) or abs(float(safe_noop_rate) - 1.0) > 1e-9:
            failures.append("safe_noop_rate must equal 1.0")
            core_failed = True

    improved_pause_buckets = 0
    bucket_keys = [
        "ambiguity_borderline_win_rate",
        "style_vs_failure_conflict_win_rate",
        "pause_neural_value_win_rate",
        "hybrid_degraded_fallback_win_rate",
    ]
    if capabilities.get("liveHybrid"):
        bucket_keys.append("live_guarded_win_rate")
    for key in bucket_keys:
        value = utility_metrics.get(key)
        if isinstance(value, (int, float)) and float(value) > 0.0:
            improved_pause_buckets += 1
    meaningful_gain = improved_pause_buckets >= 2
    if meaningful_gain:
        reasons.append("hybrid-critical buckets improved in at least two categories")

    explainability_failed = False
    if capabilities.get("pauseLocalHybrid"):
        for key, threshold, optional in (
            ("fusion_trace_coverage_rate", 0.95, False),
            ("head_policy_agreement_rate", 1.0, False),
            ("forbidden_head_violation_rate", 0.0, True),
            ("fusion_expectation_agreement_rate", 0.95, True),
            ("status_trace_consistency_rate", 1.0, False),
        ):
            value = agreement_metrics.get(key)
            if value is None:
                if optional:
                    continue
                explainability_failed = True
                failures.append(f"{key} missing")
                continue
            if key == "forbidden_head_violation_rate":
                if float(value) > threshold:
                    explainability_failed = True
                    failures.append(f"{key} must be 0.0")
            elif float(value) + 1e-9 < threshold:
                explainability_failed = True
                failures.append(f"{key} below required threshold")

    mobile_failed = False
    live_coverage_limited = False
    if capabilities.get("pauseLocalHybrid"):
        pause_success = mobile_metrics.get("pause_execute_success_rate")
        pause_failure = mobile_metrics.get("pause_failure_rate")
        pause_degraded = mobile_metrics.get("pause_degraded_execution_rate")
        pause_p95 = mobile_metrics.get("pause_latency_p95_ms")
        peak_memory = mobile_metrics.get("peak_memory_p95_mb")

        if not isinstance(pause_success, (int, float)) or float(pause_success) < 0.90:
            mobile_failed = True
            failures.append("pause_execute_success_rate below 0.90")
        if not isinstance(pause_failure, (int, float)) or float(pause_failure) > 0.10:
            mobile_failed = True
            failures.append("pause_failure_rate above 0.10")
        if has_degraded_pause_samples:
            if not isinstance(pause_degraded, (int, float)) or float(pause_degraded) <= 0.0:
                mobile_failed = True
                failures.append("pause_degraded_execution_rate missing degraded success path")
        if isinstance(pause_p95, (int, float)) and float(pause_p95) > 45.0:
            mobile_failed = True
            failures.append("pause_latency_p95_ms above PR-H05 target")
        if isinstance(peak_memory, (int, float)) and float(peak_memory) > 140.0:
            mobile_failed = True
            failures.append("peak_memory_p95_mb above hard ceiling")

    if capabilities.get("liveHybrid"):
        live_p95 = mobile_metrics.get("live_latency_p95_ms")
        live_skip = mobile_metrics.get("live_policy_skip_rate")
        thermal_skip = mobile_metrics.get("critical_thermal_skip_rate")
        if isinstance(live_p95, (int, float)) and float(live_p95) > 28.0:
            mobile_failed = True
            failures.append("live_latency_p95_ms above PR-H05 target")
        if not isinstance(live_skip, (int, float)) or not (0.25 <= float(live_skip) <= 0.95):
            mobile_failed = True
            failures.append("live_policy_skip_rate outside canonical band")
        if thermal_skip is None:
            live_coverage_limited = True
            coverage_limits.append("critical thermal live coverage missing; Gate B stays research-only")
        elif not isinstance(thermal_skip, (int, float)) or abs(float(thermal_skip) - 1.0) > 1e-9:
            mobile_failed = True
            failures.append("critical_thermal_skip_rate must equal 1.0 on covered critical samples")
        if live_sample_count < 10:
            live_coverage_limited = True
            coverage_limits.append("live sample count below release-conclusive minimum")

    if capabilities.get("offload"):
        boundary = agreement_metrics.get("offload_boundary_compliance_rate")
        if not isinstance(boundary, (int, float)) or abs(float(boundary) - 1.0) > 1e-9:
            explainability_failed = True
            failures.append("offload_boundary_compliance_rate must equal 1.0")

    if not failures and capabilities.get("pauseLocalHybrid") and meaningful_gain and not live_coverage_limited:
        verdict = "ship_candidate"
    elif explainability_failed:
        verdict = "explainability_blocked"
    elif mobile_failed:
        verdict = "mobile_blocked"
    elif core_failed:
        verdict = "regression_blocked"
    elif meaningful_gain:
        verdict = "research_only"
    else:
        verdict = "no_meaningful_gain"

    return {
        "verdict": verdict,
        "reasons": failures if failures else (coverage_limits if coverage_limits else reasons),
        "failure_count": len(failures),
    }
