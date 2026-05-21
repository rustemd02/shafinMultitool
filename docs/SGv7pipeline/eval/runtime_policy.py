from __future__ import annotations

from dataclasses import dataclass
from typing import Any


@dataclass(frozen=True)
class RuntimePolicyDecision:
    decision: str
    outcome: str
    reason: str
    signals: dict[str, Any]


TARGET_REQUIRED_ACTIONS = {"approach", "stop", "passby", "pass_by", "pass-by"}
CRITICAL_MIN_CONFIDENCE = 0.45


def _normalize_action_type(value: Any) -> str:
    raw = str(value or "").strip()
    if not raw:
        return ""
    lowered = raw.replace("-", "_").replace(" ", "_")
    if lowered.lower() == "passby":
        return "passby"
    return lowered.lower()


def _collect_actors(script: dict[str, Any]) -> list[dict[str, Any]]:
    actors = script.get("actors", [])
    return actors if isinstance(actors, list) else []


def _collect_objects(script: dict[str, Any]) -> list[dict[str, Any]]:
    objects = script.get("objects", [])
    return objects if isinstance(objects, list) else []


def _collect_actions(script: dict[str, Any]) -> list[dict[str, Any]]:
    actions: list[dict[str, Any]] = []
    top_level = script.get("actions")
    if isinstance(top_level, list):
        for payload in top_level:
            if isinstance(payload, dict):
                actions.append(payload)
    beats = script.get("beats")
    if isinstance(beats, list):
        for beat in beats:
            if not isinstance(beat, dict):
                continue
            beat_actions = beat.get("actions", [])
            if not isinstance(beat_actions, list):
                continue
            for payload in beat_actions:
                if isinstance(payload, dict):
                    actions.append(payload)
    return actions


def _extract_marked_ids_from_objects(objects: list[dict[str, Any]]) -> set[str]:
    marked: set[str] = set()
    for obj in objects:
        object_id = str(obj.get("id", "")).strip()
        if object_id.startswith("object_marked_"):
            marked.add(object_id)
    return marked


def _has_dangling_targets(script: dict[str, Any]) -> bool:
    objects = _collect_objects(script)
    actors = _collect_actors(script)
    valid_ids = {str(obj.get("id", "")).strip() for obj in objects}.union(
        {str(actor.get("id", "")).strip() for actor in actors}
    )
    for action in _collect_actions(script):
        action_type = _normalize_action_type(action.get("type"))
        if action_type not in TARGET_REQUIRED_ACTIONS:
            continue
        target = str(action.get("target") or action.get("targetId") or "").strip()
        if not target:
            return True
        if target not in valid_ids:
            return True
    return False


def _compute_pred_confidence(script: dict[str, Any], runtime_policy_snapshot: dict[str, Any]) -> float:
    confidence_model = runtime_policy_snapshot.get("confidence_model", {})
    if not isinstance(confidence_model, dict):
        confidence_model = {}
    base = float(confidence_model.get("base", 0.5))
    actor_weight = float(confidence_model.get("actor_weight", 0.1))
    object_weight = float(confidence_model.get("object_weight", 0.05))
    action_weight = float(confidence_model.get("action_weight", 0.05))
    missing_action_penalty = float(confidence_model.get("missing_action_penalty", 0.1))
    max_actor_bonus = int(confidence_model.get("max_actor_bonus", 3))
    max_object_bonus = int(confidence_model.get("max_object_bonus", 5))
    max_action_bonus = int(confidence_model.get("max_action_bonus", 5))

    actor_count = len(_collect_actors(script))
    object_count = len(_collect_objects(script))
    action_count = len(_collect_actions(script))

    score = base
    score += min(actor_count, max_actor_bonus) * actor_weight
    score += min(object_count, max_object_bonus) * object_weight
    score += min(action_count, max_action_bonus) * action_weight
    if action_count == 0:
        score -= missing_action_penalty
    if score < 0.0:
        return 0.0
    if score > 1.0:
        return 1.0
    return score


def replay_runtime_policy(
    predicted_script: dict[str, Any] | None,
    *,
    expected_marked_object_ids: list[str],
    runtime_policy_inputs: dict[str, Any],
    runtime_policy_snapshot: dict[str, Any],
) -> RuntimePolicyDecision:
    if predicted_script is None:
        return RuntimePolicyDecision(
            decision="reject",
            outcome="fallback_full",
            reason="predicted_script_missing",
            signals={"policy_inputs_missing": True},
        )

    try:
        rule_confidence = float(runtime_policy_inputs["rule_confidence"])
        rule_object_count = int(runtime_policy_inputs["rule_object_count"])
        rule_action_count = int(runtime_policy_inputs["rule_action_count"])
        rule_has_dangling_targets = bool(runtime_policy_inputs["rule_has_dangling_targets"])
        rule_matched_marked_object_count = int(runtime_policy_inputs["rule_matched_marked_object_count"])
        mentioned_marked_object_ids = [
            str(item).strip() for item in runtime_policy_inputs.get("mentioned_marked_object_ids", []) if str(item).strip()
        ]
    except (KeyError, TypeError, ValueError):
        return RuntimePolicyDecision(
            decision="reject",
            outcome="fallback_full",
            reason="policy_inputs_missing",
            signals={"policy_inputs_missing": True},
        )

    actions = _collect_actions(predicted_script)
    objects = _collect_objects(predicted_script)
    beats = predicted_script.get("beats", [])
    has_beats = isinstance(beats, list) and len(beats) > 0
    pred_marked_ids = _extract_marked_ids_from_objects(objects)
    expected_marked = {item for item in expected_marked_object_ids if item}
    mentioned_marked = set(mentioned_marked_object_ids) if mentioned_marked_object_ids else expected_marked
    pred_matched_marked_object_count = len(pred_marked_ids.intersection(mentioned_marked))
    pred_unresolved_mentioned_marked_objects = bool(mentioned_marked) and pred_matched_marked_object_count < len(mentioned_marked)
    pred_has_dangling_targets = _has_dangling_targets(predicted_script)
    pred_confidence = _compute_pred_confidence(predicted_script, runtime_policy_snapshot)

    signals = {
        "pred_actions_empty": len(actions) == 0,
        "pred_object_count": len(objects),
        "pred_action_count": len(actions),
        "pred_has_beats": has_beats,
        "pred_has_dangling_targets": pred_has_dangling_targets,
        "pred_matched_marked_object_count": pred_matched_marked_object_count,
        "pred_unresolved_mentioned_marked_objects": pred_unresolved_mentioned_marked_objects,
        "pred_confidence": pred_confidence,
        "rule_confidence": rule_confidence,
        "rule_object_count": rule_object_count,
        "rule_action_count": rule_action_count,
        "rule_has_dangling_targets": rule_has_dangling_targets,
        "rule_matched_marked_object_count": rule_matched_marked_object_count,
    }

    if signals["pred_actions_empty"]:
        return RuntimePolicyDecision("reject", "fallback_full", "pred_actions_empty", signals)
    if pred_matched_marked_object_count < rule_matched_marked_object_count:
        if has_beats and rule_object_count > 0:
            return RuntimePolicyDecision("merge", "fallback_partial", "marked_object_loss_with_merge_available", signals)
        return RuntimePolicyDecision("reject", "fallback_full", "marked_object_loss", signals)
    if pred_unresolved_mentioned_marked_objects:
        return RuntimePolicyDecision("reject", "fallback_full", "unresolved_mentioned_marked_objects", signals)
    if len(objects) < rule_object_count and rule_object_count > 0:
        if has_beats:
            return RuntimePolicyDecision("merge", "fallback_partial", "object_count_below_rule", signals)
        return RuntimePolicyDecision("reject", "fallback_full", "object_count_below_rule_without_beats", signals)
    if len(actions) + 1 < rule_action_count:
        return RuntimePolicyDecision("reject", "fallback_full", "action_count_below_rule", signals)
    if pred_has_dangling_targets and not rule_has_dangling_targets:
        if rule_object_count > 0:
            return RuntimePolicyDecision("merge", "fallback_partial", "new_dangling_targets_with_merge_available", signals)
        return RuntimePolicyDecision("reject", "fallback_full", "new_dangling_targets", signals)
    if pred_confidence < CRITICAL_MIN_CONFIDENCE:
        return RuntimePolicyDecision("reject", "fallback_full", "pred_confidence_critically_low", signals)
    return RuntimePolicyDecision("accept", "llm_only", "accepted_by_mirror_policy", signals)
